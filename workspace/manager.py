from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence


class ToolUnavailableError(RuntimeError):
    """Raised when an approved desktop tool is not installed."""


class WorkstationSetupError(RuntimeError):
    """Raised when a course workstation cannot be prepared safely."""


@dataclass(frozen=True)
class CourseEnvironmentProfile:
    key: str
    label: str
    aliases: tuple[str, ...]
    python_version: str | None = "3.12+"
    packages: tuple[str, ...] = ()
    notes: tuple[str, ...] = ()


COURSE_ENVIRONMENTS: tuple[CourseEnvironmentProfile, ...] = (
    CourseEnvironmentProfile(
        "intro-ai",
        "Introduction to Artificial Intelligence",
        ("artificial intelligence", "introduction to artificial intelligence", "intro to ai"),
        packages=(
            "numpy==2.5.3",
            "pandas==3.0.6",
            "scikit-learn==1.9.1",
            "matplotlib==3.11.2",
            "jupyterlab==4.6.3",
        ),
        notes=("Includes notebooks, data analysis, plotting, and introductory ML tooling.",),
    ),
    CourseEnvironmentProfile(
        "data-structures",
        "Data Structures",
        ("data structures",),
        packages=("pytest==8.3.3", "mypy==1.13.0"),
    ),
    CourseEnvironmentProfile(
        "cpp-oop",
        "C++ Object-Oriented Programming",
        ("c++ oop", "object oriented programming", "object-oriented programming"),
        python_version=None,
        notes=("Uses the system C++ compiler. Python packages are not required.",),
    ),
    CourseEnvironmentProfile(
        "operating-systems",
        "Operating Systems",
        ("operating systems",),
        packages=("pytest==8.3.3",),
        notes=("Native labs may also require the compiler and Linux tools supplied by the course VM.",),
    ),
    CourseEnvironmentProfile(
        "software-engineering",
        "Software Engineering",
        ("software engineering",),
        packages=("pytest==8.3.3", "requests==2.32.3", "ruff==0.7.4"),
    ),
    CourseEnvironmentProfile(
        "discrete-mathematics",
        "Discrete Mathematics",
        ("discrete mathematics",),
        packages=("sympy==1.13.3", "jupyterlab==4.2.5"),
    ),
    CourseEnvironmentProfile(
        "software-security",
        "Software Security",
        ("software security",),
        packages=("bandit==1.7.10", "pytest==8.3.3"),
    ),
    CourseEnvironmentProfile(
        "network-security",
        "Network Security",
        ("network security",),
        packages=("scapy==2.6.1", "cryptography==43.0.3"),
        notes=("Packet capture exercises can require administrator privileges.",),
    ),
    CourseEnvironmentProfile(
        "digital-forensics",
        "Digital Forensics",
        ("digital forensics",),
        packages=("python-magic==0.4.27", "pillow==11.0.0"),
        notes=("On Windows, libmagic may need the course-provided native runtime.",),
    ),
)

_REQUIREMENT_PATTERN = re.compile(
    r"^[A-Za-z0-9][A-Za-z0-9._-]*(?:\[[A-Za-z0-9_,.-]+\])?"
    r"(?:\s*(?:===|==|~=|!=|<=|>=|<|>)\s*[A-Za-z0-9*+.!_-]+)?$"
)


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


def _normalized_course(course: str) -> str:
    return re.sub(r"\s+", " ", course.strip().lower())


def _package_name(requirement: str) -> str:
    return re.split(r"\[|===|==|~=|!=|<=|>=|<|>", requirement, maxsplit=1)[0].lower().replace("_", "-")


def validate_requirements(requirements: Sequence[str]) -> tuple[str, ...]:
    if len(requirements) > 50:
        raise ValueError("A course can request at most 50 Python packages")
    validated: list[str] = []
    seen: set[str] = set()
    for raw in requirements:
        requirement = raw.strip()
        if not requirement:
            continue
        if len(requirement) > 120 or not _REQUIREMENT_PATTERN.fullmatch(requirement):
            raise ValueError(
                f"Unsupported dependency '{requirement}'. Use a package name and optional version, such as numpy==2.1.3."
            )
        name = _package_name(requirement)
        if name not in seen:
            validated.append(requirement)
            seen.add(name)
    return tuple(validated)


def course_environment(course: str) -> CourseEnvironmentProfile | None:
    normalized = _normalized_course(course)
    return next(
        (profile for profile in COURSE_ENVIRONMENTS if normalized in profile.aliases),
        None,
    )


class WorkspaceManager:
    def __init__(
        self,
        root: Path,
        *,
        launcher: Callable[[Path], None] | None = None,
        command_runner: Callable[..., subprocess.CompletedProcess[str]] | None = None,
    ) -> None:
        self.root = Path(root).expanduser().resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self._launcher = launcher or self._launch_vscode
        self._run = command_runner or subprocess.run

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

    def inspect_course_environment(
        self,
        student_id: str,
        course: str,
        custom_requirements: Sequence[str] = (),
    ) -> dict[str, object]:
        path = self.create_course_workspace(student_id, course)
        profile = course_environment(course)
        requirements = profile.packages if profile else validate_requirements(custom_requirements)
        python = self._find_python()
        venv_python = self._venv_python(path)
        installed = self._installed_packages(venv_python) if venv_python.exists() else {}
        missing = [
            requirement for requirement in requirements
            if not self._requirement_satisfied(requirement, installed)
        ]
        return {
            "path": str(path),
            "profile": profile.key if profile else "custom",
            "profile_label": profile.label if profile else "Custom course setup",
            "known_course": profile is not None,
            "python_found": python is not None,
            "python_version": self._python_version(python) if python else None,
            "virtual_environment_found": venv_python.exists(),
            "requirements": list(requirements),
            "missing_requirements": missing,
            "notes": list(profile.notes if profile else ()),
        }

    def setup_course_environment(
        self,
        student_id: str,
        course: str,
        custom_requirements: Sequence[str] = (),
        *,
        install: bool = True,
    ) -> dict[str, object]:
        status = self.inspect_course_environment(student_id, course, custom_requirements)
        path = Path(str(status["path"]))
        requirements = tuple(str(item) for item in status["requirements"])
        requirements_file = path / "requirements.txt"
        requirements_file.write_text(
            "".join(f"{item}\n" for item in requirements),
            encoding="utf-8",
        )
        self._write_workspace_config(path, requirements)
        status["requirements_file"] = str(requirements_file)
        status["installed_requirements"] = []
        status["setup_complete"] = not status["missing_requirements"]
        status["install_requested"] = install

        if not install or not requirements:
            status["setup_complete"] = not requirements or not status["missing_requirements"]
            return status

        python = self._find_python()
        if python is None:
            raise ToolUnavailableError(
                "Python is not installed. Install Python 3.12 or newer, then run Smart setup again."
            )

        venv_python = self._venv_python(path)
        if not venv_python.exists():
            self._checked_run(
                [str(python), "-m", "venv", str(path / ".venv")],
                "Could not create the course virtual environment",
            )
            self._checked_run(
                [
                    str(venv_python),
                    "-m",
                    "pip",
                    "install",
                    "--upgrade",
                    "pip",
                    "setuptools",
                    "wheel",
                ],
                "Could not initialize the course package installer",
                timeout=300,
            )

        missing = [str(item) for item in status["missing_requirements"]]
        if missing:
            self._checked_run(
                [str(venv_python), "-m", "pip", "install", "--disable-pip-version-check", *missing],
                "Could not install the course dependencies",
                timeout=900,
            )
        status.update(self.inspect_course_environment(student_id, course, custom_requirements))
        status["requirements_file"] = str(requirements_file)
        status["installed_requirements"] = missing
        status["install_requested"] = True
        status["setup_complete"] = not status["missing_requirements"]
        return status

    @staticmethod
    def _write_workspace_config(path: Path, requirements: Sequence[str]) -> None:
        ignore_file = path / ".gitignore"
        if not ignore_file.exists():
            ignore_file.write_text(".venv/\n__pycache__/\n.ipynb_checkpoints/\n", encoding="utf-8")

        vscode_directory = path / ".vscode"
        vscode_directory.mkdir(exist_ok=True)
        vscode_settings = vscode_directory / "settings.json"
        if not vscode_settings.exists():
            interpreter = (
                "${workspaceFolder}/.venv/Scripts/python.exe"
                if os.name == "nt"
                else "${workspaceFolder}/.venv/bin/python"
            )
            vscode_settings.write_text(
                json.dumps({"python.defaultInterpreterPath": interpreter}, indent=2) + "\n",
                encoding="utf-8",
            )

        activation = (
            ".venv\\Scripts\\Activate.ps1"
            if os.name == "nt"
            else "source .venv/bin/activate"
        )
        guide = [
            "# Smart workstation\n",
            "This course uses its own isolated Python environment.\n",
            "## Activate it\n",
            f"```text\n{activation}\n```\n",
        ]
        if requirements:
            guide.extend(("## Managed dependencies\n", *(f"- `{item}`\n" for item in requirements)))
        (path / "WORKSTATION.md").write_text("\n".join(guide), encoding="utf-8")

    def open_vscode(self, path: Path) -> None:
        resolved = Path(path).resolve()
        resolved.relative_to(self.root)
        if not resolved.is_dir():
            raise ValueError("Workspace path does not exist")
        self._launcher(resolved)

    @staticmethod
    def _venv_python(path: Path) -> Path:
        return path / ".venv" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")

    @staticmethod
    def _find_python() -> Path | None:
        candidates = [Path(sys.executable)] if sys.executable else []
        candidates.extend(Path(value) for name in ("python3.12", "python3.11", "python3", "python") if (value := shutil.which(name)))
        return next((candidate.resolve() for candidate in candidates if candidate.is_file()), None)

    def _python_version(self, python: Path) -> str | None:
        try:
            result = self._run(
                [str(python), "--version"], capture_output=True, text=True, timeout=15, check=False,
            )
        except (OSError, subprocess.SubprocessError):
            return None
        return (result.stdout or result.stderr).strip() or None

    def _installed_packages(self, python: Path) -> dict[str, str]:
        try:
            result = self._run(
                [str(python), "-m", "pip", "list", "--format=json", "--disable-pip-version-check"],
                capture_output=True, text=True, timeout=60, check=False,
            )
            if result.returncode != 0:
                return {}
            return {
                str(item["name"]).lower().replace("_", "-"): str(item["version"])
                for item in json.loads(result.stdout)
            }
        except (OSError, subprocess.SubprocessError, json.JSONDecodeError, KeyError, TypeError):
            return {}

    @staticmethod
    def _requirement_satisfied(requirement: str, installed: dict[str, str]) -> bool:
        name = _package_name(requirement)
        installed_version = installed.get(name)
        if installed_version is None:
            return False
        exact = re.search(r"={2,3}\s*([A-Za-z0-9*+.!_-]+)$", requirement)
        return exact is None or installed_version == exact.group(1)

    def _checked_run(self, command: list[str], message: str, timeout: int = 180) -> None:
        try:
            result = self._run(
                command, capture_output=True, text=True, timeout=timeout, check=False,
            )
        except (OSError, subprocess.SubprocessError) as error:
            raise WorkstationSetupError(f"{message}: {error}") from error
        if result.returncode != 0:
            details = (result.stderr or result.stdout or "Unknown installer error").strip()
            raise WorkstationSetupError(f"{message}: {details[-600:]}")

    @staticmethod
    def _launch_vscode(path: Path) -> None:
        executable = shutil.which("code")
        if executable is None:
            raise ToolUnavailableError(
                "VS Code command 'code' is unavailable. Install VS Code and enable its shell command."
            )
        subprocess.Popen(
            [executable, str(path)], start_new_session=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
