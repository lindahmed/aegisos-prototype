"""The standalone PDF service must never need or write an academic database."""

from __future__ import annotations

from io import BytesIO
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient
from pypdf import PdfWriter

from backend.portal_pdf_service import create_pdf_app


def valid_pdf() -> bytes:
    output = BytesIO()
    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    writer.write(output)
    return output.getvalue()


@pytest.fixture
def service(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "test-publishable-key")
    monkeypatch.setenv("AEGIS_STAFF_IDS", "104217")

    def get(url: str, *, headers=None, timeout: int):
        if url.endswith("/auth/v1/user"):
            token = headers["Authorization"].removeprefix("Bearer ")
            users = {
                "staff": ("104217@staff.aegisos.local", {"portal_role": "staff", "portal_id": "104217"}),
                "other-staff": ("999999@staff.aegisos.local", {"portal_role": "staff", "portal_id": "999999"}),
                "student": ("231003445@students.aegisos.local", {}),
                "other-student": ("231003446@students.aegisos.local", {}),
                "forged-student": ("231003445@students.aegisos.local", {"portal_role": "staff"}),
            }
            if token not in users:
                return httpx.Response(401)
            email, metadata = users[token]
            return httpx.Response(200, json={"email": email, "app_metadata": metadata,
                                              "email_confirmed_at": "2026-01-01T00:00:00Z"})
        if url.endswith("/student/231003445") or url.endswith("/student/231003446"):
            return httpx.Response(200, json={"student_id": url.rsplit("/", 1)[-1]})
        raise AssertionError(f"Unexpected GET: {url}")

    monkeypatch.setattr("backend.portal_pdf_service.httpx.get", get)
    root = tmp_path / "pdfs"
    return TestClient(create_pdf_app(storage_root=root)), root


def headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def upload(client: TestClient, *, file: bytes | None = None, course_id: str = ""):
    return client.post("/portal/pdfs/staff", headers=headers("staff"),
                       data={"title": "Lecture notes", "description": "Week one", "course_id": course_id},
                       files={"file": ("lecture.pdf", file if file is not None else valid_pdf(),
                                       "application/pdf")})


def test_upload_visibility_view_download_delete_without_database(service):
    client, root = service
    assert client.get("/portal/pdfs/staff/courses", headers=headers("staff")).json() == {"courses": []}
    response = upload(client)
    assert response.status_code == 201, response.text
    pdf = response.json()["pdf"]
    pdf_id = pdf["pdf_id"]
    assert pdf["course_id"] is None
    assert (root / f"{pdf_id}.pdf").read_bytes() == valid_pdf()
    assert (root / f"{pdf_id}.json").is_file()
    assert len(client.get("/portal/pdfs/staff", headers=headers("staff")).json()["pdfs"]) == 1
    assert client.get("/portal/pdfs/student", headers=headers("student")).json()["pdfs"][0]["pdf_id"] == pdf_id
    assert client.get("/portal/pdfs/student", headers=headers("other-student")).json()["pdfs"][0]["pdf_id"] == pdf_id
    file_path = f"/portal/pdfs/student/{pdf_id}/file"
    viewed = client.get(file_path, headers=headers("student"))
    assert viewed.status_code == 200 and viewed.content == valid_pdf()
    assert viewed.headers["content-type"] == "application/pdf"
    downloaded = client.get(file_path + "?download=true", headers=headers("student"))
    assert "attachment" in downloaded.headers["content-disposition"]
    assert client.get(file_path).status_code == 401
    assert client.get(file_path, headers=headers("staff")).status_code == 403
    assert client.get(file_path, headers=headers("forged-student")).status_code == 403
    assert client.delete(f"/portal/pdfs/staff/{pdf_id}", headers=headers("other-staff")).status_code == 403
    assert client.delete(f"/portal/pdfs/staff/{pdf_id}", headers=headers("staff")).status_code == 204
    assert not (root / f"{pdf_id}.pdf").exists()
    assert not (root / f"{pdf_id}.json").exists()
    assert client.get(file_path, headers=headers("student")).status_code == 404


def test_rejects_invalid_oversize_unassigned_and_unauthorized(service):
    client, root = service
    assert upload(client, course_id="CCS4505").status_code == 403
    assert upload(client, file=b"not a PDF").status_code == 422
    assert upload(client, file=valid_pdf() + b"x" * (10 * 1024 * 1024)).status_code == 413
    assert client.post("/portal/pdfs/staff", headers=headers("student"),
                       data={"title": "No"}, files={"file": ("x.pdf", valid_pdf(), "application/pdf")}).status_code == 403
    assert client.get("/portal/pdfs/staff", headers=headers("invalid")).status_code == 401
    assert not root.exists() or not list(root.glob("*.pdf"))


def test_records_survive_service_restart(service):
    client, root = service
    pdf_id = upload(client).json()["pdf"]["pdf_id"]
    restarted = TestClient(create_pdf_app(storage_root=root))
    assert restarted.get("/portal/pdfs/student", headers=headers("student")).json()["pdfs"][0]["pdf_id"] == pdf_id
