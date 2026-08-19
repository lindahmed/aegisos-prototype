from pathlib import Path

import pytest

from workspace.manager import WorkspaceManager


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
