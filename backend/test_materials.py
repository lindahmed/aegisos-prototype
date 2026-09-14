from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

from fastapi.testclient import TestClient

from backend.advisor.context import fetch_student_context
from backend.app import create_app
from backend.materials.retrieval import embed_text
from database.repository import StudentRepository


def _add_operating_system_material(
    repository: StudentRepository, storage_root: Path
) -> str:
    document_id = "os-deadlocks-week6"
    now = datetime.now(UTC).isoformat()
    relative_path = Path(
        "cs", "semester-5", "CCS3203", "lecture", "deadlocks-week-6.pdf"
    )
    source = storage_root / relative_path
    source.parent.mkdir(parents=True, exist_ok=True)
    source.write_bytes(b"sample course material")
    repository.upsert_material_document(
        {
            "document_id": document_id,
            "course_id": "CCS3203",
            "course_name": "Operating Systems",
            "major_code": "CS",
            "program_semester": 5,
            "title": "Deadlocks Week 6",
            "category": "lecture",
            "week_number": 6,
            "original_filename": "deadlocks-week-6.pdf",
            "source_archive_path": "Semester 5/Operating System/deadlocks-week-6.pdf",
            "storage_provider": "local",
            "storage_path": relative_path.as_posix(),
            "mime_type": "application/pdf",
            "checksum": "test-checksum-deadlocks",
            "size_bytes": source.stat().st_size,
            "page_count": 1,
            "visibility": "student",
            "status": "ready",
            "created_at": now,
            "updated_at": now,
        }
    )
    content = (
        "A deadlock can occur when mutual exclusion, hold and wait, no "
        "preemption, and circular wait are all present."
    )
    repository.replace_material_chunks(
        document_id,
        [
            {
                "chunk_id": "os-deadlocks-chunk-1",
                "chunk_index": 0,
                "content": content,
                "page_start": 4,
                "page_end": 4,
                "token_count": 24,
                "embedding": embed_text(content),
            }
        ],
    )
    repository.upsert_material_summary(
        document_id,
        {
            "summary": "The four necessary conditions for deadlock.",
            "learning_objectives": ["Recognize deadlock conditions"],
            "keywords": ["deadlock", "mutual exclusion"],
            "generator": "test",
        },
    )
    return document_id


def test_material_search_is_scoped_to_cs_semester_five(tmp_path: Path) -> None:
    repository = StudentRepository(tmp_path / "aegisos.db")
    repository.initialize()
    _add_operating_system_material(repository, tmp_path / "materials")

    results = repository.search_student_materials(
        "231027905", "What are the four deadlock conditions?"
    )
    assert results
    assert results[0]["course_id"] == "CCS3203"
    assert results[0]["page_start"] == 4

    assert repository.list_student_materials("231027906") == []


def test_advisor_context_contains_citable_material(tmp_path: Path) -> None:
    repository = StudentRepository(tmp_path / "aegisos.db")
    repository.initialize()
    _add_operating_system_material(repository, tmp_path / "materials")

    context = fetch_student_context(
        repository,
        "231027905",
        message="Explain mutual exclusion in deadlocks",
    )
    assert context["material_sources"]
    assert context["material_sources"][0]["page_start"] == 4


def test_material_api_lists_searches_and_downloads(tmp_path: Path) -> None:
    database_path = tmp_path / "aegisos.db"
    storage_root = tmp_path / "materials"
    repository = StudentRepository(database_path)
    repository.initialize()
    document_id = _add_operating_system_material(repository, storage_root)
    client = TestClient(
        create_app(
            db_path=database_path,
            workspace_root=tmp_path / "students",
            material_storage_root=storage_root,
        )
    )

    listing = client.get("/portal/students/231027905/materials")
    assert listing.status_code == 200
    document = listing.json()["documents"][0]
    assert document["document_id"] == document_id
    assert "storage_path" not in document
    assert document["keywords"] == ["deadlock", "mutual exclusion"]

    search = client.get(
        "/portal/students/231027905/materials/search",
        params={"q": "circular wait deadlock"},
    )
    assert search.status_code == 200
    assert search.json()["results"][0]["document_id"] == document_id

    download = client.get(
        f"/portal/students/231027905/materials/{document_id}"
    )
    assert download.status_code == 200
    assert download.content == b"sample course material"

    denied = client.get("/portal/students/231027906/materials")
    assert denied.status_code == 200
    assert denied.json()["documents"] == []
