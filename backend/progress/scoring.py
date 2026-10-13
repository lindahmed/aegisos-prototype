"""Deterministic student points from recorded academic work.

The Progress Agent can run repeatedly; recomputing from unique source records
prevents a second analysis cycle from granting the same points again.
"""

from __future__ import annotations

from typing import Any

from database.postgres_repository import PostgresStudentRepository
from database.repository import StudentRepository

Repository = StudentRepository | PostgresStudentRepository

POINTS = {"lecture": 10, "good_exam": 25, "project": 40, "award": 50}
GOOD_EXAM_PERCENTAGE = 70
EXAM_TYPES = {"quiz", "midterm", "final", "exam"}


def student_score(repository: Repository, student_id: str) -> dict[str, Any] | None:
    progress = repository.get_student_progress(student_id)
    if progress is None:
        return None
    current_week = int(progress["current_week"])
    weeks: dict[int, dict[str, int]] = {}

    def add(week: int, kind: str) -> None:
        if not 1 <= week <= current_week:
            return
        row = weeks.setdefault(week, {"week": week, "lectures": 0, "exams_taken": 0,
                                      "good_exams": 0, "projects": 0, "awards": 0,
                                      "points": 0})
        row[kind] += 1
        point_kind = {"lectures": "lecture", "good_exams": "good_exam",
                      "projects": "project", "awards": "award"}.get(kind)
        if point_kind:
            row["points"] += POINTS[point_kind]

    for course in progress["courses"]:
        for lecture in course["lectures"]:
            if lecture["completed"]:
                add(int(lecture.get("completed_week") or lecture["available_week"]), "lectures")
        for assessment in course["assessments"]:
            if assessment["assessment_type"] not in EXAM_TYPES or assessment["percentage"] is None:
                continue
            week = int(assessment["due_week"])
            add(week, "exams_taken")
            if float(assessment["percentage"]) >= GOOD_EXAM_PERCENTAGE:
                add(week, "good_exams")
    if isinstance(repository, PostgresStudentRepository):
        for lecture in repository.get_score_lectures(student_id):
            add(int(lecture["completed_week"]), "lectures")
    for achievement in repository.get_score_achievements(student_id):
        add(int(achievement["week_number"]), "projects" if achievement["kind"] == "project" else "awards")

    history = [weeks[week] for week in sorted(weeks)]
    totals = {key: sum(row[key] for row in history)
              for key in ("lectures", "exams_taken", "good_exams", "projects", "awards", "points")}
    return {"student_id": student_id, "name": progress["student"]["name"],
            "current_week": current_week, "score": totals["points"],
            "totals": totals, "weekly": history}


def leaderboard(repository: Repository, student_id: str) -> dict[str, Any] | None:
    if isinstance(repository, PostgresStudentRepository):
        scores = [
            {"student_id": row["student_id"], "name": row["name"],
             "score": sum(row[kind] * POINTS[point_kind] for kind, point_kind in (
                 ("lectures", "lecture"), ("good_exams", "good_exam"),
                 ("projects", "project"), ("awards", "award")))}
            for row in repository.get_scoreboard_activity()
        ]
    else:
        if repository.get_student(student_id) is None:
            return None
        scores = [score for student in repository.get_registered_students()
                  if (score := student_score(repository, student.student_id)) is not None]
    scores.sort(key=lambda row: (-row["score"], row["name"].casefold(), row["student_id"]))
    for index, row in enumerate(scores):
        row["rank"] = (scores[index - 1]["rank"] if index and row["score"] == scores[index - 1]["score"]
                       else index + 1)
    own_index = next((index for index, row in enumerate(scores) if row["student_id"] == student_id), None)
    if own_index is None:
        return None
    if isinstance(repository, PostgresStudentRepository):
        detail = student_score(repository, student_id)
        if detail is not None:
            scores[own_index].update({key: detail[key] for key in ("totals", "weekly", "current_week")})

    def public_row(row: dict[str, Any]) -> dict[str, Any]:
        return {key: row[key] for key in ("student_id", "name", "score", "rank")}

    own_score = scores[own_index]["score"]
    nearby = [row for index, row in enumerate(scores)
              if abs(index - own_index) <= 2 or row["score"] == own_score]
    return {"me": scores[own_index], "top_five": [public_row(row) for row in scores[:5]],
            "nearby": [public_row(row) for row in nearby], "rules": POINTS,
            "good_exam_percentage": GOOD_EXAM_PERCENTAGE}
