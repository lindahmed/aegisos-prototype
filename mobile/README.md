# AegisOS Advisor mobile app

Flutter client for the AegisOS student experience. It validates a student ID with the
AegisOS FastAPI backend and displays the student's profile and current courses from the
same PostgreSQL/Supabase database used by the rest of the project. Its Advisor AI chat
supports career guidance, semester planning, course questions, and academic progress.

## Architecture

The app intentionally does not connect directly to PostgreSQL. Mobile binaries can be
inspected, so embedding `DATABASE_URL` would expose the database password. The connection is:

`Flutter app -> FastAPI /student/{student_id} -> PostgreSQL/Supabase`

Advisor questions use the existing grounded backend flow:

`Flutter chat -> FastAPI /advisor -> student context + Advisor AI`

The root `.env` remains the single place where the backend reads `DATABASE_URL`.

## Run locally

Start FastAPI from the repository root:

```bash
python -m uvicorn backend.app:app --host 0.0.0.0 --port 8000
```

Then start Flutter:

```bash
cd mobile
flutter pub get
flutter run
```

The default API URL is `http://10.0.2.2:8000` for an Android emulator. Override it for
other targets without editing source:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8000
```

For a physical device, replace the example address with the development computer's LAN IP
and allow port 8000 through the local firewall. Use an HTTPS API URL for production builds.

## Checks

```bash
flutter analyze
flutter test
```
