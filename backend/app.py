from __future__ import annotations
import hashlib
import hmac
import json
import os
import logging
from io import BytesIO
from datetime import UTC, date, datetime
from pathlib import Path
from typing import Callable, Literal
from uuid import uuid4

from dotenv import load_dotenv
import httpx
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pypdf import PdfReader

PROJECT_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(PROJECT_ROOT / ".env", override=False)
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from backend.advisor.context import fetch_student_context
from backend.advisor.graph import advisor_graph
from backend.advisor.knowledge_graph import create_knowledge_graph
from backend.advisor.llm import AdvisorConfigurationError
from backend.advisor.models import (
    AdvisorRequest,
    AdvisorResponse,
    AdvisorVoiceResponse,
)
from backend.advisor.voice import (
    VoiceConfigurationError,
    VoiceProcessingError,
    decode_audio,
    encode_audio,
    synthesize_speech,
    transcribe_audio,
)
from backend.progress.models import (
    CourseTwin,
    Risk,
    StudentTwin,
    WhatIfRequest,
    WhatIfResponse,
)
from backend.progress.narrative import generate_weekly_narrative
from backend.progress.scheduler import run_analysis_cycle
from backend.progress.scoring import leaderboard
from backend.progress.service import build_student_twin
from backend.planner.service import build_semester_plan
from backend.progress_agent.graph import (
    StudentNotFoundError,
    build_progress_graph,
)
from backend.simulation.what_if import run_assessment_grade_scenario
from database.repository import Student, StudentRepository
from database.postgres_repository import PostgresStudentRepository
from database.portal_pdfs import PortalPdfStore
from workspace.manager import ToolUnavailableError, WorkspaceManager


class WorkspaceRequest(BaseModel):
    student_id: str = Field(min_length=1, max_length=64)
    course: str = Field(min_length=1, max_length=160)


class WorkspaceResponse(BaseModel):
    student_id: str
    course: str
    path: str
    opened: bool = False


class ScoreAchievementRequest(BaseModel):
    achievement_id: str = Field(min_length=1, max_length=100)
    kind: Literal["project", "award"]
    title: str = Field(min_length=1, max_length=160)
    week_number: int = Field(ge=1, le=52)


class PortalGradebookRowRequest(BaseModel):
    student_id: str = Field(min_length=1, max_length=64)
    coursework_mark: float = Field(ge=0, le=10)
    week7_exam_mark: float = Field(ge=0, le=30)
    week12_exam_mark: float = Field(ge=0, le=20)
    final_exam_mark: float = Field(ge=0, le=40)


class PortalGradebookUpdateRequest(BaseModel):
    semester: str = Field(min_length=1, max_length=64)
    rows: list[PortalGradebookRowRequest] = Field(min_length=1)


class PortalNotificationReadRequest(BaseModel):
    notification_ids: list[str] = Field(max_length=200)
    read: bool = True


class PortalMessageCreateRequest(BaseModel):
    sender_type: Literal["student", "staff"]
    sender_id: str = Field(min_length=1, max_length=64)
    recipient_type: Literal["student", "staff"] | None = None
    recipient_id: str | None = Field(default=None, max_length=64)
    is_broadcast: bool = False
    body: str = Field(min_length=1, max_length=4000)


class PortalMessageReadRequest(BaseModel):
    actor_type: Literal["student", "staff"]
    actor_id: str = Field(min_length=1, max_length=64)
    message_ids: list[str] = Field(max_length=200)


class PortalStaffLoginRequest(BaseModel):
    staff_id: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=256)


class WeeklyPlanStatusRequest(BaseModel):
    status: Literal["pending", "completed"]


class PortalAttendanceRowRequest(BaseModel):
    student_id: str = Field(min_length=1, max_length=64)
    status: Literal["Present", "Absent", "Excused", "Late"]


class PortalAttendanceUpdateRequest(BaseModel):
    session_date: date
    rows: list[PortalAttendanceRowRequest] = Field(min_length=1)


GRADE_SCALE = [
    ("A+", 4.0, 97),
    ("A", 4.0, 93),
    ("A-", 3.7, 90),
    ("B+", 3.3, 87),
    ("B", 3.0, 83),
    ("B-", 2.7, 80),
    ("C+", 2.3, 77),
    ("C", 2.0, 73),
    ("C-", 1.7, 70),
    ("D+", 1.3, 67),
    ("D", 1.0, 63),
    ("D-", 0.7, 60),
    ("F", 0.0, 0),
]

GRADE_POINTS = {letter: points for letter, points, _ in GRADE_SCALE}
PDF_MAX_BYTES = 10 * 1024 * 1024
logger = logging.getLogger(__name__)


def _weighted_total(record: dict[str, object]) -> float:
    fields = ("coursework_mark", "week7_exam_mark", "week12_exam_mark", "final_exam_mark")
    return round(sum(float(record.get(field, 0) or 0) for field in fields), 2)


def _score_to_grade(total: float) -> tuple[str, float]:
    for letter, gpa_points, minimum in GRADE_SCALE:
        if total >= minimum:
            return letter, gpa_points
    return "F", 0.0


def _enrich_grade_record(record: dict[str, object]) -> dict[str, object]:
    fields = ("coursework_mark", "week7_exam_mark", "week12_exam_mark", "final_exam_mark")
    marks = {
        field: round(float(value), 2) if (value := record.get(field)) is not None else None
        for field in fields
    }
    grade_source = str(record.get("grade_source") or "")
    if not grade_source:
        grade_source = "gradebook" if any(value is not None for value in marks.values()) else "none"

    total_score: float | None = None
    letter_grade: str | None = None
    gpa_points: float | None = None
    if grade_source == "gradebook":
        total_score = _weighted_total(marks)
        # A zero is the gradebook's current placeholder for an exam that has
        # not been entered. Do not turn partial coursework into a failing final
        # grade; U means the result is still unfinalized and is excluded from GPA.
        final_mark = marks["final_exam_mark"]
        if final_mark is None or final_mark <= 0:
            letter_grade = "U"
        else:
            letter_grade, gpa_points = _score_to_grade(total_score)
    else:
        stored_letter = record.get("stored_letter_grade")
        if stored_letter:
            letter_grade = str(stored_letter).strip().upper()
            gpa_points = GRADE_POINTS.get(letter_grade)

    return {
        **record,
        **marks,
        "total_score": total_score,
        "letter_grade": letter_grade,
        "gpa_points": gpa_points,
        "grade_source": grade_source,
        "grade_posted": letter_grade is not None and letter_grade != "U",
    }


def _standing_for_gpa(gpa: float) -> str:
    if gpa >= 3.7:
        return "Dean's List"
    if gpa >= 2.0:
        return "Good Standing"
    return "Academic Probation"


def _semester_summaries(records: list[dict[str, object]]) -> list[dict[str, object]]:
    grouped: dict[str, list[dict[str, object]]] = {}
    for record in records:
        semester = str(record["semester"])
        grouped.setdefault(semester, []).append(record)

    summaries = []
    for semester, semester_records in grouped.items():
        graded_records = [
            record for record in semester_records if record.get("gpa_points") is not None
        ]
        gpa = (
            round(
                sum(float(record["gpa_points"]) for record in graded_records)
                / len(graded_records),
                2,
            )
            if graded_records
            else None
        )
        standing = (
            "In Progress"
            if any(str(record.get("enrollment_status", "Current")) != "Completed" for record in semester_records)
            else _standing_for_gpa(gpa or 0)
        )
        summaries.append(
            {
                "semester": semester,
                "gpa": gpa,
                "courses_graded": len(graded_records),
                "standing": standing,
            }
        )
    return summaries


def _portal_notifications(
    repository: StudentRepository | PostgresStudentRepository, student_id: str
) -> list[dict[str, object]]:
    report = repository.get_student_portal_grade_report(student_id)
    if report is None:
        raise HTTPException(status_code=404, detail="Student not found")

    read_ids = repository.get_read_notification_ids(student_id)
    items: list[dict[str, object]] = []
    for stored in repository.get_stored_notifications(student_id):
        stored_notification_id = f"stored:{stored['notification_id']}"
        items.append(
            {
                "id": stored_notification_id,
                "type": stored["type"],
                "category": stored["type"].capitalize(),
                "title": stored["message"],
                "body": "",
                "timestamp": str(stored["created_at"]),
                "read": bool(stored["is_read"]),
            }
        )
    for alert in repository.get_attendance_alerts(student_id):
        absence_count = int(alert["absence_count"])
        dropped = bool(alert.get("automatically_dropped"))
        notification_id = (
            f"attendance:{alert['course_id']}:{alert['semester']}:{absence_count}"
        )
        items.append(
            {
                "id": notification_id,
                "type": "attendance",
                "category": "Attendance",
                "title": (
                    f"Course dropped: {alert['course_name']}"
                    if dropped
                    else f"Attendance warning: {alert['course_name']}"
                ),
                "body": (
                    "This course was automatically dropped after your fourth "
                    "recorded absence."
                    if dropped
                    else (
                        "You have missed 3 lectures. One more absence will "
                        "automatically drop this course."
                        if absence_count == 3
                        else f"You have {absence_count} recorded absences. The "
                        "attendance limit has been reached."
                    )
                ),
                "timestamp": str(alert["semester"]),
                "read": notification_id in read_ids,
            }
        )

    twin = build_student_twin(repository, student_id)
    if twin is not None:
        for course in twin.courses:
            for risk in course.risks:
                notification_id = (
                    f"risk:{course.course_id}:{risk.code}:{twin.current_week}"
                )
                items.append(
                    {
                        "id": notification_id,
                        "type": "risk",
                        "category": "System",
                        "title": f"{course.course_name} needs attention",
                        "body": risk.message,
                        "timestamp": (
                            f"Week {twin.current_week} · {risk.severity.upper()} RISK"
                        ),
                        "read": notification_id in read_ids,
                    }
                )

    for raw_record in report["records"]:
        record = _enrich_grade_record(raw_record)
        if (
            record["grade_source"] != "gradebook"
            or record["total_score"] is None
            or not record["grade_posted"]
        ):
            continue
        total = float(record["total_score"])
        notification_id = (
            f"grade:{record['course_id']}:{record['semester']}:{total:.2f}"
        )
        items.append(
            {
                "id": notification_id,
                "type": "grade",
                "category": "Grades",
                "title": f"Grade posted: {record['course_name']}",
                "body": f"{record['letter_grade']} · {total:.1f}% overall",
                "timestamp": str(record["semester"]),
                "read": notification_id in read_ids,
            }
        )

    if twin is not None:
        exam_types = {"midterm", "final", "exam"}
        for course in twin.courses:
            for assessment in course.assessments:
                if assessment.assessment_type not in exam_types:
                    continue
                if (
                    assessment.mark is not None
                    and assessment.due_week <= twin.current_week
                ):
                    continue
                if not twin.current_week <= assessment.due_week <= twin.current_week + 2:
                    continue
                weeks_left = assessment.due_week - twin.current_week
                when = (
                    "this week"
                    if weeks_left == 0
                    else "next week"
                    if weeks_left == 1
                    else f"in {weeks_left} weeks"
                )
                notification_id = (
                    f"exam-preparation:{assessment.assessment_id}:week-{twin.current_week}"
                )
                items.append(
                    {
                        "id": notification_id,
                        "type": "exam",
                        "category": "Registration",
                        "title": f"Start studying for {assessment.name}",
                        "body": (
                            f"Prepare now for {course.course_name}. The exam is in "
                            f"week {assessment.due_week} ({when})."
                        ),
                        "timestamp": f"Week {twin.current_week} reminder",
                        "read": notification_id in read_ids,
                    }
                )
    return items


def _risk_study_task(
    course: CourseTwin, risk: Risk, timing: str
) -> tuple[str, str]:
    related_assessment = next(
        (
            assessment
            for assessment in course.assessments
            if assessment.assessment_id in risk.related_assessment_ids
        ),
        None,
    )
    assessment_name = related_assessment.name if related_assessment else "exam"
    lecture_count = len(risk.related_lecture_ids)

    tasks = {
        "low_midterm": (
            f"Review {assessment_name} mistakes",
            f"{timing} · 45 min — revisit the covered topics, redo difficult "
            "questions, and write down 3 weak points.",
        ),
        "midterm_coursework_drop": (
            f"Practice {assessment_name} questions",
            f"{timing} · 45 min — solve 5 exam-style questions without notes, "
            "then check and correct every mistake.",
        ),
        "low_assignment_average": (
            "Strengthen assignment skills",
            f"{timing} · 40 min — redo one weak assignment section and compare "
            "your solution with the course material.",
        ),
        "low_lab_average": (
            "Practice the latest lab",
            f"{timing} · 45 min — repeat the latest lab exercise from scratch "
            "and note anything you still need to ask about.",
        ),
        "lecture_backlog": (
            "Catch up on pending lectures",
            f"{timing} · 45 min — finish the next incomplete lecture, make a "
            "short summary, and answer 3 recall questions."
            + (f" Start with one of the {lecture_count} pending lectures." if lecture_count else ""),
        ),
        "missed_assessment": (
            "Check overdue assessment work",
            f"{timing} · 20 min — confirm the submission or grade status, then "
            "write the exact next action and deadline.",
        ),
        "repeated_poor_assessments": (
            "Run a focused revision session",
            f"{timing} · 45 min — choose the two weakest topics, review one "
            "worked example for each, then solve one question alone.",
        ),
        "significant_decline": (
            "Reset this course's study plan",
            f"{timing} · 25 min — list unfinished work, choose the top two "
            "priorities, and reserve study blocks for both.",
        ),
        "steady_decline": (
            "Reset this course's study plan",
            f"{timing} · 25 min — list unfinished work, choose the top two "
            "priorities, and reserve study blocks for both.",
        ),
        "incomplete_exam_coverage": (
            f"Complete {assessment_name} coverage",
            f"{timing} · 50 min — finish one uncovered topic, summarize it in "
            "5 lines, and solve 3 related questions.",
        ),
        "missing_coursework_window": (
            f"Start {assessment_name}",
            f"{timing} · 45 min — review the requirements, finish the next "
            "covered topic, and begin the first section.",
        ),
        "deadline_cluster": (
            "Plan upcoming deadlines",
            f"{timing} · 20 min — split each assessment into small steps and "
            "assign one step to every available study block.",
        ),
        "lecture_pace_slowdown": (
            "Restore your lecture pace",
            f"{timing} · 40 min — complete the next lecture and schedule the "
            "following one before the end of the week.",
        ),
    }
    return tasks.get(
        risk.code,
        (
            "Strengthen this course this week",
            f"{timing} · 40 min — review your weakest topic, solve 3 practice "
            "questions, and record what still needs work.",
        ),
    )


def _weekly_plan_candidates(student_id: str, twin: StudentTwin) -> list[dict[str, object]]:
    candidates: list[dict[str, object]] = []
    timing_slots = ("Today", "Tomorrow", "Later this week")
    for course in twin.courses:
        for risk in course.risks[:2]:
            source_key = f"risk:{course.course_id}:{risk.code}"
            timing = timing_slots[min(len(candidates), len(timing_slots) - 1)]
            title, detail = _risk_study_task(course, risk, timing)
            candidates.append(
                {
                    "source_key": source_key,
                    "course_id": course.course_id,
                    "course_name": course.course_name,
                    "title": title,
                    "detail": detail,
                    "task_type": "risk",
                }
            )

        for assessment in course.assessments:
            if (
                assessment.mark is not None
                or assessment.due_week < twin.current_week
                or assessment.due_week > twin.current_week + 1
            ):
                continue
            source_key = f"assessment:{assessment.assessment_id}"
            timing = timing_slots[min(len(candidates), len(timing_slots) - 1)]
            candidates.append(
                {
                    "source_key": source_key,
                    "course_id": course.course_id,
                    "course_name": course.course_name,
                    "title": f"Prepare for {assessment.name}",
                    "detail": (
                        f"{timing} · 60 min — review the requirements, complete "
                        "the next section, and leave time for a final check."
                        if assessment.due_week == twin.current_week
                        else f"{timing} · 45 min — review the covered material "
                        "and begin the first practice or work section."
                    ),
                    "task_type": "assessment",
                }
            )

    items: list[dict[str, object]] = []
    for position, candidate in enumerate(candidates[:6], start=1):
        identity = "|".join(
            (
                student_id,
                twin.semester,
                str(twin.current_week),
                str(candidate.pop("source_key")),
            )
        )
        task_id = f"weekly:{hashlib.sha256(identity.encode()).hexdigest()[:24]}"
        items.append({"task_id": task_id, "position": position, **candidate})
    return items


def _enrolled_course(student: Student, requested_course: str) -> str:
    normalized = requested_course.strip().casefold()
    for course in student.courses:
        if course.casefold() == normalized:
            return course
    raise HTTPException(status_code=400, detail="Course is not enrolled for this student")


def _public_material(document: dict[str, object], student_id: str) -> dict[str, object]:
    result = {
        key: value
        for key, value in document.items()
        if key not in {"source_archive_path", "storage_path"}
    }
    for field in ("learning_objectives_json", "keywords_json"):
        value = result.get(field)
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except json.JSONDecodeError:
                value = []
        result[field.removesuffix("_json")] = value or []
        result.pop(field, None)
    result["download_url"] = (
        f"/portal/students/{student_id}/materials/{document['document_id']}"
    )
    return result


def create_app(
    *,
    db_path: Path | None = None,
    workspace_root: Path | None = None,
    material_storage_root: Path | None = None,
    launcher: Callable[[Path], None] | None = None,
) -> FastAPI:
    student_workspace_root = workspace_root or Path(
        os.environ.get(
            "AEGIS_WORKSPACE_ROOT", PROJECT_ROOT / "workspace" / "students"
        )
    )
    material_storage_root = (
        material_storage_root
        or Path(
            os.environ.get(
                "AEGIS_MATERIAL_STORAGE_ROOT",
                PROJECT_ROOT / "workspace" / "materials",
            )
        )
    ).resolve()
    database_url = os.environ.get("DATABASE_URL")
    if database_url and db_path is None:
        # The Database branch's normalized PostgreSQL/Supabase schema is the
        # production source. db_path remains an explicit SQLite test override.
        repository = PostgresStudentRepository(database_url)
        print(f"AegisOS API connected to PostgreSQL: {database_url.split('@')[-1].split('/')[0]}")
    else:
        database_path = db_path or Path(
            os.environ.get("AEGIS_DB_PATH", PROJECT_ROOT / "database" / "aegisos.db")
        )
        repository = StudentRepository(database_path)
        print(f"AegisOS API using SQLite database: {database_path}")
    repository.initialize()
    knowledge_graph = create_knowledge_graph()
    progress_graph = build_progress_graph(repository)
    manager = WorkspaceManager(student_workspace_root, launcher=launcher)

    api = FastAPI(title="AegisOS EDU API", version="1.1.0")
    api.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["GET", "POST", "PUT", "DELETE"],
        allow_headers=["Content-Type", "Authorization"],
    )

    staff_names = {"104217": "Dr. Omar Fathallah"}
    allowed_staff_ids = {
        identifier.strip()
        for identifier in os.environ.get("AEGIS_STAFF_IDS", "104217").split(",")
        if identifier.strip()
    }
    pdf_store = PortalPdfStore(repository)
    pdf_storage_root = material_storage_root / "portal-pdfs"

    def portal_actor(authorization: str | None = Header(default=None)) -> dict[str, str]:
        """Resolve a Supabase access token to a server-checked portal identity."""
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Sign in to access PDFs")
        token = authorization[7:].strip()
        if not token:
            raise HTTPException(status_code=401, detail="Sign in to access PDFs")
        supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
        anon_key = os.environ.get("SUPABASE_ANON_KEY", "")
        if not supabase_url or not anon_key:
            raise HTTPException(status_code=503, detail="Supabase Auth is not configured on the API")
        try:
            response = httpx.get(
                f"{supabase_url}/auth/v1/user",
                headers={"apikey": anon_key, "Authorization": f"Bearer {token}"},
                timeout=5,
            )
        except httpx.RequestError as error:
            raise HTTPException(status_code=503, detail="Authentication service unavailable") from error
        if response.status_code != 200:
            raise HTTPException(status_code=401, detail="Invalid or expired session")
        user = response.json()
        email = str(user.get("email") or "").lower()
        metadata = user.get("app_metadata") or {}
        auth_user_id = str(user.get("id") or "")
        for role, domain in (("staff", "staff.aegisos.local"),
                             ("student", "students.aegisos.local")):
            suffix = f"@{domain}"
            if email.endswith(suffix):
                actor_id = email[:-len(suffix)]
                if not actor_id or "@" in actor_id:
                    break
                if (role == "staff" and actor_id in allowed_staff_ids
                        and metadata.get("portal_role") == "staff"
                        and metadata.get("portal_id") == actor_id):
                    return {"role": role, "id": actor_id}
                if role == "student":
                    student_linked = (
                        metadata.get("portal_role") == "student"
                        and metadata.get("portal_id") == actor_id
                    ) or pdf_store.is_registered_student_auth(auth_user_id, actor_id)
                    if student_linked and repository.get_student(actor_id) is not None:
                        return {"role": role, "id": actor_id}
        raise HTTPException(status_code=403, detail="Account is not authorized for this portal")

    def require_staff(actor: dict[str, str] = Depends(portal_actor)) -> str:
        if actor["role"] != "staff":
            raise HTTPException(status_code=403, detail="Staff access required")
        return actor["id"]

    def require_student(actor: dict[str, str] = Depends(portal_actor)) -> str:
        if actor["role"] != "student":
            raise HTTPException(status_code=403, detail="Student access required")
        return actor["id"]

    def public_pdf(pdf: dict[str, object]) -> dict[str, object]:
        return {
            key: (value.isoformat() if isinstance(value, datetime) else value)
            for key, value in pdf.items()
            if key not in {"storage_path"}
        }

    def checked_pdf(pdf_id: str, actor_id: str, role: str) -> dict[str, object]:
        # Visibility is checked against the current enrollment at every request.
        visible = pdf_store.list_staff(actor_id) if role == "staff" else pdf_store.list_student(actor_id)
        pdf = next((item for item in visible if item["pdf_id"] == pdf_id), None)
        if pdf is None:
            raise HTTPException(status_code=404, detail="PDF not found")
        return pdf

    def pdf_response(pdf: dict[str, object], download: bool) -> FileResponse:
        source = (pdf_storage_root / str(pdf["storage_path"])).resolve()
        if not source.is_relative_to(pdf_storage_root) or not source.is_file():
            raise HTTPException(status_code=404, detail="PDF file unavailable")
        return FileResponse(
            source,
            media_type="application/pdf",
            filename=str(pdf["original_filename"]) if download else None,
            content_disposition_type="attachment" if download else "inline",
            headers={"X-Content-Type-Options": "nosniff", "Content-Security-Policy": "sandbox"},
        )

    def messaging_participant(actor_type: str, actor_id: str) -> dict[str, str]:
        normalized_id = actor_id.strip()
        if actor_type == "student":
            student = repository.get_student(normalized_id)
            if student is None:
                raise HTTPException(status_code=404, detail="Student not found")
            return {
                "type": "student",
                "id": student.student_id,
                "name": student.name,
                "subtitle": f"Year {student.year} · {student.major}",
            }
        if normalized_id not in allowed_staff_ids:
            raise HTTPException(status_code=404, detail="Staff member not found")
        return {
            "type": "staff",
            "id": normalized_id,
            "name": staff_names.get(normalized_id, f"Staff {normalized_id}"),
            "subtitle": "Professor · Computer Engineering",
        }

    def enrich_message(message: dict[str, object]) -> dict[str, object]:
        result = dict(message)
        sender = messaging_participant(
            str(result["sender_type"]), str(result["sender_id"])
        )
        result["sender_name"] = sender["name"]
        if result.get("recipient_id") and result.get("recipient_type"):
            recipient = messaging_participant(
                str(result["recipient_type"]), str(result["recipient_id"])
            )
            result["recipient_name"] = recipient["name"]
        else:
            result["recipient_name"] = "All students"
        return result

    @api.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @api.get("/student/{student_id}")
    def get_student(student_id: str) -> dict[str, object]:
        student = repository.get_student(student_id)
        if student is None:
            raise HTTPException(status_code=404, detail="Student not found")
        return student.as_dict()

    @api.get("/messages/contacts")
    def get_message_contacts(actor_type: Literal["student", "staff"], actor_id: str) -> dict[str, object]:
        actor = messaging_participant(actor_type, actor_id)
        students = [
            {
                "type": "student",
                "id": student.student_id,
                "name": student.name,
                "subtitle": f"Year {student.year} · {student.major}",
            }
            for student in repository.get_registered_students()
            if not (actor_type == "student" and student.student_id == actor["id"])
        ]
        contacts = students
        if actor_type == "student":
            contacts = [
                messaging_participant("staff", identifier)
                for identifier in sorted(allowed_staff_ids)
            ] + students
        return {"actor": actor, "contacts": contacts}

    @api.get("/messages")
    def get_messages(actor_type: Literal["student", "staff"], actor_id: str) -> dict[str, object]:
        actor = messaging_participant(actor_type, actor_id)
        messages = [
            enrich_message(message)
            for message in repository.list_portal_messages(actor_type, actor["id"])
        ]
        return {"messages": messages}

    @api.post("/messages")
    def create_message(request: PortalMessageCreateRequest) -> dict[str, object]:
        sender = messaging_participant(request.sender_type, request.sender_id)
        body = request.body.strip()
        if not body:
            raise HTTPException(status_code=400, detail="Message cannot be empty")
        if request.is_broadcast:
            if request.sender_type != "staff":
                raise HTTPException(status_code=403, detail="Only staff can broadcast messages")
            recipient_type = None
            recipient_id = None
        else:
            if request.recipient_type is None or not request.recipient_id:
                raise HTTPException(status_code=400, detail="Choose a message recipient")
            recipient = messaging_participant(request.recipient_type, request.recipient_id)
            if request.sender_type == "staff" and recipient["type"] != "student":
                raise HTTPException(status_code=400, detail="Staff messages must be sent to students")
            recipient_type = recipient["type"]
            recipient_id = recipient["id"]
        message = repository.create_portal_message(
            {
                "message_id": str(uuid4()),
                "sender_type": sender["type"],
                "sender_id": sender["id"],
                "recipient_type": recipient_type,
                "recipient_id": recipient_id,
                "is_broadcast": request.is_broadcast,
                "body": body,
                "created_at": datetime.now(UTC).isoformat(),
                "read": True,
            }
        )
        return {"message": enrich_message(message)}

    @api.put("/messages/read")
    def mark_messages_read(request: PortalMessageReadRequest) -> dict[str, object]:
        actor = messaging_participant(request.actor_type, request.actor_id)
        visible = {
            str(message["message_id"])
            for message in repository.list_portal_messages(request.actor_type, actor["id"])
        }
        message_ids = [message_id for message_id in request.message_ids if message_id in visible]
        repository.mark_portal_messages_read(request.actor_type, actor["id"], message_ids)
        return {"read": message_ids}

    @api.get("/portal/pdfs/staff/courses")
    def get_pdf_instructor_courses(instructor_id: str = Depends(require_staff)) -> dict[str, object]:
        return {"courses": pdf_store.instructor_courses(instructor_id)}

    @api.get("/portal/pdfs/staff")
    def list_staff_pdfs(instructor_id: str = Depends(require_staff)) -> dict[str, object]:
        return {"pdfs": [public_pdf(item) for item in pdf_store.list_staff(instructor_id)]}

    @api.post("/portal/pdfs/staff", status_code=201)
    async def upload_staff_pdf(
        file: UploadFile = File(...),
        title: str = Form(...),
        description: str = Form(""),
        course_id: str = Form(...),
        instructor_id: str = Depends(require_staff),
    ) -> dict[str, object]:
        clean_title = title.strip()
        clean_description = description.strip()
        clean_course_id = course_id.strip()
        if not clean_title or len(clean_title) > 160:
            raise HTTPException(status_code=422, detail="Title must be 1–160 characters")
        if len(clean_description) > 2000:
            raise HTTPException(status_code=422, detail="Description must be at most 2000 characters")
        if not clean_course_id:
            raise HTTPException(status_code=422, detail="Choose a course for this PDF")
        if clean_course_id not in {
            item["course_id"] for item in pdf_store.instructor_courses(instructor_id)
        }:
            raise HTTPException(status_code=403, detail="You are not assigned to this course")
        original_name = (file.filename or "").replace("\\", "/").split("/")[-1]
        if not original_name.lower().endswith(".pdf") or not original_name or len(original_name) > 255:
            raise HTTPException(status_code=422, detail="Choose a PDF file")
        if file.content_type not in ("application/pdf", "application/octet-stream"):
            raise HTTPException(status_code=422, detail="Choose a PDF file")
        contents = await file.read(PDF_MAX_BYTES + 1)
        await file.close()
        if len(contents) > PDF_MAX_BYTES:
            raise HTTPException(status_code=413, detail="PDF must be 10 MB or smaller")
        if not contents.startswith(b"%PDF-"):
            raise HTTPException(status_code=422, detail="File is not a valid PDF")
        try:
            reader = PdfReader(BytesIO(contents), strict=True)
            if reader.is_encrypted or len(reader.pages) < 1:
                raise ValueError("Encrypted or empty PDF")
        except Exception as error:
            raise HTTPException(status_code=422, detail="File is not a valid, readable PDF") from error
        pdf_id = str(uuid4())
        storage_path = f"{pdf_id}.pdf"
        pdf_storage_root.mkdir(parents=True, exist_ok=True)
        destination = pdf_storage_root / storage_path
        destination.write_bytes(contents)
        record = {
            "pdf_id": pdf_id,
            "instructor_id": instructor_id,
            "course_id": clean_course_id,
            "title": clean_title,
            "description": clean_description or None,
            "original_filename": original_name,
            "storage_path": storage_path,
            "size_bytes": len(contents),
            "uploaded_at": datetime.now(UTC).isoformat(),
        }
        try:
            pdf_store.insert(record)
        except Exception:
            destination.unlink(missing_ok=True)
            raise
        result = pdf_store.get(pdf_id)
        return {"pdf": public_pdf(result or record)}

    @api.get("/portal/pdfs/student")
    def list_student_pdfs(student_id: str = Depends(require_student)) -> dict[str, object]:
        return {"pdfs": [public_pdf(item) for item in pdf_store.list_student(student_id)]}

    @api.get("/portal/pdfs/student/{pdf_id}/file")
    def get_student_pdf_file(
        pdf_id: str, download: bool = False, student_id: str = Depends(require_student)
    ) -> FileResponse:
        return pdf_response(checked_pdf(pdf_id, student_id, "student"), download)

    @api.get("/portal/pdfs/staff/{pdf_id}/file")
    def get_staff_pdf_file(
        pdf_id: str, download: bool = False, instructor_id: str = Depends(require_staff)
    ) -> FileResponse:
        return pdf_response(checked_pdf(pdf_id, instructor_id, "staff"), download)

    @api.delete("/portal/pdfs/staff/{pdf_id}", status_code=204)
    def delete_staff_pdf(pdf_id: str, instructor_id: str = Depends(require_staff)) -> None:
        pdf = checked_pdf(pdf_id, instructor_id, "staff")
        if not pdf_store.delete_owned(pdf_id, instructor_id):
            raise HTTPException(status_code=404, detail="PDF not found")
        source = (pdf_storage_root / str(pdf["storage_path"])).resolve()
        if source.is_relative_to(pdf_storage_root):
            try:
                source.unlink(missing_ok=True)
            except OSError:
                logger.exception("Could not remove deleted PDF file %s", pdf_id)

    @api.get("/portal/courses")
    def get_portal_courses() -> dict[str, object]:
        return {"courses": repository.list_portal_courses()}

    @api.get("/portal/courses/{course_id}/grades")
    def get_portal_course_gradebook(
        course_id: str, semester: str | None = None
    ) -> dict[str, object]:
        gradebook = repository.get_portal_course_gradebook(course_id, semester)
        if gradebook is None:
            raise HTTPException(status_code=404, detail="Course not found")
        rows = [_enrich_grade_record(row) for row in gradebook["rows"]]
        return {
            "course": {
                "course_id": gradebook["course_id"],
                "course_name": gradebook["course_name"],
                "semester": gradebook["semester"],
            },
            "rows": rows,
        }

    @api.get("/portal/courses/{course_id}/attendance")
    def get_portal_course_attendance(
        course_id: str, session_date: date
    ) -> dict[str, object]:
        try:
            attendance = repository.get_portal_course_attendance(
                course_id, session_date
            )
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        if attendance is None:
            raise HTTPException(
                status_code=404,
                detail="Course or semester not found for this attendance date",
            )
        return attendance

    @api.put("/portal/courses/{course_id}/attendance")
    def save_portal_course_attendance(
        course_id: str, request: PortalAttendanceUpdateRequest
    ) -> dict[str, object]:
        student_ids = [row.student_id for row in request.rows]
        if len(student_ids) != len(set(student_ids)):
            raise HTTPException(
                status_code=400,
                detail="Each student may appear only once in an attendance session",
            )
        try:
            attendance = repository.save_portal_course_attendance(
                course_id,
                request.session_date,
                [row.model_dump() for row in request.rows],
            )
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        if attendance is None:
            raise HTTPException(
                status_code=404,
                detail="Course or semester not found for this attendance date",
            )
        return attendance

    @api.put("/portal/courses/{course_id}/grades")
    def save_portal_course_gradebook(
        course_id: str, request: PortalGradebookUpdateRequest
    ) -> dict[str, object]:
        gradebook = repository.get_portal_course_gradebook(course_id, request.semester)
        if gradebook is None:
            raise HTTPException(status_code=404, detail="Course not found")
        valid_student_ids = {str(row["student_id"]) for row in gradebook["rows"]}
        unknown_student_ids = [
            row.student_id for row in request.rows if row.student_id not in valid_student_ids
        ]
        if unknown_student_ids:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown or unenrolled students: {', '.join(sorted(unknown_student_ids))}",
            )
        repository.save_portal_course_gradebook(
            course_id,
            request.semester,
            [row.model_dump() for row in request.rows],
        )
        refreshed = repository.get_portal_course_gradebook(course_id, request.semester)
        assert refreshed is not None
        return {
            "course": {
                "course_id": refreshed["course_id"],
                "course_name": refreshed["course_name"],
                "semester": refreshed["semester"],
            },
            "rows": [_enrich_grade_record(row) for row in refreshed["rows"]],
        }

    @api.get("/portal/students/{student_id}/grades")
    def get_portal_student_grades(student_id: str) -> dict[str, object]:
        report = repository.get_student_portal_grade_report(student_id)
        if report is None:
            raise HTTPException(status_code=404, detail="Student not found")
        records = [_enrich_grade_record(record) for record in report["records"]]
        return {
            "student": report["student"],
            "completed_courses": sum(
                1
                for record in records
                if str(record.get("enrollment_status", "")) == "Completed"
            ),
            "semesters": _semester_summaries(records),
            "records": records,
        }

    @api.get("/portal/students/{student_id}/courses")
    def get_portal_student_courses(student_id: str) -> dict[str, object]:
        result = repository.get_student_current_courses(student_id)
        if result is None:
            raise HTTPException(status_code=404, detail="Student not found")
        return result

    @api.get("/portal/students/{student_id}/materials")
    def get_portal_student_materials(
        student_id: str, course_id: str | None = None
    ) -> dict[str, object]:
        if repository.get_student(student_id) is None:
            raise HTTPException(status_code=404, detail="Student not found")
        documents = repository.list_student_materials(student_id, course_id)
        return {
            "student_id": student_id,
            "documents": [
                _public_material(document, student_id) for document in documents
            ],
        }

    @api.get("/portal/students/{student_id}/materials/search")
    def search_portal_student_materials(
        student_id: str,
        q: str,
        course_id: str | None = None,
        limit: int = 8,
    ) -> dict[str, object]:
        if repository.get_student(student_id) is None:
            raise HTTPException(status_code=404, detail="Student not found")
        if not q.strip():
            raise HTTPException(status_code=400, detail="Search query is required")
        results = repository.search_student_materials(
            student_id,
            q,
            course_id=course_id,
            limit=max(1, min(limit, 20)),
        )
        for result in results:
            result.pop("storage_path", None)
            result["download_url"] = (
                f"/portal/students/{student_id}/materials/{result['document_id']}"
            )
        return {"student_id": student_id, "query": q, "results": results}

    @api.get("/portal/students/{student_id}/materials/{document_id}")
    def download_portal_student_material(
        student_id: str, document_id: str
    ) -> FileResponse:
        if repository.get_student(student_id) is None:
            raise HTTPException(status_code=404, detail="Student not found")
        allowed = {
            str(document["document_id"]): document
            for document in repository.list_student_materials(student_id)
        }
        document = allowed.get(document_id)
        if document is None:
            raise HTTPException(status_code=404, detail="Material not found")
        source = (material_storage_root / str(document["storage_path"])).resolve()
        if not source.is_relative_to(material_storage_root) or not source.is_file():
            raise HTTPException(status_code=404, detail="Material file is unavailable")
        return FileResponse(
            source,
            media_type=str(document["mime_type"]),
            filename=str(document["original_filename"]),
        )

    @api.get("/portal/students/{student_id}/academics")
    def get_portal_student_academics(student_id: str) -> dict[str, object]:
        twin = build_student_twin(repository, student_id)
        if twin is None:
            raise HTTPException(status_code=404, detail="Student not found")
        report = repository.get_student_portal_grade_report(student_id)
        records = [_enrich_grade_record(record) for record in report["records"]] if report else []
        return {
            "student": twin.student.model_dump(),
            "semester": twin.semester,
            "current_week": twin.current_week,
            "courses": [course.model_dump() for course in twin.courses],
            "grades": {
                "completed_courses": sum(
                    1
                    for record in records
                    if str(record.get("enrollment_status", "")) == "Completed"
                ),
                "semesters": _semester_summaries(records),
                "records": records,
            },
        }

    @api.get("/portal/students/{student_id}/semester-plan")
    def get_portal_student_semester_plan(
        student_id: str,
        max_credits: int = 18,
        expected_term_gpa: float = 3.3,
    ) -> dict[str, object]:
        source = repository.get_semester_planner_source(student_id)
        if source is None:
            raise HTTPException(status_code=404, detail="Student not found")
        return build_semester_plan(
            source,
            max_credits=max_credits,
            expected_term_gpa=expected_term_gpa,
        )

    @api.get("/portal/students/{student_id}/notifications")
    def get_portal_student_notifications(student_id: str) -> dict[str, object]:
        return {"notifications": _portal_notifications(repository, student_id)}

    @api.put("/portal/students/{student_id}/notifications/read")
    def set_portal_student_notifications_read(
        student_id: str, request: PortalNotificationReadRequest
    ) -> dict[str, object]:
        if repository.get_student(student_id) is None:
            raise HTTPException(status_code=404, detail="Student not found")
        repository.set_notifications_read(
            student_id, request.notification_ids, request.read
        )
        return {"notifications": _portal_notifications(repository, student_id)}

    @api.get("/portal/students/{student_id}/weekly-plan")
    def get_student_weekly_plan(student_id: str) -> dict[str, object]:
        twin = build_student_twin(repository, student_id)
        if twin is None:
            raise HTTPException(status_code=404, detail="Student not found")
        repository.upsert_weekly_plan_items(
            student_id,
            twin.semester,
            twin.current_week,
            _weekly_plan_candidates(student_id, twin),
        )
        items = repository.get_weekly_plan_items(
            student_id, twin.semester, twin.current_week
        )
        return {
            "student_id": student_id,
            "semester": twin.semester,
            "current_week": twin.current_week,
            "items": items,
        }

    @api.put("/portal/students/{student_id}/weekly-plan/{task_id}")
    def set_student_weekly_plan_status(
        student_id: str, task_id: str, request: WeeklyPlanStatusRequest
    ) -> dict[str, object]:
        if repository.get_student(student_id) is None:
            raise HTTPException(status_code=404, detail="Student not found")
        item = repository.set_weekly_plan_item_status(
            student_id, task_id, request.status
        )
        if item is None:
            raise HTTPException(status_code=404, detail="Weekly plan item not found")
        return {"item": item}

    @api.get("/portal/staff/{staff_id}")
    def validate_portal_staff(staff_id: str) -> dict[str, object]:
        allowed_ids = {
            identifier.strip()
            for identifier in os.environ.get("AEGIS_STAFF_IDS", "104217").split(",")
            if identifier.strip()
        }
        if staff_id.strip() not in allowed_ids:
            raise HTTPException(status_code=404, detail="Staff member not found")
        return {"staff_id": staff_id.strip(), "valid": True}

    @api.post("/portal/staff/login")
    def login_portal_staff(request: PortalStaffLoginRequest) -> dict[str, object]:
        staff_member = messaging_participant("staff", request.staff_id)
        expected_password = os.environ.get(
            "AEGIS_STAFF_DEMO_PASSWORD", "demo1234"
        )
        if request.password != expected_password:
            raise HTTPException(status_code=401, detail="Incorrect ID or password")
        return {
            "staff_id": staff_member["id"],
            "name": staff_member["name"],
            "valid": True,
        }

    @api.post("/workspace/create", response_model=WorkspaceResponse)
    def create_workspace(request: WorkspaceRequest) -> WorkspaceResponse:
        student = repository.get_student(request.student_id)
        if student is None:
            raise HTTPException(status_code=404, detail="Student not found")
        course = _enrolled_course(student, request.course)
        path = manager.create_course_workspace(student.student_id, course)
        return WorkspaceResponse(
            student_id=student.student_id,
            course=course,
            path=str(path),
        )

    @api.post("/workspace/vscode", response_model=WorkspaceResponse)
    def open_vscode(request: WorkspaceRequest) -> WorkspaceResponse:
        student = repository.get_student(request.student_id)
        if student is None:
            raise HTTPException(status_code=404, detail="Student not found")
        course = _enrolled_course(student, request.course)
        path = manager.create_course_workspace(student.student_id, course)
        try:
            manager.open_vscode(path)
        except ToolUnavailableError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error
        return WorkspaceResponse(
            student_id=student.student_id,
            course=course,
            path=str(path),
            opened=True,
        )

    @api.post("/advisor", response_model=AdvisorResponse)
    def ask_advisor(request: AdvisorRequest) -> AdvisorResponse:
        student = repository.get_student(request.student_id)
        if student is None:
            raise HTTPException(status_code=404, detail="Student not found")

        history = [message.model_dump() for message in request.history]
        context = fetch_student_context(
            repository, request.student_id,
            message=request.message,
            knowledge_graph=knowledge_graph,
        )

        try:
            result = advisor_graph.invoke(
                {
                    "message": request.message,
                    "history": history,
                    "student": student.as_dict(),
                    "context": context,
                    "language": request.language,
                }
            )
        except AdvisorConfigurationError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error
        except Exception as error:
            raise HTTPException(
                status_code=502,
                detail="Advisor AI could not complete the request.",
            ) from error

        return AdvisorResponse(
            intent=result["intent"],
            response=result["response"],
            language=request.language,
        )

    def _run_advisor_with_voice(
        student_id: str, transcript: str, language: str, history: list[dict]
    ) -> dict[str, object]:
        student = repository.get_student(student_id)
        if student is None:
            raise HTTPException(status_code=404, detail="Student not found")
        context = fetch_student_context(
            repository, student_id,
            message=transcript,
            knowledge_graph=knowledge_graph,
        )
        try:
            result = advisor_graph.invoke(
                {
                    "message": transcript,
                    "history": history,
                    "student": student.as_dict(),
                    "context": context,
                    "language": language,
                }
            )
        except AdvisorConfigurationError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error
        except Exception as error:
            raise HTTPException(
                status_code=502,
                detail="Advisor AI could not complete the request.",
            ) from error
        return result

    @api.post("/advisor/voice", response_model=AdvisorVoiceResponse)
    async def advisor_voice(
        student_id: str = Form(...),
        language: str = Form(default="english"),
        audio: UploadFile = File(...),
    ) -> AdvisorVoiceResponse:
        audio_bytes = await audio.read()
        try:
            transcript = transcribe_audio(audio_bytes, language=language)
            result = _run_advisor_with_voice(student_id, transcript, language, [])
            audio_response = synthesize_speech(result["response"], language=language)
        except (VoiceConfigurationError, VoiceProcessingError) as error:
            raise HTTPException(status_code=503, detail=str(error)) from error
        return AdvisorVoiceResponse(
            student_id=student_id,
            transcript=transcript,
            response=result["response"],
            intent=result["intent"],
            language=language,
            audio_base64=encode_audio(audio_response),
        )

    @api.post("/advisor/transcribe")
    async def advisor_transcribe(
        language: str = Form(default="english"),
        audio: UploadFile = File(...),
    ) -> dict[str, str]:
        audio_bytes = await audio.read()
        try:
            transcript = transcribe_audio(audio_bytes, language=language)
        except (VoiceConfigurationError, VoiceProcessingError) as error:
            raise HTTPException(status_code=503, detail=str(error)) from error
        return {"language": language, "transcript": transcript}

    @api.post("/advisor/speak")
    def advisor_speak(text: str, language: str = "english") -> dict[str, str]:
        try:
            audio_bytes = synthesize_speech(text, language=language)
        except (VoiceConfigurationError, VoiceProcessingError) as error:
            raise HTTPException(status_code=503, detail=str(error)) from error
        return {
            "language": language,
            "audio_base64": encode_audio(audio_bytes),
        }

    @api.get("/scores/{student_id}")
    def get_scores(student_id: str) -> dict[str, object]:
        result = leaderboard(repository, student_id)
        if result is None:
            raise HTTPException(status_code=404, detail="Student not found")
        return result

    @api.put("/scores/{student_id}/achievements")
    def record_score_achievement(
        student_id: str,
        achievement: ScoreAchievementRequest,
        x_scheduler_token: str | None = Header(default=None, alias="X-Scheduler-Token"),
    ) -> dict[str, object]:
        expected_token = os.environ.get("AEGIS_SCHEDULER_TOKEN")
        if not expected_token or not x_scheduler_token or not hmac.compare_digest(x_scheduler_token, expected_token):
            raise HTTPException(status_code=403, detail="A configured staff token is required")
        if repository.get_student(student_id) is None:
            raise HTTPException(status_code=404, detail="Student not found")
        repository.save_score_achievement(student_id, achievement.achievement_id,
                                          achievement.kind, achievement.title.strip(), achievement.week_number)
        return {"student_id": student_id, **achievement.model_dump()}

    @api.get("/progress/{student_id}", response_model=StudentTwin)
    def get_progress(student_id: str) -> StudentTwin:
        twin = build_student_twin(repository, student_id)
        if twin is None:
            raise HTTPException(status_code=404, detail="Student not found")
        return twin

    @api.post("/progress/analyze/{student_id}")
    def analyze_progress(student_id: str) -> dict[str, object]:
        try:
            result = progress_graph.invoke({"student_id": student_id})
        except StudentNotFoundError as error:
            raise HTTPException(status_code=404, detail="Student not found") from error
        except AdvisorConfigurationError as error:
            raise HTTPException(status_code=503, detail=str(error)) from error
        except Exception as error:
            raise HTTPException(
                status_code=502,
                detail="Progress analysis could not complete.",
            ) from error
        interventions = [
            {"course_id": course.course_id, "course_name": course.course_name, **intervention.model_dump()}
            for course, intervention in result.get("validated_interventions", [])
        ]
        return {"twin": result["twin"].model_dump(), "interventions": interventions}

    @api.get("/progress/{student_id}/weekly")
    def get_weekly_progress(student_id: str) -> dict[str, object]:
        if repository.get_student(student_id) is None:
            raise HTTPException(status_code=404, detail="Student not found")
        return {"student_id": student_id, "snapshots": repository.get_weekly_snapshots(student_id)}

    @api.get("/progress/{student_id}/interventions")
    def get_progress_interventions(student_id: str) -> dict[str, object]:
        if repository.get_student(student_id) is None:
            raise HTTPException(status_code=404, detail="Student not found")
        return {"student_id": student_id, "interventions": repository.get_interventions(student_id)}

    @api.get("/progress/{student_id}/narrative")
    def get_progress_narrative(student_id: str) -> dict[str, str]:
        twin = build_student_twin(repository, student_id)
        if twin is None:
            raise HTTPException(status_code=404, detail="Student not found")
        try:
            narrative = generate_weekly_narrative(twin)
        except Exception as error:
            raise HTTPException(
                status_code=502,
                detail="Narrative generation could not complete.",
            ) from error
        return {"student_id": student_id, "narrative": narrative}

    @api.post("/progress/scheduler/run")
    def run_progress_scheduler(
        x_scheduler_token: str | None = Header(default=None, alias="X-Scheduler-Token"),
    ) -> dict[str, object]:
        expected_token = os.environ.get("AEGIS_SCHEDULER_TOKEN")
        if expected_token and x_scheduler_token != expected_token:
            raise HTTPException(status_code=403, detail="Invalid scheduler token")
        try:
            result = run_analysis_cycle(repository)
        except Exception as error:
            raise HTTPException(
                status_code=502,
                detail="Scheduled analysis could not complete.",
            ) from error
        return {
            "students_analyzed": result.students_analyzed,
            "interventions_created": result.interventions_created,
            "errors": result.errors,
            "summary": result.summary(),
        }

    @api.post("/progress/{student_id}/what-if", response_model=WhatIfResponse)
    def simulate_progress(student_id: str, scenario: WhatIfRequest) -> WhatIfResponse:
        try:
            result = run_assessment_grade_scenario(repository, student_id, scenario)
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error)) from error
        if result is None:
            raise HTTPException(status_code=404, detail="Student not found")
        return result

    return api


app = create_app()
