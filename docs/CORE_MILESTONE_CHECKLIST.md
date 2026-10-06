# Core Milestone Acceptance Checklist

This checklist is the gate between the base AegisOS EDU prototype and the later Gemini/LangGraph
phase. Run it inside the Ubuntu VM, not from another computer.

## 1. Runtime and XFCE

```bash
cd ~/aegisos-prototype
git pull origin main
./vm/setup.sh
./desktop/setup-desktop.sh
echo $XDG_CURRENT_DESKTOP
node --version
```

Pass conditions:

- Desktop output contains `XFCE`.
- Node output begins with `v22.`.
- All Python and frontend checks in `vm/setup.sh` pass.
- `chrome-sandbox` is owned by `root root` with mode `4755`.

## 2. Manual Electron launch

```bash
cd ~/aegisos-prototype
./desktop/start-aegis.sh
```

Pass conditions:

- No Chromium SUID sandbox error appears.
- Electron displays the AegisOS login screen.
- Student ID `231027905` loads Yasmin Wael from SQLite.
- An invalid ID displays `Student not found`.

## 3. Workspace and VS Code

In the dashboard, choose **Artificial Intelligence** and click **Create / open folder**, then
**Open in VS Code**.

Pass conditions:

- `workspace/students/231027905/Artificial_Intelligence/` exists.
- It contains `README.md`, `assignments/`, and `labs/`.
- VS Code opens that exact folder.
- A course not enrolled for the student cannot be requested through the API.

## 4. XFCE launchers

Stop the manual process with `Ctrl+C`. Test the **AegisOS EDU** desktop icon, then log out and back into
the Xfce Session.

Pass conditions:

- The desktop icon starts the same working flow.
- XFCE autostart opens AegisOS after login.
- The Aegis wallpaper and launcher icon are visible.

## 5. Phase gate

Commit the VM-tested checkpoint only after sections 1-4 pass. Gemini/LangGraph work begins after this
gate, following the attached full prototype workflow.
