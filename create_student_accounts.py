"""
Creates real Supabase Auth login accounts for existing students.

Run this ONCE per student (it skips anyone who already has an account).
Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in your .env file.

Usage (from your project root, inside the activated venv):
    python create_student_accounts.py
"""
import os
import secrets
import string
import csv
import requests
from dotenv import load_dotenv
import psycopg2
import psycopg2.extras

load_dotenv()

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
DATABASE_URL = os.environ["DATABASE_URL"]

HEADERS = {
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
}


def generate_password(length: int = 12) -> str:
    alphabet = string.ascii_letters + string.digits + "!@#$%"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def create_auth_user(email: str, password: str) -> str:
    """Creates a real Supabase Auth account, returns the new user's UUID."""
    response = requests.post(
        f"{SUPABASE_URL}/auth/v1/admin/users",
        headers=HEADERS,
        json={"email": email, "password": password, "email_confirm": True},
        timeout=15,
    )
    response.raise_for_status()
    return response.json()["id"]


def main() -> None:
    connection = psycopg2.connect(DATABASE_URL, cursor_factory=psycopg2.extras.RealDictCursor)
    cursor = connection.cursor()

    cursor.execute(
        """SELECT s.student_id, s.full_name
           FROM students s
           WHERE NOT EXISTS (
               SELECT 1 FROM user_profiles up WHERE up.student_id = s.student_id
           )"""
    )
    students = cursor.fetchall()
    print(f"Found {len(students)} students without an account.")

    results = []
    for student in students:
        student_id = student["student_id"]
        email = f"{student_id}@students.aegisos.local"
        password = generate_password()
        try:
            user_id = create_auth_user(email, password)
        except requests.HTTPError as error:
            print(f"  FAILED for {student_id}: {error.response.text}")
            continue

        cursor.execute(
            """INSERT INTO user_profiles (user_id, student_id, display_name, email)
               VALUES (%s, %s, %s, %s)""",
            (user_id, student_id, student["full_name"], email),
        )
        cursor.execute(
            """INSERT INTO user_roles (user_id, role_name) VALUES (%s, 'student')""",
            (user_id,),
        )
        connection.commit()
        results.append({"student_id": student_id, "name": student["full_name"], "password": password})
        print(f"  created account for {student_id} ({student['full_name']})")

    with open("student_passwords.csv", "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["student_id", "name", "password"])
        writer.writeheader()
        writer.writerows(results)

    print(f"\nDone. {len(results)} accounts created.")
    print("Passwords saved to student_passwords.csv -- keep this file secure and delete it after distributing.")

    cursor.close()
    connection.close()


if __name__ == "__main__":
    main()
