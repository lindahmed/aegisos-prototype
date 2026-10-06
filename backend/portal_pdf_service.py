"""Standalone PDF API. Academic data stays on the existing API; no DB is opened."""

from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from io import BytesIO
from pathlib import Path
from uuid import UUID, uuid4

import httpx
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pypdf import PdfReader

PROJECT_ROOT = Path(__file__).resolve().parents[1]
load_dotenv(PROJECT_ROOT / ".env", override=False)
PDF_MAX_BYTES = 10 * 1024 * 1024
DEFAULT_ACADEMIC_API = "https://web-production-3a6ad.up.railway.app"


def create_pdf_app(*, storage_root: Path | None = None,
                   academic_api_url: str | None = None) -> FastAPI:
    configured_root = storage_root or Path(os.environ.get(
        "AEGIS_PDF_STORAGE_ROOT", PROJECT_ROOT / "workspace" / "materials" / "portal-pdfs"
    ))
    root = (PROJECT_ROOT / configured_root).resolve()
    academic_api = (academic_api_url or os.environ.get(
        "AEGIS_ACADEMIC_API_URL", DEFAULT_ACADEMIC_API
    )).rstrip("/")
    api = FastAPI(title="AAST Portal PDF API")
    origins = os.environ.get("AEGIS_PORTAL_ORIGINS", "http://127.0.0.1:5174,http://localhost:5174,http://127.0.0.1:5173,http://localhost:5173")
    api.add_middleware(CORSMiddleware, allow_origins=[item.strip() for item in origins.split(",") if item.strip()],
                       allow_methods=["GET", "POST", "DELETE"], allow_headers=["Authorization", "Content-Type"])

    def actor(authorization: str | None = Header(default=None)) -> tuple[str, str]:
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(401, "Sign in to access PDFs")
        token = authorization[7:].strip()
        supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
        anon_key = os.environ.get("SUPABASE_ANON_KEY", "")
        if not token:
            raise HTTPException(401, "Sign in to access PDFs")
        if not supabase_url or not anon_key:
            raise HTTPException(503, "Supabase Auth is not configured")
        try:
            response = httpx.get(f"{supabase_url}/auth/v1/user", headers={
                "apikey": anon_key, "Authorization": f"Bearer {token}",
            }, timeout=8)
        except httpx.RequestError as error:
            raise HTTPException(503, "Authentication service unavailable") from error
        if response.status_code != 200:
            raise HTTPException(401, "Invalid or expired session")
        user = response.json()
        email = str(user.get("email") or "").lower()
        metadata = user.get("app_metadata") or {}
        for role, domain in (("staff", "staff.aegisos.local"),
                             ("student", "students.aegisos.local")):
            suffix = f"@{domain}"
            if not email.endswith(suffix):
                continue
            portal_id = email[:-len(suffix)]
            if not portal_id.isdigit() or len(portal_id) > 32:
                break
            if role == "staff":
                allowed = {value.strip() for value in os.environ.get("AEGIS_STAFF_IDS", "104217").split(",")}
                if (portal_id in allowed and metadata.get("portal_role") == "staff"
                        and metadata.get("portal_id") == portal_id):
                    return role, portal_id
            elif (metadata.get("portal_role") in (None, "student")
                  and metadata.get("portal_id") in (None, portal_id)):
                # Existing student accounts have no portal app_metadata. Their
                # confirmed Auth email plus the academic API establish identity.
                if not user.get("email_confirmed_at"):
                    break
                try:
                    student = httpx.get(f"{academic_api}/student/{portal_id}", timeout=8)
                except httpx.RequestError as error:
                    raise HTTPException(503, "Academic service unavailable") from error
                if student.status_code == 200:
                    return role, portal_id
                if student.status_code != 404:
                    raise HTTPException(503, "Academic service unavailable")
            break
        raise HTTPException(403, "Account is not authorized for this portal")

    def staff(identity: tuple[str, str] = Depends(actor)) -> str:
        if identity[0] != "staff":
            raise HTTPException(403, "Staff access required")
        return identity[1]

    def student(identity: tuple[str, str] = Depends(actor)) -> str:
        if identity[0] != "student":
            raise HTTPException(403, "Student access required")
        return identity[1]

    def path_for(pdf_id: str, suffix: str) -> Path:
        try:
            normalized = str(UUID(pdf_id))
        except ValueError as error:
            raise HTTPException(404, "PDF not found") from error
        return root / f"{normalized}{suffix}"

    def read_record(pdf_id: str) -> dict[str, object] | None:
        try:
            source = path_for(pdf_id, ".json")
            record = json.loads(source.read_text(encoding="utf-8"))
            if (not isinstance(record, dict) or record.get("pdf_id") != pdf_id
                    or not isinstance(record.get("uploaded_at"), str)
                    or not isinstance(record.get("instructor_id"), str)
                    or not path_for(pdf_id, ".pdf").is_file()):
                return None
            return record
        except (FileNotFoundError, ValueError, OSError, AttributeError, HTTPException):
            return None

    def records() -> list[dict[str, object]]:
        if not root.exists():
            return []
        items = [record for path in root.glob("*.json")
                 if (record := read_record(path.stem)) is not None]
        return sorted(items, key=lambda item: str(item["uploaded_at"]), reverse=True)

    def checked_record(pdf_id: str, owner_id: str | None = None) -> dict[str, object]:
        record = read_record(pdf_id)
        if record is None or (owner_id is not None and record["instructor_id"] != owner_id):
            raise HTTPException(404, "PDF not found")
        return record

    def file_response(pdf_id: str, download: bool, record: dict[str, object]) -> FileResponse:
        return FileResponse(path_for(pdf_id, ".pdf"), media_type="application/pdf",
                            filename=str(record["original_filename"]) if download else None,
                            content_disposition_type="attachment" if download else "inline",
                            headers={"X-Content-Type-Options": "nosniff", "Content-Security-Policy": "sandbox"})

    @api.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @api.get("/portal/pdfs/staff/courses")
    def instructor_courses(_: str = Depends(staff)) -> dict[str, list[object]]:
        # No instructor-course assignment source exists in the unchanged DB.
        return {"courses": []}

    @api.get("/portal/pdfs/staff")
    def list_staff_pdfs(instructor_id: str = Depends(staff)) -> dict[str, object]:
        return {"pdfs": [item for item in records() if item["instructor_id"] == instructor_id]}

    @api.post("/portal/pdfs/staff", status_code=201)
    async def upload_staff_pdf(file: UploadFile = File(...), title: str = Form(...),
                               description: str = Form(""), course_id: str = Form(""),
                               instructor_id: str = Depends(staff)) -> dict[str, object]:
        clean_title, clean_description = title.strip(), description.strip()
        if not clean_title or len(clean_title) > 160:
            raise HTTPException(422, "Title must be 1–160 characters")
        if len(clean_description) > 2000:
            raise HTTPException(422, "Description must be at most 2000 characters")
        if course_id.strip():
            raise HTTPException(403, "Course-specific uploads need an instructor assignment")
        filename = (file.filename or "").replace("\\", "/").split("/")[-1]
        if not filename or len(filename) > 255 or not filename.lower().endswith(".pdf"):
            raise HTTPException(422, "Choose a PDF file")
        if file.content_type not in ("application/pdf", "application/octet-stream"):
            raise HTTPException(422, "Choose a PDF file")
        contents = await file.read(PDF_MAX_BYTES + 1)
        await file.close()
        if len(contents) > PDF_MAX_BYTES:
            raise HTTPException(413, "PDF must be 10 MB or smaller")
        if not contents.startswith(b"%PDF-"):
            raise HTTPException(422, "File is not a valid PDF")
        try:
            reader = PdfReader(BytesIO(contents), strict=True)
            if reader.is_encrypted or len(reader.pages) < 1:
                raise ValueError("Encrypted or empty PDF")
        except Exception as error:
            raise HTTPException(422, "File is not a valid, readable PDF") from error

        pdf_id = str(uuid4())
        record = {"pdf_id": pdf_id, "instructor_id": instructor_id, "course_id": None,
                  "course_name": None, "title": clean_title,
                  "description": clean_description or None, "original_filename": filename,
                  "size_bytes": len(contents), "uploaded_at": datetime.now(UTC).isoformat()}
        root.mkdir(parents=True, exist_ok=True)
        pdf_path, record_path = path_for(pdf_id, ".pdf"), path_for(pdf_id, ".json")
        temp_pdf, temp_record = root / f"{pdf_id}.pdf.tmp", root / f"{pdf_id}.json.tmp"
        try:
            temp_pdf.write_bytes(contents)
            os.replace(temp_pdf, pdf_path)
            temp_record.write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
            os.replace(temp_record, record_path)
        except OSError as error:
            for path in (temp_pdf, temp_record, pdf_path, record_path):
                path.unlink(missing_ok=True)
            raise HTTPException(500, "Could not store PDF") from error
        return {"pdf": record}

    @api.get("/portal/pdfs/student")
    def list_student_pdfs(_: str = Depends(student)) -> dict[str, object]:
        return {"pdfs": records()}

    @api.get("/portal/pdfs/student/{pdf_id}/file")
    def student_file(pdf_id: str, download: bool = False,
                     _: str = Depends(student)) -> FileResponse:
        return file_response(pdf_id, download, checked_record(pdf_id))

    @api.get("/portal/pdfs/staff/{pdf_id}/file")
    def staff_file(pdf_id: str, download: bool = False,
                   instructor_id: str = Depends(staff)) -> FileResponse:
        return file_response(pdf_id, download, checked_record(pdf_id, instructor_id))

    @api.delete("/portal/pdfs/staff/{pdf_id}", status_code=204)
    def delete_staff_pdf(pdf_id: str, instructor_id: str = Depends(staff)) -> None:
        checked_record(pdf_id, instructor_id)
        path_for(pdf_id, ".json").unlink(missing_ok=True)
        path_for(pdf_id, ".pdf").unlink(missing_ok=True)

    return api


app = create_pdf_app()
