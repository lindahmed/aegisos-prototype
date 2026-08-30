# AegisOS EDU Prototype

AegisOS EDU is a personalized student computing environment running on Ubuntu + XFCE. The current
milestone proves the complete non-AI path:

`XFCE -> Electron launcher -> FastAPI -> SQLite -> student workspace -> VS Code`

The Advisor AI and the Semester Progress Agent use Gemini only after the deterministic
SQLite-backed academic data has been calculated. Set `GEMINI_API_KEY` in `.env` to enable
AI recommendations; grades and academic facts always remain database-derived.

## Repository layout

- `frontend/` - secure Electron login/dashboard UI.
- `mobile/` - Flutter student app connected to the same FastAPI/PostgreSQL data source.
- `backend/` - FastAPI integration endpoints.
- `database/` - CSV seed data, SQLite repository, and database initializer.
- `workspace/` - controlled folder and VS Code actions.
- `vm/` - repeatable Ubuntu + Node 22 runtime setup.
- `desktop/` - XFCE launcher, autostart installer, logo, and wallpaper.
- `docs/` - integration and acceptance instructions.

## Fresh Ubuntu setup

Clone the repository as the normal Ubuntu user, then run:

```bash
cd ~/aegisos-prototype
chmod +x vm/setup.sh desktop/setup-desktop.sh desktop/start-aegis.sh start-aegis.sh
./vm/setup.sh
./desktop/setup-desktop.sh
```

`vm/setup.sh` installs the base packages, installs Node 22 through nvm, creates `.venv`, installs the
backend and Electron dependencies, configures Electron's Linux SUID sandbox, initializes SQLite, and
runs automated checks.

VS Code is a documented manual dependency. Confirm its shell command works before the demo:

```bash
code --version
```

Log out, choose **Xfce Session**, and confirm:

```bash
echo $XDG_CURRENT_DESKTOP
```

The output must contain `XFCE`.

## Run AegisOS manually

From the repository root:

```bash
./desktop/start-aegis.sh
```

The script starts FastAPI on `127.0.0.1:8000`, waits for `/health`, and starts Electron with the
required `npm start` contract. It also checks Node 22 and the Electron sandbox before launch.

If `npm ci` or `npm install` is run again, restore the sandbox permissions:

```bash
cd ~/aegisos-prototype/frontend
sudo chown root:root node_modules/electron/dist/chrome-sandbox
sudo chmod 4755 node_modules/electron/dist/chrome-sandbox
ls -l node_modules/electron/dist/chrome-sandbox
```

The mode must begin with `-rwsr-xr-x` and the owner/group must be `root root`. Do not use
`--no-sandbox` as the project solution.

## Demo student IDs

- `231027905` - Yasmin Wael
- `231027906` - Ziad Ahmed
- `231027907` - Mariam Hassan

## API contract

- `GET /health`
- `GET /student/{student_id}`
- `POST /workspace/create`
- `POST /workspace/vscode`
- `POST /advisor`
- `GET /progress/{student_id}` - current Student Digital Twin.
- `POST /progress/analyze/{student_id}` - runs the LangGraph progress workflow and saves
  weekly snapshots/interventions when a grounded intervention is needed.
- `GET /progress/{student_id}/weekly` - saved course metrics by week.
- `GET /progress/{student_id}/interventions` - recommendation history.
- `POST /progress/{student_id}/what-if` - read-only assessment-grade projection.

When `DATABASE_URL` is configured, FastAPI uses the normalized PostgreSQL/Supabase database
from the Database branch for student profiles and current course enrollments. SQLite remains
the local fallback and explicit test database. The current PostgreSQL schema does not yet
contain assessments, lectures, materials, or completion records, so progress health is returned
as unavailable rather than fabricated until those portal records are added.

The initial SQLite prototype contained profiles and enrollments only. The initializer now
adds the related course, lecture, assessment, material, grade, snapshot, and intervention
tables, plus clearly scoped prototype academic records for the registered demo students.
Replace those seed records with Task 1/SIS or portal imports when that data source is ready;
the progress agent reads only through `StudentRepository`.

## Flutter mobile app

The app in `mobile/` talks to FastAPI; FastAPI is the only component that receives
`DATABASE_URL`. This keeps the PostgreSQL password out of APK, IPA, and web bundles while
still using the same Supabase data as the desktop and portal clients.

Start the API so other devices can reach it:

```bash
python -m uvicorn backend.app:app --host 0.0.0.0 --port 8000
```

Then run Flutter. The default URL is `http://10.0.2.2:8000`, which is correct for an Android
emulator. For a physical phone, iOS simulator, web, or a deployed API, pass the reachable URL:

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://YOUR_COMPUTER_LAN_IP:8000
```

Use HTTPS for production deployments. Student sign-in currently matches the portal prototype:
it validates a student registration number through `GET /student/{student_id}` and then shows
that student's PostgreSQL-backed profile and current courses.

Workspace requests use this JSON shape:

```json
{
  "student_id": "231027905",
  "course": "Artificial Intelligence"
}
```

Only courses enrolled for that SQLite student are accepted. VS Code is launched with an argument
array, never raw shell text.

## Developer checks

```bash
cd ~/aegisos-prototype
.venv/bin/python -m pytest
cd frontend
npm run check
```

Complete the manual checks in [`docs/CORE_MILESTONE_CHECKLIST.md`](docs/CORE_MILESTONE_CHECKLIST.md)
before adding Gemini or LangGraph.
