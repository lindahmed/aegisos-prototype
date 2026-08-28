from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


RiskSeverity = Literal["low", "medium", "high"]
Trend = Literal["improving", "stable", "declining", "new"]


class StudentProfile(BaseModel):
    student_id: str
    name: str
    major: str
    year: int
    gpa: float


class Assessment(BaseModel):
    assessment_id: str
    name: str
    assessment_type: Literal["assignment", "lab", "quiz", "midterm", "final", "exam"]
    weight: float = Field(ge=0, le=100)
    due_week: int = Field(ge=1)
    covered_lecture_ids: list[str] = Field(default_factory=list)
    percentage: float | None = Field(default=None, ge=0, le=100)


class Lecture(BaseModel):
    lecture_id: str
    lecture_number: int
    title: str
    available_week: int
    completed: bool = False


class CourseMaterial(BaseModel):
    material_id: str
    title: str
    material_type: str
    lecture_id: str | None = None
    source_url: str | None = None


class Risk(BaseModel):
    code: str
    severity: RiskSeverity
    message: str
    related_lecture_ids: list[str] = Field(default_factory=list)
    related_assessment_ids: list[str] = Field(default_factory=list)


class CourseMetrics(BaseModel):
    assignment_average: float | None = None
    lab_average: float | None = None
    quiz_average: float | None = None
    exam_percentage: float | None = None
    weighted_grade: float | None = None
    lecture_completion: float = Field(ge=0, le=100)
    assessment_completion: float = Field(ge=0, le=100)
    course_health: float = Field(ge=0, le=100)
    trend: Trend
    previous_course_health: float | None = Field(default=None, ge=0, le=100)


class CourseTwin(BaseModel):
    course_id: str
    course_name: str
    semester: str
    current_week: int
    assessments: list[Assessment]
    lectures: list[Lecture]
    materials: list[CourseMaterial]
    completed_lectures: list[Lecture]
    unstudied_lectures: list[Lecture]
    metrics: CourseMetrics
    risks: list[Risk] = Field(default_factory=list)
    risk_level: RiskSeverity | None = None


class StudentTwin(BaseModel):
    student: StudentProfile
    semester: str
    current_week: int
    courses: list[CourseTwin]
    overall_academic_health: float = Field(ge=0, le=100)
    active_risks: list[Risk] = Field(default_factory=list)
    weekly_history: list[dict[str, object]] = Field(default_factory=list)
    recent_interventions: list[dict[str, object]] = Field(default_factory=list)


class Intervention(BaseModel):
    severity: RiskSeverity
    reason: str
    weak_topics: list[str] = Field(default_factory=list)
    lectures_to_review: list[int] = Field(default_factory=list)
    recommended_actions: list[str] = Field(default_factory=list, max_length=5)
    message: str = Field(min_length=1, max_length=1600)


class WhatIfRequest(BaseModel):
    type: Literal["assessment_grade"]
    course_id: str = Field(min_length=1, max_length=100)
    assessment_id: str = Field(min_length=1, max_length=100)
    hypothetical_grade: float = Field(ge=0, le=100)


class WhatIfResponse(BaseModel):
    before: dict[str, object]
    after: dict[str, object]
    difference: dict[str, float | None]
    explanation: str

