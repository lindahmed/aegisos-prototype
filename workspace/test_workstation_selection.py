"""The student chooses which of a course's packages to install."""

from __future__ import annotations

from pathlib import Path

from workspace.manager import WorkspaceManager

AI = "Introduction to Artificial Intelligence"
ALL = ["numpy==2.5.3", "pandas==3.0.6", "scikit-learn==1.9.1", "matplotlib==3.11.2", "jupyterlab==4.6.3"]
PICK = ["numpy==2.5.3", "pandas==3.0.6"]


def test_without_a_choice_everything_is_selected(tmp_path: Path) -> None:
    result = WorkspaceManager(tmp_path / "students").inspect_course_environment("231027905", AI)
    assert result["requirements"] == ALL and result["selected_requirements"] == ALL
    assert result["missing_requirements"] == ALL


def test_only_the_ticked_packages_are_selected_and_written(tmp_path: Path) -> None:
    manager = WorkspaceManager(tmp_path / "students")
    result = manager.setup_course_environment("231027905", AI, selected_requirements=PICK, install=False)
    assert result["requirements"] == ALL                       # the full package is still on offer
    assert result["selected_requirements"] == PICK
    assert result["missing_requirements"] == PICK             # only what was chosen would be installed
    assert Path(result["requirements_file"]).read_text(encoding="utf-8") == "numpy==2.5.3\npandas==3.0.6\n"
    guide = (Path(result["requirements_file"]).parent / "WORKSTATION.md").read_text(encoding="utf-8")
    assert "numpy==2.5.3" in guide and "jupyterlab" not in guide


def test_the_choice_is_remembered_next_time(tmp_path: Path) -> None:
    manager = WorkspaceManager(tmp_path / "students")
    manager.setup_course_environment("231027905", AI, selected_requirements=PICK, install=False)
    again = manager.inspect_course_environment("231027905", AI)       # no selection sent
    assert again["selected_requirements"] == PICK


def test_unknown_names_are_ignored_and_other_students_are_unaffected(tmp_path: Path) -> None:
    manager = WorkspaceManager(tmp_path / "students")
    result = manager.inspect_course_environment(
        "231027905", AI, selected_requirements=["numpy==2.5.3", "evil-package==1.0"])
    assert result["selected_requirements"] == ["numpy==2.5.3"]
    other = manager.inspect_course_environment("231027906", AI)
    assert other["selected_requirements"] == ALL


def test_only_chosen_packages_are_passed_to_pip(tmp_path: Path) -> None:
    manager = WorkspaceManager(tmp_path / "students")
    commands: list[list[str]] = []
    manager._find_python = lambda: Path("python3")                        # type: ignore[method-assign]
    manager._checked_run = lambda command, message, timeout=180: commands.append(command)  # type: ignore[method-assign]
    result = manager.setup_course_environment("231027905", AI, selected_requirements=PICK, install=True)
    install = next(c for c in commands if "install" in c and "numpy==2.5.3" in c)
    assert install[-2:] == PICK and "jupyterlab==4.6.3" not in install
    assert result["installed_requirements"] == PICK


def test_choosing_nothing_installs_nothing(tmp_path: Path) -> None:
    manager = WorkspaceManager(tmp_path / "students")
    manager._find_python = lambda: None                                     # type: ignore[method-assign]
    result = manager.setup_course_environment("231027905", AI, selected_requirements=[], install=True)
    assert result["selected_requirements"] == [] and result["setup_complete"] is True
    assert Path(result["requirements_file"]).read_text(encoding="utf-8") == ""


def test_a_package_added_later_starts_selected(tmp_path: Path) -> None:
    manager = WorkspaceManager(tmp_path / "students")
    manager.setup_course_environment("231027905", "Compiler Design", ["lark==1.2.2"],
                                     selected_requirements=[], install=False)
    result = manager.inspect_course_environment("231027905", "Compiler Design", ["lark==1.2.2", "pytest>=8.0"])
    assert result["selected_requirements"] == ["pytest>=8.0"]      # lark was unticked, pytest is new
