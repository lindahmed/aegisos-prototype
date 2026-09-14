from __future__ import annotations

import re
import shutil
import subprocess
import unicodedata
from pathlib import Path
from typing import Callable


class ToolUnavailableError(RuntimeError):
    """Raised when an approved desktop tool is not installed."""


def _safe_student_id(student_id: str) -> str:
    normalized = student_id.strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", normalized):
        raise ValueError("Student ID contains unsupported characters")
    return normalized


def _course_folder(course: str) -> str:
    ascii_course = (
        unicodedata.normalize("NFKD", course).encode("ascii", "ignore").decode("ascii")
    )
    normalized = re.sub(r"[^A-Za-z0-9]+", "_", ascii_course).strip("_")
    if not normalized:
        raise ValueError("Course name cannot be converted to a safe folder name")
    return normalized


class WorkspaceManager:
    def __init__(
        self,
        root: Path,
        *,
        launcher: Callable[[Path], None] | None = None,
    ) -> None:
        self.root = Path(root).expanduser().resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self._launcher = launcher or self._launch_vscode

    def student_path(self, student_id: str) -> Path:
        path = (self.root / _safe_student_id(student_id)).resolve()
        path.relative_to(self.root)
        return path

    def create_student_workspace(self, student_id: str) -> Path:
        path = self.student_path(student_id)
        path.mkdir(parents=True, exist_ok=True)
        return path

    def create_course_workspace(self, student_id: str, course: str) -> Path:
        path = self.create_student_workspace(student_id) / _course_folder(course)
        path.mkdir(parents=True, exist_ok=True)
        (path / "assignments").mkdir(exist_ok=True)
        (path / "labs").mkdir(exist_ok=True)
        readme = path / "README.md"
        if not readme.exists():
            readme.write_text(
                f"# {course}\n\nAegisOS EDU workspace for student {student_id}.\n",
                encoding="utf-8",
            )
        return path

    def open_vscode(self, path: Path) -> None:
        resolved = Path(path).resolve()
        resolved.relative_to(self.root)
        if not resolved.is_dir():
            raise ValueError("Workspace path does not exist")
        self._launcher(resolved)

    @staticmethod
    def _launch_vscode(path: Path) -> None:
        executable = shutil.which("code")
        if executable is None:
            raise ToolUnavailableError(
                "VS Code command 'code' is unavailable. Install VS Code and enable its shell command."
            )
        subprocess.Popen(
            [executable, str(path)],
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
