"""PDF metadata queries against the portal's existing SQLite/PostgreSQL database."""

from __future__ import annotations

from typing import Any

from .postgres_repository import PostgresStudentRepository


class PortalPdfStore:
    def __init__(self, repository: Any) -> None:
        self.repository = repository
        self.postgres = isinstance(repository, PostgresStudentRepository)

    def _read(self, sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
        with self.repository._connect() as connection:
            if self.postgres:
                with connection.cursor() as cursor:
                    cursor.execute(sql, params)
                    return [dict(row) for row in cursor.fetchall()]
            return [dict(row) for row in connection.execute(sql, params).fetchall()]

    def _write(self, sql: str, params: tuple[Any, ...]) -> None:
        with self.repository._connect() as connection:
            if self.postgres:
                with connection.cursor() as cursor:
                    cursor.execute(sql, params)
            else:
                connection.execute(sql, params)

    def instructor_courses(self, instructor_id: str) -> list[dict[str, Any]]:
        if self.postgres:
            return self._read(
                """SELECT c.course_code AS course_id, c.course_title AS course_name
                   FROM portal_instructor_courses assigned
                   JOIN courses c ON c.course_code = assigned.course_id
                   WHERE assigned.instructor_id = %s ORDER BY c.course_title""",
                (instructor_id,),
            )
        return self._read(
            """SELECT c.course_id, c.course_name FROM portal_instructor_courses assigned
               JOIN course_offerings c ON c.course_id = assigned.course_id
               WHERE assigned.instructor_id = ? ORDER BY c.course_name""",
            (instructor_id,),
        )

    def is_registered_student_auth(self, auth_user_id: str, student_id: str) -> bool:
        """Existing production student accounts are linked by user_profiles."""
        if not self.postgres or not auth_user_id:
            return False
        return bool(self._read(
            """SELECT 1 FROM user_profiles
               WHERE user_id::text = %s AND student_id::text = %s LIMIT 1""",
            (auth_user_id, student_id),
        ))

    def list_staff(self, instructor_id: str) -> list[dict[str, Any]]:
        return self._read(
            f"""SELECT pdf.*, {('c.course_title' if self.postgres else 'c.course_name')} AS course_name
                FROM portal_pdfs pdf
                LEFT JOIN {('courses' if self.postgres else 'course_offerings')} c
                  ON {('c.course_code' if self.postgres else 'c.course_id')} = pdf.course_id
                WHERE pdf.instructor_id = {('%s' if self.postgres else '?')}
                ORDER BY pdf.uploaded_at DESC""",
            (instructor_id,),
        )

    def list_student(self, student_id: str) -> list[dict[str, Any]]:
        if self.postgres:
            return self._read(
                """SELECT pdf.*, c.course_title AS course_name FROM portal_pdfs pdf
                   LEFT JOIN courses c ON c.course_code = pdf.course_id
                   WHERE pdf.course_id IS NULL OR EXISTS (
                       SELECT 1 FROM student_courses enrollment
                       WHERE enrollment.student_id::text = %s
                         AND enrollment.course_code = pdf.course_id
                         AND enrollment.status = 'Current')
                   ORDER BY pdf.uploaded_at DESC""",
                (student_id,),
            )
        return self._read(
            """SELECT pdf.*, offering.course_name FROM portal_pdfs pdf
               LEFT JOIN course_offerings offering ON offering.course_id = pdf.course_id
               WHERE pdf.course_id IS NULL OR EXISTS (
                   SELECT 1 FROM courses enrollment
                   WHERE enrollment.student_id = ?
                     AND enrollment.course_name = offering.course_name
                     AND enrollment.status = 'Current')
               ORDER BY pdf.uploaded_at DESC""",
            (student_id,),
        )

    def get(self, pdf_id: str) -> dict[str, Any] | None:
        rows = self._read(
            f"SELECT * FROM portal_pdfs WHERE pdf_id = {('%s' if self.postgres else '?')}",
            (pdf_id,),
        )
        return rows[0] if rows else None

    def insert(self, pdf: dict[str, Any]) -> None:
        fields = ("pdf_id", "instructor_id", "course_id", "title", "description",
                  "original_filename", "storage_path", "size_bytes", "uploaded_at")
        placeholders = ", ".join(["%s" if self.postgres else "?"] * len(fields))
        self._write(
            f"INSERT INTO portal_pdfs ({', '.join(fields)}) VALUES ({placeholders})",
            tuple(pdf[field] for field in fields),
        )

    def delete_owned(self, pdf_id: str, instructor_id: str) -> bool:
        marker = "%s" if self.postgres else "?"
        with self.repository._connect() as connection:
            if self.postgres:
                with connection.cursor() as cursor:
                    cursor.execute(
                        f"DELETE FROM portal_pdfs WHERE pdf_id = {marker} AND instructor_id = {marker}",
                        (pdf_id, instructor_id),
                    )
                    return cursor.rowcount > 0
            cursor = connection.execute(
                f"DELETE FROM portal_pdfs WHERE pdf_id = {marker} AND instructor_id = {marker}",
                (pdf_id, instructor_id),
            )
            return cursor.rowcount > 0
