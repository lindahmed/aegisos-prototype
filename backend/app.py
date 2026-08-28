from __future__ import annotations

import os
from pathlib import Path
from typing import Callable

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from backend.advisor.graph import advisor_graph
from backend.advisor.llm import AdvisorConfigurationError
from backend.advisor.models import AdvisorRequest, AdvisorResponse
from backend.progress.models import StudentTwin, WhatIfRequest, WhatIfResponse
from backend.progress.service import build_student_twin
from backend.progress_agent.graph import (
    StudentNotFoundError,
    build_progress_graph,
)
from backend.simulation.what_if import run_assessment_grade_scenario
from database.repository import Student, StudentRepository
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
    database_path = db_path or Path(
        os.environ.get("AEGIS_DB_PATH", PROJECT_ROOT / "database" / "aegisos.db")
    )
    student_workspace_root = workspace_root or Path(
        os.environ.get(
            "AEGIS_WORKSPACE_ROOT", PROJECT_ROOT / "workspace" / "students"
        )
    )
    repository = StudentRepository(database_path)
    repository.initialize()
    progress_graph = build_progress_graph(repository)
    manager = WorkspaceManager(student_workspace_root, launcher=launcher)

    api = FastAPI(title="AegisOS EDU API", version="1.1.0")
    api.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["GET", "POST"],
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

        try:
            result = advisor_graph.invoke(
                {
                    "message": request.message,
                    "history": history,
                    "student": student.as_dict(),
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
        )

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
