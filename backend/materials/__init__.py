"""Course-material ingestion and retrieval for Advisor AI."""

from .ingestion import COURSE_FOLDERS, ingest_semester_archive
from .retrieval import embed_text

__all__ = ["COURSE_FOLDERS", "embed_text", "ingest_semester_archive"]
