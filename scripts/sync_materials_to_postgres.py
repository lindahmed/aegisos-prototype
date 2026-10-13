from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path

from dotenv import load_dotenv


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))
load_dotenv(PROJECT_ROOT / ".env", override=False)

from database.postgres_repository import PostgresStudentRepository


def _rows(connection: sqlite3.Connection, query: str, parameters=()):
    return [dict(row) for row in connection.execute(query, parameters)]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Publish locally ingested material metadata and chunks to PostgreSQL."
    )
    parser.add_argument(
        "--database", type=Path, default=PROJECT_ROOT / "database" / "aegisos.db"
    )
    args = parser.parse_args()
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        parser.error("DATABASE_URL is not configured")

    target = PostgresStudentRepository(database_url)
    target.initialize()
    source = sqlite3.connect(args.database)
    source.row_factory = sqlite3.Row
    try:
        documents = _rows(source, "SELECT * FROM material_documents ORDER BY document_id")
        print(f"Publishing {len(documents)} material documents", flush=True)
        for index, document in enumerate(documents, start=1):
            target.upsert_material_document(document)
            chunks = _rows(
                source,
                "SELECT * FROM material_chunks WHERE document_id = ? ORDER BY chunk_index",
                (document["document_id"],),
            )
            for chunk in chunks:
                chunk["embedding"] = json.loads(chunk.pop("embedding_json"))
            target.replace_material_chunks(document["document_id"], chunks)
            summary = source.execute(
                "SELECT * FROM material_summaries WHERE document_id = ?",
                (document["document_id"],),
            ).fetchone()
            if summary:
                summary_data = dict(summary)
                summary_data["learning_objectives"] = json.loads(
                    summary_data.pop("learning_objectives_json")
                )
                summary_data["keywords"] = json.loads(
                    summary_data.pop("keywords_json")
                )
                target.upsert_material_summary(document["document_id"], summary_data)
            if index % 10 == 0:
                print(f"Published {index}/{len(documents)} documents", flush=True)

        jobs = _rows(source, "SELECT report_json FROM material_ingestion_jobs")
        for job in jobs:
            target.save_material_ingestion_job(json.loads(job["report_json"]))
    finally:
        source.close()
        target.close()

    print("PostgreSQL material library is synchronized", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
