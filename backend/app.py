from __future__ import annotations

import os
from pathlib import Path
from typing import Callable

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

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
    manager = WorkspaceManager(student_workspace_root, launcher=launcher)

    api = FastAPI(title="AegisOS EDU API", version="1.0.0")
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

    return api


app = create_app()
