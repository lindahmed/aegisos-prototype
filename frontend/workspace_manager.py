"""Compatibility entry point for the old Person 2 workspace demo.

The live application uses the FastAPI endpoints in backend/app.py. This module remains
only so old team commands fail safely and exercise the same controlled manager.
"""

import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from workspace.manager import WorkspaceManager  # noqa: E402


def main() -> None:
    manager = WorkspaceManager(PROJECT_ROOT / "workspace" / "students")
    path = manager.create_course_workspace("demo", "Artificial Intelligence")
    print(f"Demo workspace ready: {path}")


if __name__ == "__main__":
    main()
