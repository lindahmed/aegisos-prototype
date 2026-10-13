from pathlib import Path

import pytest

from workspace.manager import (
    WorkspaceManager,
    course_environment,
    validate_requirements,
)


def test_rejects_student_path_traversal(tmp_path: Path) -> None:
    manager = WorkspaceManager(tmp_path / "students")
    with pytest.raises(ValueError, match="unsupported characters"):
        manager.create_student_workspace("../../outside")


def test_course_folder_is_stable_and_safe(tmp_path: Path) -> None:
    manager = WorkspaceManager(tmp_path / "students")
    path = manager.create_course_workspace("231027906", "C++ OOP")
    assert path.name == "C_OOP"
    assert path.parent.name == "231027906"


def test_open_vscode_rejects_path_outside_workspace(tmp_path: Path) -> None:
    manager = WorkspaceManager(tmp_path / "students", launcher=lambda _path: None)
    outside = tmp_path / "outside"
    outside.mkdir()
    with pytest.raises(ValueError):
        manager.open_vscode(outside)


def test_artificial_intelligence_has_a_pinned_environment() -> None:
    profile = course_environment("Artificial Intelligence")
    assert profile is not None
    assert "numpy==2.5.3" in profile.packages
    assert "pandas==3.0.6" in profile.packages


def test_custom_requirements_reject_shell_and_file_options() -> None:
    with pytest.raises(ValueError, match="Unsupported dependency"):
        validate_requirements(["numpy; Remove-Item important.txt"])
    with pytest.raises(ValueError, match="Unsupported dependency"):
        validate_requirements(["-r requirements.txt"])


def test_unknown_course_dry_run_writes_validated_requirements(tmp_path: Path) -> None:
    manager = WorkspaceManager(tmp_path / "students")
    result = manager.setup_course_environment(
        "231027905",
        "Compiler Design",
        ["lark==1.2.2", "pytest>=8.0"],
        install=False,
    )
    requirements_file = Path(result["requirements_file"])
    assert requirements_file.read_text(encoding="utf-8") == "lark==1.2.2\npytest>=8.0\n"
    assert result["profile"] == "custom"
    assert result["install_requested"] is False
    assert (requirements_file.parent / ".vscode" / "settings.json").is_file()
    assert "lark==1.2.2" in (requirements_file.parent / "WORKSTATION.md").read_text(
        encoding="utf-8"
    )
