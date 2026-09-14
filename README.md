# Uni Track

Uni Track is a multi-client educational platform with a shared backend and database. The repository contains the FastAPI backend, PostgreSQL/Supabase data layer, Flutter mobile app, web/student portal, desktop components, and supporting scripts.

## Architecture

```text
Flutter Mobile  ──────┐
Web / Portal    ──────┼──> FastAPI Backend ───> PostgreSQL / Supabase
Desktop Client  ──────┘            │
                                   └──> Gemini Advisor (when configured)
```

The Android app should talk to the FastAPI backend, not directly to the database.

---

# Install the UNI Track Android app

If you only want to use the app and do not want to edit the source code:

1. Download `uni-track-mobile-v1.1.0.apk` from the project's GitHub **Releases** page.
2. Open the downloaded APK on an Android phone.
3. If Android asks for permission to install apps from this source, enable **Install unknown apps** for the browser/file manager you used.
4. Install and open **UNI Track**.
5. Keep the phone connected to the internet because the app uses the online backend.

> The APK is for Android. iPhone/iOS distribution requires a separate iOS build and Apple signing process.

---

# Developer setup

## 1. Clone the repository

```bash
git clone <REPOSITORY_URL>
cd aegisos-prototype-main
```

## 2. Install the required tools

### Git

Check:

```bash
git --version
```

Official site: https://git-scm.com/

### Python 3.12+

The backend uses modern Python type syntax, so use Python 3.12 or newer.

Check:

```bash
python3.12 --version
```

Official macOS downloads: https://www.python.org/downloads/macos/

### Flutter

Install the current stable Flutter SDK.

Check:

```bash
flutter --version
flutter doctor
```

Official installation guide: https://docs.flutter.dev/get-started/install

### Android Studio

Android Studio provides the Android SDK, platform tools, emulator, and device tooling used by Flutter.

Official download: https://developer.android.com/studio

After installation, make sure Flutter can see Android devices:

```bash
flutter devices
```

### Node.js

Node.js is needed for the JavaScript/TypeScript web and desktop-related parts of the repository.

Use the current Node.js LTS release.

Official download: https://nodejs.org/

Check:

```bash
node --version
npm --version
```

### Railway CLI — optional

Railway is only needed if you are deploying or managing the hosted FastAPI backend. It is not required just to run the Android app against an already deployed backend.

Official CLI docs: https://docs.railway.com/cli

---

# Environment variables

The real secrets are **not stored in GitHub**.

Create your local environment file from the example:

```bash
cp .env.example .env
```

Then edit `.env` and provide the values you are authorized to use:

```env
DATABASE_URL=postgresql://USER:PASSWORD@HOST:PORT/DATABASE
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=your_neo4j_password
AEGIS_CURRENT_SEMESTER=...
AEGIS_SEMESTER_START_DATE=2026-08-08
GEMINI_API_KEY=your_gemini_api_key_here
GEMINI_MODEL=gemini-3.5-flash
GEMINI_FALLBACK_MODELS=gemini-3.5-flash-lite
GEMINI_TIMEOUT_MS=30000
```

Important:

- Never commit `.env`.
- Never put a real database password or Gemini API key in `.env.example`.
- Never paste project secrets into issues, pull requests, or screenshots.
- Ask the project owner for Supabase/Railway access when needed instead of sharing passwords manually.

The repository `.gitignore` is configured to exclude local environment/secrets and development-only files.

---

# Run the backend locally

From the repository root:

## 1. Create a Python virtual environment

```bash
python3.12 -m venv .venv
```

Activate it on macOS/Linux:

```bash
source .venv/bin/activate
```

Confirm the version:

```bash
python --version
```

## 2. Install backend dependencies

```bash
python -m pip install --upgrade pip
python -m pip install -r backend/requirements.txt
```

## 3. Start FastAPI

```bash
python -m uvicorn backend.app:app --host 0.0.0.0 --port 8000
```

Expected startup includes a message showing the API is connected to PostgreSQL when `DATABASE_URL` is configured.

Test the API:

```bash
curl http://127.0.0.1:8000/health
```

Expected response:

```json
{"status":"ok"}
```

FastAPI interactive docs are available locally at:

```text
http://127.0.0.1:8000/docs
```

---

# Database / Supabase

When `DATABASE_URL` is configured, the backend connects to the PostgreSQL/Supabase database.

The mobile app does **not** connect directly to Supabase. The flow is:

```text
Mobile -> FastAPI -> PostgreSQL/Supabase
```

To test a student endpoint locally, use a valid student ID that exists in the connected database:

```bash
curl http://127.0.0.1:8000/student/<STUDENT_ID>
```

Do not assume demo IDs from old prototype databases exist in the real database.

## Synchronize the Neo4j academic graph

Neo4j is rebuilt from the PostgreSQL course catalogue and prerequisite tables;
there is no separate hard-coded curriculum to maintain. Validate the source
snapshot first:

```bash
python -m backend.advisor.seed_neo4j --dry-run
```

Then synchronize Neo4j (this replaces the existing Course, Programme, and
Student nodes in the academic graph):

```bash
python -m backend.advisor.seed_neo4j
```

The synchronization imports every course and prerequisite relationship. When
available, it also imports department plans, major electives, programmes, and
student-to-programme enrollment.

## Semester course-material library

The material pipeline maps files to official course codes, removes exact
duplicates, excludes system metadata and named student submissions, preserves
private originals, extracts page/slide text, creates citable chunks and
summaries, and publishes a hybrid full-text/vector index. Exam papers and model
answers are labeled `exam_practice` and are never presented as predictions of a
future exam.

Import an approved archive into the private local library and SQLite index:

```bash
python scripts/ingest_semester_materials.py \
  --archive "/path/to/Semester 5.zip" \
  --database database/aegisos.db \
  --storage-root workspace/materials
```

Publish the resulting metadata, summaries, and vectors to PostgreSQL:

```bash
python scripts/sync_materials_to_postgres.py --database database/aegisos.db
```

Students can browse `/portal/students/{student_id}/materials`, search
`/portal/students/{student_id}/materials/search?q=...`, download authorized
source files, or ask Advisor AI for a cited summary or explanation. Access is
restricted by the student's major and current programme semester. Files marked
`needs_ocr` remain downloadable but are not used as text evidence until an OCR
worker processes them.

An optional `scripts/ocr_materials.py` worker can transcribe scanned PDFs with
the configured Gemini service while preserving page numbers. This sends each
selected PDF to that external service and must only be run when the material
owner has explicitly approved that transfer.

---

# Run the Flutter mobile app

Go to the Flutter project:

```bash
cd mobile
```

Install Dart/Flutter dependencies:

```bash
flutter pub get
```

See available devices:

```bash
flutter devices
```

Run on a selected device:

```bash
flutter run -d <DEVICE_ID>
```

Example for an emulator:

```bash
flutter run -d emulator-5554
```

## Backend URL used by the mobile app

The API configuration is in:

```text
mobile/lib/services/api_service.dart
```

The current project is configured to use the deployed online backend by default.

If you intentionally want to test against a FastAPI backend running locally on the same Mac with the standard Android Emulator, use:

```text
http://10.0.2.2:8000
```

`10.0.2.2` is an Android Emulator address that maps back to the host computer. It is **not** the correct production address for a real phone.

For a real Android phone that should work anywhere, use the deployed HTTPS backend URL.

---

# Run on a real Android phone

1. On Android, enable **Developer options**.
2. Enable **USB debugging**.
3. Connect the phone to the development computer.
4. Accept the **Allow USB debugging** prompt on the phone.
5. Check that Flutter sees the phone:

```bash
flutter devices
```

6. Run the app using the displayed device ID:

```bash
cd mobile
flutter run -d <ANDROID_DEVICE_ID>
```

The project has been tested using a real Android device against the online backend.

---

# Build the Android APK

From the `mobile` directory:

```bash
flutter build apk --release
```

The generated release APK is located at:

```text
mobile/build/app/outputs/flutter-apk/app-release.apk
```

On macOS, you can open that directory with:

```bash
open build/app/outputs/flutter-apk/
```

The `build/` directory is generated output and normally should not be committed to Git. Upload the final APK as a **GitHub Release asset** if you want users to download it easily.

---

# Deploy / manage the backend on Railway

The repository contains:

```text
Procfile
requirements.txt
```

These support deployment of the FastAPI service.

If you already have access to the existing Railway project, use that project rather than creating a duplicate production backend.

## Railway login

```bash
railway login
```

If normal browser login is inconvenient:

```bash
railway login --browserless
```

## Check account

```bash
railway whoami
```

## Environment variables on Railway

Production secrets should be configured as Railway service variables, especially:

```text
DATABASE_URL
GEMINI_API_KEY
GEMINI_MODEL
GEMINI_FALLBACK_MODELS
GEMINI_TIMEOUT_MS
```

Do not commit those values to GitHub.

## Deploy

After the Railway project/service is linked:

```bash
railway up --service backend
```

After deployment, verify:

```text
https://<YOUR_RAILWAY_DOMAIN>/health
https://<YOUR_RAILWAY_DOMAIN>/docs
```

---

# Gemini Advisor

Advisor functionality requires a valid Gemini API key on the backend environment:

```env
GEMINI_API_KEY=...
```

If it is missing, student/database functionality may still work while the Advisor reports that AI is not configured.

For production, the Gemini key belongs on Railway (or the server hosting FastAPI), **not inside the Flutter APK**.

---

# Web / portal development

The repository also includes the AAST portal under:

```text
aast-portal/
```

Typical setup:

```bash
cd aast-portal
npm install
npm run dev
```

See `aast-portal/package.json` and its local README for the scripts supported by that part of the project.

---

# Repository structure

```text
.
├── aast-portal/       # Student/staff web portal
├── backend/           # FastAPI API, Advisor and progress logic
├── database/          # PostgreSQL/SQLite repository layer and database helpers
├── desktop/           # Desktop environment/assets/scripts
├── docs/              # Project documentation
├── frontend/          # Desktop/Electron frontend
├── mobile/            # Flutter mobile application
├── scripts/           # Utility/demo scripts
├── vm/                # VM setup
├── workspace/         # Student workspace management
├── Procfile           # Hosted backend start configuration
└── requirements.txt   # Root deployment dependency list
```

---

# Useful troubleshooting

## `python: command not found`

Activate the virtual environment first:

```bash
source .venv/bin/activate
```

Then verify:

```bash
python --version
```

## `No pubspec.yaml file found`

You are not inside the Flutter project. Run:

```bash
cd mobile
```

Then retry the Flutter command.

## Port 8000 is already in use

Check which process owns it:

```bash
lsof -i :8000
```

Stop the old backend process before starting another one.

## Flutter cannot see the Android phone

Check Android Debug Bridge:

```bash
~/Library/Android/sdk/platform-tools/adb devices
```

On the phone, verify USB debugging is enabled and accept the computer authorization prompt.

## Advisor does not respond

Check that:

- The backend `/health` endpoint works.
- The mobile app is pointing to the correct backend URL.
- `GEMINI_API_KEY` is configured on the backend host.
- `GEMINI_MODEL` names an available model; transient `429`/`5xx` failures
  automatically try the models in `GEMINI_FALLBACK_MODELS`.
- `GEMINI_TIMEOUT_MS` limits each model attempt so one busy model cannot hold
  the Advisor request until the app gives up.
- Railway/backend logs do not show an exception.

---

# Handoff checklist for another developer

Before starting work, a new developer should have:

- Access to the GitHub repository.
- Flutter installed.
- Android Studio + Android SDK installed for Android development.
- Python 3.12+ installed.
- Node.js installed if working on the web/desktop frontend.
- A local `.env` created from `.env.example` if running the backend locally.
- Authorized Supabase access if database administration is needed.
- Authorized Railway access if production backend deployment is needed.
- Their own/authorized Gemini API key access if working on Advisor functionality.

They do **not** need your `.venv`, Flutter SDK folder, Android Studio installation folder, or local build artifacts from your computer. Those are recreated on each developer machine.

---

# Security

Never commit or publish:

```text
.env
Database passwords
Supabase service secrets
Gemini API keys
Private Railway tokens
Private credentials
```

Use `.env.example` only for variable names and safe placeholder values.
