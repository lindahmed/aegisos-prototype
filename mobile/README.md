# UNI Track mobile app

**Guide. Track. Evolve.**

Flutter client for the UNI Track student experience. It validates a student ID with the
project FastAPI backend and displays the student's profile and current courses from the
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
python -m uvicorn backend.app:app --host 0.0.0.0 --port 8001
```

Then start Flutter:

```bash
cd mobile
flutter pub get
flutter run
```

The default API URL is the deployed Railway service:

```text
https://web-production-3a6ad.up.railway.app
```

Override it only when intentionally testing another backend:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8001
```

For local development on an Android emulator, use `http://10.0.2.2:8001`
after starting FastAPI on port 8001.

## Checks

```bash
flutter analyze
flutter test
```

## iOS

The iOS app uses Swift Package Manager for Flutter plugins and supports iOS 15
or later. Microphone and speech-recognition permission descriptions are already
configured for Advisor AI.

Build and run on an iPhone Simulator:

```bash
flutter pub get
flutter run -d "iPhone 18 Pro"
```

Build a release for a physical iPhone without signing:

```bash
flutter build ios --release --no-codesign
```

To install on a physical iPhone or create an IPA, open
`ios/Runner.xcworkspace` in Xcode, select an Apple development Team under
Signing & Capabilities, and build the Runner target.
