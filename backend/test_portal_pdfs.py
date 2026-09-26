from __future__ import annotations

from io import BytesIO
from pathlib import Path
import sqlite3

import httpx
import pytest
from fastapi.testclient import TestClient
from pypdf import PdfWriter

from backend.app import create_app
from database.repository import StudentRepository


def pdf_bytes() -> bytes:
    output = BytesIO()
    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    writer.write(output)
    return output.getvalue()


@pytest.fixture
def portal(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "test-anon-key")
    monkeypatch.setenv("AEGIS_STAFF_IDS", "104217,other-staff")

    def auth_user(url: str, *, headers: dict[str, str], timeout: int):
        assert url == "https://example.supabase.co/auth/v1/user"
        assert headers["apikey"] == "test-anon-key"
        token = headers["Authorization"].removeprefix("Bearer ")
        emails = {
            "staff": "104217@staff.aegisos.local",
            "other-staff": "other-staff@staff.aegisos.local",
            "student": "231027905@students.aegisos.local",
            "other-student": "231027906@students.aegisos.local",
            "forged-staff": "104217@staff.aegisos.local",
        }
        if token not in emails:
            return httpx.Response(401)
        role = "staff" if token in {"staff", "other-staff"} else "student"
        return httpx.Response(200, json={
            "id": token,
            "email": emails[token],
            "app_metadata": {"portal_role": role, "portal_id": emails[token].split("@")[0]},
        })

    monkeypatch.setattr("backend.app.httpx.get", auth_user)
    db_path = tmp_path / "portal.db"
    repository = StudentRepository(db_path)
    repository.initialize()
    with repository._connect() as connection:
        connection.execute(
            "INSERT INTO portal_instructor_courses (instructor_id, course_id) VALUES (?, ?)",
            ("104217", "ai"),
        )
    root = tmp_path / "materials"
    client = TestClient(create_app(db_path=db_path, material_storage_root=root))
    return client, root


def headers(actor: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {actor}"}


def upload(client: TestClient, *, actor: str = "staff", course: str = "ai"):
    return client.post(
        "/portal/pdfs/staff",
        headers=headers(actor),
        data={"title": "Lecture notes", "description": "Week one", "course_id": course},
        files={"file": ("notes.pdf", pdf_bytes(), "application/pdf")},
    )


def test_upload_student_visibility_view_download_and_delete(portal):
    client, root = portal
    response = upload(client)
    assert response.status_code == 201, response.text
    pdf = response.json()["pdf"]
    pdf_id = pdf["pdf_id"]
    assert pdf["instructor_id"] == "104217"
    assert pdf["course_id"] == "ai"
    assert "storage_path" not in pdf
    assert (root / "portal-pdfs" / f"{pdf_id}.pdf").read_bytes() == pdf_bytes()

    assert len(client.get("/portal/pdfs/staff", headers=headers("staff")).json()["pdfs"]) == 1
    visible = client.get("/portal/pdfs/student", headers=headers("student"))
    assert visible.status_code == 200
    assert visible.json()["pdfs"][0]["pdf_id"] == pdf_id
    assert visible.json()["pdfs"][0]["course_name"]
    assert client.get("/portal/pdfs/student", headers=headers("other-student")).json()["pdfs"] == []

    path = f"/portal/pdfs/student/{pdf_id}/file"
    viewed = client.get(path, headers=headers("student"))
    assert viewed.status_code == 200 and viewed.content == pdf_bytes()
    assert viewed.headers["content-type"] == "application/pdf"
    downloaded = client.get(path + "?download=true", headers=headers("student"))
    assert downloaded.status_code == 200
    assert "attachment" in downloaded.headers["content-disposition"]
    assert client.get(path, headers=headers("other-student")).status_code == 404
    assert client.get(path).status_code == 401
    assert client.get(path, headers=headers("staff")).status_code == 403
    assert client.get(f"/portal/pdfs/staff/{pdf_id}/file", headers=headers("other-staff")).status_code == 404
    assert client.delete(f"/portal/pdfs/staff/{pdf_id}", headers=headers("other-staff")).status_code == 404

    with sqlite3.connect(root.parent / "portal.db") as connection:
        connection.execute(
            "UPDATE courses SET status = 'Withdrawn' WHERE student_id = ? AND course_name = ?",
            ("231027905", "Artificial Intelligence"),
        )
    assert client.get("/portal/pdfs/student", headers=headers("student")).json()["pdfs"] == []
    assert client.get(path, headers=headers("student")).status_code == 404

    assert client.delete(f"/portal/pdfs/staff/{pdf_id}", headers=headers("staff")).status_code == 204
    assert not (root / "portal-pdfs" / f"{pdf_id}.pdf").exists()
    assert client.get(path, headers=headers("student")).status_code == 404


def test_rejects_unassigned_course_invalid_and_oversize_files(portal):
    client, _ = portal
    assert upload(client, course="os").status_code == 403
    assert upload(client, actor="student").status_code == 403
    assert upload(client, actor="other-staff").status_code == 403
    assert client.post(
        "/portal/pdfs/staff", headers=headers("staff"),
        data={"title": "Bad"}, files={"file": ("bad.pdf", b"not a PDF", "application/pdf")},
    ).status_code == 422
    assert client.post(
        "/portal/pdfs/staff", headers=headers("staff"),
        data={"title": "Bad"}, files={"file": ("bad.txt", pdf_bytes(), "text/plain")},
    ).status_code == 422
    assert client.post(
        "/portal/pdfs/staff", headers=headers("staff"),
        data={"title": "Too large"},
        files={"file": ("large.pdf", pdf_bytes() + b"x" * (10 * 1024 * 1024), "application/pdf")},
    ).status_code == 413
    assert client.get("/portal/pdfs/staff", headers=headers("invalid")).status_code == 401
    assert client.get("/portal/pdfs/staff", headers=headers("forged-staff")).status_code == 403


def test_general_pdf_visible_to_all_students(portal):
    client, _ = portal
    response = upload(client, course="")
    assert response.status_code == 201
    assert len(client.get("/portal/pdfs/student", headers=headers("other-student")).json()["pdfs"]) == 1
