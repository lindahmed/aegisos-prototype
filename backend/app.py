from __future__ import annotations

import os
from pathlib import Path
from typing import Callable

from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile

load_dotenv(override=False)
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
from backend.progress.models import StudentTwin, WhatIfRequest, WhatIfResponse
from backend.progress.narrative import generate_weekly_narrative
from backend.progress.scheduler import run_analysis_cycle
from backend.progress.service import build_student_twin
from backend.progress_agent.graph import (
    StudentNotFoundError,
    build_progress_graph,
)
from backend.simulation.what_if import run_assessment_grade_scenario
from database.repository import Student, StudentRepository
from database.postgres_repository import PostgresStudentRepository
from workspace.manager import ToolUnavailableError, WorkspaceManager


PROJECT_ROOT = Path(__file__).resolve().parents[1]


class WorkspaceRequest(BaseModel):
    student_id: str = Field(min_length=1, max_length=64)
    course: str = Field(min_length=1, max_length=160)


class WorkspaceResponse(BaseModel):
    student_id: str
    course: str
    path: str
    opened: bool = False


class PortalGradebookRowRequest(BaseModel):
    student_id: str = Field(min_length=1, max_length=64)
    assignment_score: float = Field(ge=0, le=100)
    midterm_score: float = Field(ge=0, le=100)
    final_score: float = Field(ge=0, le=100)


class PortalGradebookUpdateRequest(BaseModel):
    semester: str = Field(min_length=1, max_length=64)
    rows: list[PortalGradebookRowRequest] = Field(min_length=1)


GRADE_SCALE = [
    ("A", 4.0, 93),
    ("A-", 3.7, 90),
    ("B+", 3.3, 87),
    ("B", 3.0, 83),
    ("B-", 2.7, 80),
    ("C+", 2.3, 77),
    ("C", 2.0, 73),
    ("D", 1.0, 60),
    ("F", 0.0, 0),
]


def _weighted_total(record: dict[str, object]) -> float:
    assignment = float(record.get("assignment_score", 0) or 0)
    midterm = float(record.get("midterm_score", 0) or 0)
    final = float(record.get("final_score", 0) or 0)
    return round((assignment * 0.3) + (midterm * 0.3) + (final * 0.4), 2)


def _score_to_grade(total: float) -> tuple[str, float]:
    for letter, gpa_points, minimum in GRADE_SCALE:
        if total >= minimum:
            return letter, gpa_points
    return "F", 0.0


def _enrich_grade_record(record: dict[str, object]) -> dict[str, object]:
    assignment_score = round(float(record.get("assignment_score", 0) or 0), 2)
    midterm_score = round(float(record.get("midterm_score", 0) or 0), 2)
    final_score = round(float(record.get("final_score", 0) or 0), 2)
    total_score = _weighted_total(
        {
            "assignment_score": assignment_score,
            "midterm_score": midterm_score,
            "final_score": final_score,
        }
    )
    letter_grade, gpa_points = _score_to_grade(total_score)
    return {
        **record,
        "assignment_score": assignment_score,
        "midterm_score": midterm_score,
        "final_score": final_score,
        "total_score": total_score,
        "letter_grade": letter_grade,
        "gpa_points": gpa_points,
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
        gpa = round(
            sum(float(record["gpa_points"]) for record in semester_records)
            / len(semester_records),
            2,
        )
        standing = (
            "In Progress"
            if any(float(record["final_score"]) == 0 for record in semester_records)
            else _standing_for_gpa(gpa)
        )
        summaries.append(
            {
                "semester": semester,
                "gpa": gpa,
                "courses_graded": len(semester_records),
                "standing": standing,
            }
        )
    return sorted(summaries, key=lambda summary: str(summary["semester"]), reverse=True)


def _enrolled_course(student: Student, requested_course: str) -> str:
    normalized = requested_course.strip().casefold()
    for course in student.courses:
        if course.casefold() == normalized:
            return course
    raise HTTPException(status_code=400, detail="Course is not enrolled for this student")


def create_app(
    *,
    db_path: Path | None = None,
    workspace_root: Path | None = None,
    launcher: Callable[[Path], None] | None = None,
) -> FastAPI:
    student_workspace_root = workspace_root or Path(
        os.environ.get(
            "AEGIS_WORKSPACE_ROOT", PROJECT_ROOT / "workspace" / "students"
        )
    )
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
        allow_methods=["GET", "POST", "PUT"],
        allow_headers=["Content-Type"],
    )

    @api.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @api.get("/student/{student_id}")
    def get_student(student_id: str) -> dict[str, object]:
        student = repository.get_student(student_id)
        if student is None:
            raise HTTPException(status_code=404, detail="Student not found")
        return student.as_dict()

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
            "semesters": _semester_summaries(records),
            "records": records,
        }

    @api.get("/portal/students/{student_id}/academics")
    def get_portal_student_academics(student_id: str) -> dict[str, object]:
        student = repository.get_student(student_id)
        if student is None:
            raise HTTPException(status_code=404, detail="Student not found")
        twin = build_student_twin(repository, student_id)
        report = repository.get_student_portal_grade_report(student_id)
        records = [_enrich_grade_record(record) for record in report["records"]] if report else []
        return {
            "student": student.as_dict(),
            "semester": twin.semester if twin else "",
            "current_week": twin.current_week if twin else 1,
            "courses": [course.model_dump() for course in (twin.courses if twin else [])],
            "grades": {
                "semesters": _semester_summaries(records),
                "records": records,
            },
        }

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
