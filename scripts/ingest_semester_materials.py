from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from backend.materials.ingestion import ingest_semester_archive
from database.repository import StudentRepository


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Import the approved CS Semester 5 course-material archive."
    )
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument(
        "--database", type=Path, default=PROJECT_ROOT / "database" / "aegisos.db"
    )
    parser.add_argument(
        "--storage-root", type=Path, default=PROJECT_ROOT / "workspace" / "materials"
    )
    args = parser.parse_args()

    if not args.archive.is_file():
        parser.error(f"Archive not found: {args.archive}")

    repository = StudentRepository(args.database)
    repository.initialize()
    print(f"Starting approved Semester 5 import from {args.archive}", flush=True)
    report = ingest_semester_archive(
        args.archive,
        args.storage_root,
        repository,
        progress=lambda message: print(message, flush=True),
    )
    print(json.dumps(report, indent=2, ensure_ascii=False), flush=True)
    return 0 if report["status"] == "completed" else 2


if __name__ == "__main__":
    raise SystemExit(main())
