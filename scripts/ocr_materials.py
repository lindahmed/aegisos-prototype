from __future__ import annotations

import argparse
import sqlite3
import sys
from datetime import UTC, datetime
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from backend.materials.ingestion import (
    COURSE_FOLDERS,
    build_chunks,
    summarize_chunks,
)
from backend.materials.ocr import extract_scanned_pdf
from database.repository import StudentRepository


def main() -> int:
    parser = argparse.ArgumentParser(
        description="OCR scanned material PDFs while preserving page citations."
    )
    parser.add_argument(
        "--database", type=Path, default=PROJECT_ROOT / "database" / "aegisos.db"
    )
    parser.add_argument(
        "--storage-root", type=Path, default=PROJECT_ROOT / "workspace" / "materials"
    )
    parser.add_argument("--document-id")
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()

    repository = StudentRepository(args.database)
    repository.initialize()
    connection = sqlite3.connect(args.database)
    connection.row_factory = sqlite3.Row
    query = "SELECT * FROM material_documents WHERE status = 'needs_ocr'"
    parameters: tuple[object, ...] = ()
    if args.document_id:
        query += " AND document_id = ?"
        parameters = (args.document_id,)
    query += " ORDER BY course_id, original_filename"
    documents = [dict(row) for row in connection.execute(query, parameters)]
    connection.close()
    if args.limit is not None:
        documents = documents[: max(0, args.limit)]

    course_map = {course.course_id: course for course in COURSE_FOLDERS}
    failures = 0
    print(f"OCR queue contains {len(documents)} scanned PDFs", flush=True)
    for index, document in enumerate(documents, start=1):
        source = (args.storage_root / document["storage_path"]).resolve()
        try:
            print(
                f"[{index}/{len(documents)}] {document['course_id']} — "
                f"{document['original_filename']}",
                flush=True,
            )
            sections = extract_scanned_pdf(source)
            chunks = build_chunks(
                document["document_id"],
                course_map[document["course_id"]],
                document["title"],
                document["category"],
                sections,
            )
            if not chunks:
                raise RuntimeError("OCR output did not produce searchable sections")
            repository.replace_material_chunks(document["document_id"], chunks)
            summary = summarize_chunks(chunks)
            summary["generator"] = "gemini-page-ocr-plus-extractive-summary-v1"
            repository.upsert_material_summary(document["document_id"], summary)
            document["status"] = "ready_ocr"
            document["updated_at"] = datetime.now(UTC).isoformat()
            repository.upsert_material_document(document)
            print(f"  Added {len(chunks)} searchable page sections", flush=True)
        except Exception as error:
            failures += 1
            print(f"  FAILED: {type(error).__name__}: {error}", flush=True)

    print(
        f"OCR complete: {len(documents) - failures} succeeded, {failures} failed",
        flush=True,
    )
    return 0 if failures == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
