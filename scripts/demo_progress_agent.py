#!/usr/bin/env python3
"""Demonstrate the Progress Agent against the configured database.

Run without arguments to print current state. Pass --run to create snapshots
and interventions (safe — only writes progress-agent history tables).
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(override=False)

import sys

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from backend.progress.scheduler import run_analysis_cycle
from backend.progress.narrative import generate_weekly_narrative
from backend.progress.service import build_student_twin
from backend.progress_agent.graph import build_progress_graph
from database.postgres_repository import PostgresStudentRepository
from database.repository import StudentRepository


def get_repository():
    database_url = os.environ.get("DATABASE_URL")
    if database_url:
        print("Using PostgreSQL database (DATABASE_URL)")
        return PostgresStudentRepository(database_url)
    database_path = Path(os.environ.get("AEGIS_DB_PATH", PROJECT_ROOT / "database" / "aegisos.db"))
    print(f"Using SQLite database: {database_path}")
    return StudentRepository(database_path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Demonstrate the AegisOS Progress Agent")
    parser.add_argument("--run", action="store_true", help="Run the scheduler and create interventions")
    parser.add_argument("--student", default=None, help="Analyze a single student ID")
    args = parser.parse_args()

    repository = get_repository()
    repository.initialize()

    students = repository.get_registered_students()
    if not students:
        print("No students found in the database.")
        return

    if args.student:
        students = [s for s in students if s.student_id == args.student]
        if not students:
            print(f"Student {args.student} not found.")
            return

    print(f"\nFound {len(students)} student(s): {', '.join(s.student_id for s in students)}\n")

    if args.run:
        print("=" * 60)
        print("RUNNING SCHEDULER (proactive, deadline-clustering, pattern detection)")
        print("=" * 60)
        result = run_analysis_cycle(repository)
        print(f"Students analyzed: {result.students_analyzed}")
        print(f"Interventions created: {result.interventions_created}")
        print(f"Errors: {result.errors}")
        print(f"Summary: {result.summary()}")
        print()

    for student in students:
        print("=" * 60)
        print(f"STUDENT: {student.student_id} — {student.name}")
        print("=" * 60)

        twin = build_student_twin(repository, student.student_id)
        if twin is None:
            print("No Digital Twin available.\n")
            continue

        print(f"Semester: {twin.semester} | Current week: {twin.current_week}")
        print(f"Overall academic health: {twin.overall_academic_health or 'N/A'}")
        print(f"Active risks: {len(twin.active_risks)}")
        for risk in twin.active_risks:
            print(f"  - [{risk.severity.upper()}] {risk.code}: {risk.message}")

        print("\nCourses:")
        for course in twin.courses:
            health = course.metrics.course_health
            print(
                f"  {course.course_id}: health={health if health is not None else 'N/A'} "
                f"trend={course.metrics.trend} risks={len(course.risks)}"
            )

        print("\nInterventions:")
        interventions = repository.get_interventions(student.student_id)
        if interventions:
            for inv in interventions:
                print(
                    f"  [{inv['status'].upper()}] Week {inv['week_number']} {inv['course_id']}: "
                    f"{inv['message'][:120]}..."
                )
        else:
            print("  None")

        print("\nWeekly dashboard narrative:")
        try:
            narrative = generate_weekly_narrative(twin)
            print(f"  {narrative}")
        except Exception as e:
            print(f"  Could not generate narrative: {e}")

        print("\nSnapshots:")
        snapshots = repository.get_weekly_snapshots(student.student_id)
        for snap in snapshots[-3:]:
            print(
                f"  Week {snap['week_number']} {snap['course_id']}: "
                f"health={snap['course_health']} risk={snap['risk_level']} trend={snap['trend']}"
            )

        print()


if __name__ == "__main__":
    main()
