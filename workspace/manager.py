from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import urllib.error
import urllib.request
import sysconfig
from datetime import datetime
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
        selected_requirements: Sequence[str] | None = None,
    ) -> dict[str, object]:
        """Report the course's packages and which of them the student chose to install.

        `requirements` is everything the course offers.  The student installs only the
        `selected_requirements`: what they just ticked, else what they chose last time,
        else everything.
        """
        path = self.create_course_workspace(student_id, course)
        profile = course_environment(course)
        requirements = validate_requirements((*profile.packages, *custom_requirements)) if profile else validate_requirements(custom_requirements)
        chosen = self._choose_requirements(path, requirements, selected_requirements)
        python = self._find_python()
        python_options = self._python_options()
        venv_python = self._venv_python(path)
        installed = self._installed_packages(venv_python) if venv_python.exists() else {}
        satisfied = [
            requirement for requirement in requirements
            if self._requirement_satisfied(requirement, installed)
        ]
        missing = [requirement for requirement in chosen if requirement not in satisfied]
        return {
            "path": str(path),
            "profile": profile.key if profile else "custom",
            "profile_label": profile.label if profile else "Custom course setup",
            "known_course": profile is not None,
            "python_found": python is not None,
            "python_version": self._python_version(python) if python else None,
            "python_options": python_options,
            "virtual_environment_found": venv_python.exists(),
            "requirements": list(requirements),
            "selected_requirements": chosen,
            "satisfied_requirements": satisfied,
            "installed_packages": [
                {"name": name, "version": version}
                for name, version in sorted(installed.items())
            ],
            "package_versions": self._package_versions(requirements),
            "missing_requirements": missing,
            "notes": list(profile.notes if profile else ()),
        }

    _SELECTION_FILE = ".workstation-selection.json"

    def package_installations(self, student_id: str, limit: int = 30) -> list[dict[str, str]]:
        history = self.student_path(student_id) / ".package-installations.json"
        try:
            items = json.loads(history.read_text(encoding="utf-8"))
            return [item for item in items if isinstance(item, dict)][:limit]
        except (OSError, ValueError, TypeError):
            return []

    def install_package(self, student_id: str, course: str, package: str, version: str) -> list[dict[str, str]]:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", package) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.!+_-]*", version):
            raise ValueError("Enter a valid package name and version")
        path = self.create_course_workspace(student_id, course)
        python = self._venv_python(path)
        if not python.exists():
            base_python = self._find_python()
            if base_python is None:
                raise ToolUnavailableError("Python is not installed on this device")
            self._checked_run([str(base_python), "-m", "venv", str(path / ".venv")], "Could not create the course Python environment")
        self._checked_run([str(python), "-m", "pip", "install", "--disable-pip-version-check", f"{package}=={version}"], f"Could not install {package} {version}", timeout=900)
        installed = self._installed_packages(python)
        normalized = package.lower().replace("_", "-")
        actual_version = installed.get(normalized, version)
        history = self.student_path(student_id) / ".package-installations.json"
        records = self.package_installations(student_id)
        records.insert(0, {"name": package, "version": actual_version, "course": course, "installed_at": datetime.now().astimezone().isoformat(timespec="seconds")})
        history.write_text(json.dumps(records[:100], indent=2) + "\n", encoding="utf-8")
        return records[:30]

    def _choose_requirements(
        self, path: Path, requirements: Sequence[str], selected: Sequence[str] | None
    ) -> list[str]:
        """The packages to install: the student's pick, their saved pick, or everything."""
        if selected is not None:
            wanted = set(selected)
            return [item for item in requirements if item in wanted]
        saved = path / self._SELECTION_FILE
        try:
            data = json.loads(saved.read_text(encoding="utf-8"))
            offered_before = set(data["offered"])
            wanted = set(data["selected"])
        except (OSError, ValueError, KeyError, TypeError):
            return list(requirements)
        # A package that was not on offer last time is new, so it starts out selected.
        return [item for item in requirements if item in wanted or item not in offered_before]

    def _save_selection(self, path: Path, requirements: Sequence[str], chosen: Sequence[str]) -> None:
        (path / self._SELECTION_FILE).write_text(
            json.dumps({"offered": list(requirements), "selected": list(chosen)}, indent=2) + "\n",
            encoding="utf-8",
        )

    def setup_course_environment(
        self,
        student_id: str,
        course: str,
        custom_requirements: Sequence[str] = (),
        *,
        install: bool = True,
        selected_requirements: Sequence[str] | None = None,
        python_executable: str | None = None,
        python_version: str | None = None,
        package_versions: dict[str, str] | None = None,
        remove_packages: Sequence[str] = (),
    ) -> dict[str, object]:
        requirements = list(self._selected_requirements(course, custom_requirements, package_versions or {}))
        selected_names = {
            re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)", item).group(1).lower()
            for item in selected_requirements
        } if selected_requirements is not None else None
        chosen = [
            item for item in requirements
            if selected_names is None
            or re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)", item).group(1).lower() in selected_names
        ]
        status = self.inspect_course_environment(student_id, course, requirements, chosen)
        path = Path(str(status["path"]))
        # The student's own package: only the requirements they chose are written and installed.
        requirements = tuple(str(item) for item in status["selected_requirements"])
        self._save_selection(path, [str(item) for item in status["requirements"]], requirements)
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

        if not install or (not requirements and not python_version and not remove_packages):
            status["setup_complete"] = not requirements or not status["missing_requirements"]
            return status

        python = self._validated_python(python_executable) if python_executable else self._find_python()
        if python_version:
            if not re.fullmatch(r"3\.(?:8|9|10|11|12|13|14)(?:\.\d+)?", python_version):
                raise ValueError("Choose a supported Python version from the list")
            python = self._install_managed_python(python_version, python)
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

        if venv_python.exists():
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

        if remove_packages and venv_python.exists():
            installed_now = self._installed_packages(venv_python)
            removals = sorted({str(name).lower().replace("_", "-") for name in remove_packages} & set(installed_now))
            if removals:
                self._checked_run(
                    [str(venv_python), "-m", "pip", "uninstall", "-y", *removals],
                    "Could not remove the selected packages",
                    timeout=300,
                )
        missing = [str(item) for item in status["missing_requirements"]]
        if missing:
            self._checked_run(
                [str(venv_python), "-m", "pip", "install", "--disable-pip-version-check", *missing],
                "Could not install the course dependencies",
                timeout=900,
            )
        status.update(
            self.inspect_course_environment(
                student_id, course, custom_requirements, list(requirements)
            )
        )
        status["requirements_file"] = str(requirements_file)
        status["installed_requirements"] = missing
        status["install_requested"] = True
        status["setup_complete"] = not status["missing_requirements"]
        return status

    def _install_managed_python(self, version: str, bootstrap_python: Path | None) -> Path:
        """Use uv's platform-specific managed runtimes, keeping them separate from system Python."""
        uv = shutil.which("uv")
        if not uv:
            if bootstrap_python is None:
                raise ToolUnavailableError("Install Python or uv first to download a managed Python version.")
            self._checked_run(
                [str(bootstrap_python), "-m", "pip", "install", "--user", "uv"],
                "Could not prepare the Python version installer", timeout=300,
            )
            scripts = Path(sysconfig.get_path("scripts", "nt" if os.name == "nt" else "posix_user"))
            uv = str(scripts / ("uv.exe" if os.name == "nt" else "uv"))
            if not Path(uv).is_file():
                uv = shutil.which("uv")
            if not uv:
                raise ToolUnavailableError("The Python installer was prepared but its uv command was not found.")
        self._checked_run([uv, "python", "install", version], "Could not download the selected Python version", timeout=900)
        result = self._run([uv, "python", "find", version], capture_output=True, text=True, timeout=30, check=False)
        if result.returncode != 0 or not result.stdout.strip():
            raise WorkstationSetupError("Python downloaded, but its interpreter could not be located")
        return Path(result.stdout.strip().splitlines()[0]).resolve()

    def _python_options(self) -> list[dict[str, str]]:
        candidates: dict[str, dict[str, str]] = {}
        for name in ("python", "python3", "python3.13", "python3.12", "python3.11", "python3.10"):
            executable = shutil.which(name)
            if not executable:
                continue
            version = self._python_version(Path(executable))
            if version:
                candidates[executable] = {"path": executable, "version": version}
        return sorted(
            candidates.values(),
            key=lambda item: tuple(
                int(part) for part in re.findall(r"\d+", item["version"])
            ),
            reverse=True,
        )

    def _validated_python(self, requested: str) -> Path:
        available = {item["path"] for item in self._python_options()}
        if requested not in available:
            raise ValueError("Choose a Python interpreter detected on this device")
        return Path(requested)

    @staticmethod
    def _package_versions(requirements: Sequence[str], *, limit: int | None = 12) -> dict[str, list[str]]:
        result: dict[str, list[str]] = {}
        for requirement in requirements:
            match = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)", requirement)
            if not match:
                continue
            package = match.group(1)
            try:
                request = urllib.request.Request(f"https://pypi.org/pypi/{package}/json", headers={"User-Agent": "AegisOS-Workstation"})
                with urllib.request.urlopen(request, timeout=2) as response:
                    releases = json.loads(response.read().decode("utf-8")).get("releases", {})
                versions = sorted(
                    (version for version, files in releases.items() if files),
                    key=lambda value: tuple(int(part) for part in re.findall(r"\d+", value)),
                    reverse=True,
                )
                result[package.lower()] = versions[:limit] if limit else versions
            except (OSError, ValueError, urllib.error.URLError, json.JSONDecodeError):
                result[package.lower()] = []
        return result

    @staticmethod
    def _selected_requirements(course: str, custom: Sequence[str], versions: dict[str, str]) -> tuple[str, ...]:
        profile = course_environment(course)
        requirements = validate_requirements((*profile.packages, *custom)) if profile else validate_requirements(custom)
        selected: list[str] = []
        for requirement in requirements:
            name = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)", requirement).group(1)
            version = versions.get(name.lower())
            selected.append(f"{name}=={version}" if version else requirement)
        return validate_requirements(selected)

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
