# AegisOS EDU Prototype

AegisOS EDU is a personalized student computing environment running on Ubuntu + XFCE. The current
milestone proves the complete non-AI path:

`XFCE -> Electron launcher -> FastAPI -> SQLite -> student workspace -> VS Code`

Gemini and LangGraph are intentionally gated until this path passes the VM acceptance checklist.

## Repository layout

- `frontend/` - secure Electron login/dashboard UI.
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
