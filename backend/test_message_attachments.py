from pathlib import Path
import sqlite3

import pytest
from fastapi.testclient import TestClient

from backend.app import create_app
from database.repository import StudentRepository


def client_for(tmp_path: Path) -> TestClient:
    return TestClient(create_app(
        db_path=tmp_path / "messages.db",
        workspace_root=tmp_path / "students",
        material_storage_root=tmp_path / "materials",
    ))


def send_document(client, filename="notes.txt", content=b"Lecture notes", body=""):
    return client.post("/messages/attachments", data={
        "sender_type": "student", "sender_id": "231027905",
        "recipient_type": "student", "recipient_id": "231027906", "body": body,
    }, files={"file": (filename, content, "application/octet-stream")})


@pytest.mark.parametrize("body", ["", "Here are my notes"])
def test_document_survives_restart_and_downloads_for_both_participants(tmp_path, body):
    client = client_for(tmp_path)
    response = send_document(client, body=body)
    assert response.status_code == 200
    message = response.json()["message"]
    assert message["body"] == body
    assert message["attachment"] == {"filename": "notes.txt", "size_bytes": 13}
    client = client_for(tmp_path)
    for student_id in ("231027905", "231027906"):
        params = {"actor_type": "student", "actor_id": student_id}
        inbox = client.get("/messages", params=params).json()["messages"]
        assert inbox[0]["attachment"] == message["attachment"]
        assert inbox[0]["read"] is (student_id == "231027905")
        download = client.get(f'/messages/{message["message_id"]}/attachment', params=params)
        assert download.status_code == 200
        assert download.content == b"Lecture notes"
        assert "attachment; filename*=UTF-8''notes.txt" == download.headers["content-disposition"]
        assert download.headers["x-content-type-options"] == "nosniff"
    unrelated = client.get(f'/messages/{message["message_id"]}/attachment', params={
        "actor_type": "student", "actor_id": "231027907",
    })
    assert unrelated.status_code == 404


@pytest.mark.parametrize("filename,content,status", [
    ("notes.exe", b"data", 400),
    ("empty.pdf", b"", 400),
    ("large.pdf", b"x" * (10 * 1024 * 1024 + 1), 413),
], ids=["unsupported-type", "empty-document", "over-size-limit"])
def test_invalid_documents_create_no_message_or_file(tmp_path, filename, content, status):
    client = client_for(tmp_path)
    assert send_document(client, filename, content).status_code == status
    assert client.get("/messages", params={
        "actor_type": "student", "actor_id": "231027906",
    }).json()["messages"] == []
    assert not list((tmp_path / "materials").rglob("*"))


@pytest.mark.parametrize("filename", ["notes.PDF", "notes.docx", "notes.xlsx", "notes.pptx", "notes.csv", "notes.odt"])
def test_common_document_formats_are_accepted(tmp_path, filename):
    assert send_document(client_for(tmp_path), filename).status_code == 200


def test_filename_is_not_used_as_storage_path(tmp_path):
    client = client_for(tmp_path)
    message = send_document(client, "../../notes.txt").json()["message"]
    assert message["attachment"]["filename"] == "notes.txt"
    repository = StudentRepository(tmp_path / "messages.db")
    assert repository.get_portal_message_attachment(message["message_id"]) == b"Lecture notes"
    assert not (tmp_path / "notes.txt").exists()


def test_document_is_shared_between_backends_without_shared_filesystem(tmp_path):
    sent = send_document(client_for(tmp_path)).json()["message"]
    other_computer = TestClient(create_app(
        db_path=tmp_path / "messages.db",
        workspace_root=tmp_path / "other-computer" / "students",
        material_storage_root=tmp_path / "other-computer" / "materials",
    ))
    params = {"actor_type": "student", "actor_id": "231027906"}
    inbox = other_computer.get("/messages", params=params).json()["messages"]
    assert inbox[0]["message_id"] == sent["message_id"]
    assert "attachment_content" not in inbox[0]
    download = other_computer.get(f'/messages/{sent["message_id"]}/attachment', params=params)
    assert download.status_code == 200
    assert download.content == b"Lecture notes"


def test_missing_recipient_and_oversized_caption_are_rejected(tmp_path):
    client = client_for(tmp_path)
    response = client.post("/messages/attachments", data={
        "sender_type": "student", "sender_id": "231027905",
        "recipient_type": "student", "recipient_id": "unknown",
    }, files={"file": ("notes.txt", b"Notes")})
    assert response.status_code == 404
    assert send_document(client, body="x" * 4001).status_code == 422
    assert not list((tmp_path / "materials").rglob("*"))


def test_text_only_messages_still_require_content(tmp_path):
    client = client_for(tmp_path)
    fields = {"sender_type": "student", "sender_id": "231027905",
              "recipient_type": "student", "recipient_id": "231027906"}
    assert client.post("/messages", json={**fields, "body": " "}).status_code == 400
    assert client.post("/messages", json={**fields, "body": "Hello"}).status_code == 200


def test_existing_sqlite_messages_are_preserved_by_migration(tmp_path):
    repository = StudentRepository(tmp_path / "legacy.db")
    repository.initialize()
    repository.create_portal_message({
        "message_id": "legacy", "sender_type": "student", "sender_id": "231027905",
        "recipient_type": "student", "recipient_id": "231027906", "body": "Old message",
        "created_at": "2026-10-03T00:00:00+00:00",
    })
    with sqlite3.connect(repository.database_path) as connection:
        connection.execute("ALTER TABLE portal_messages DROP COLUMN attachment")
        connection.execute("ALTER TABLE portal_messages DROP COLUMN attachment_content")
    repository.initialize()
    repository.initialize()
    message = repository.list_portal_messages("student", "231027906")[0]
    assert message["body"] == "Old message"
    assert message["attachment"] is None
