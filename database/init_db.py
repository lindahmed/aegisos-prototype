from pathlib import Path

from database.repository import StudentRepository


def main() -> None:
    database_path = Path(__file__).with_name("aegisos.db")
    repository = StudentRepository(database_path)
    repository.initialize()
    print(f"AegisOS student database ready: {database_path}")


if __name__ == "__main__":
    main()
