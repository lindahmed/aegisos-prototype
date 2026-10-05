#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FRONTEND_DIR="$PROJECT_ROOT/frontend"
API_URL="http://127.0.0.1:8000"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/aegisos"
BACKEND_LOG="$STATE_DIR/backend.log"
BACKEND_PID=""

if [[ -z "${DATABASE_URL:-}" ]] && ! grep -qE '^DATABASE_URL=[^[:space:]]+' "$PROJECT_ROOT/.env" 2>/dev/null; then
    echo "UniTrack requires DATABASE_URL for the Supabase-backed backend." >&2
    exit 1
fi

mkdir -p "$STATE_DIR"

if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    # XFCE launchers do not load the interactive shell profile, so load nvm here.
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    # shellcheck disable=SC1091
    source "$NVM_DIR/nvm.sh"
    nvm use --silent 22 >/dev/null
fi

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "UniTrack requires Node.js 22 and npm. Run vm/setup.sh first." >&2
    exit 1
fi

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [[ "$NODE_MAJOR" != "22" ]]; then
    echo "UniTrack requires Node.js 22; found $(node --version). Run vm/setup.sh first." >&2
    exit 1
fi

if [[ ! -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
    echo "UniTrack Python environment is missing. Run vm/setup.sh first." >&2
    exit 1
fi

if [[ ! -d "$FRONTEND_DIR/node_modules/electron" ]]; then
    echo "Electron dependencies are missing. Run vm/setup.sh first." >&2
    exit 1
fi

SANDBOX="$FRONTEND_DIR/node_modules/electron/dist/chrome-sandbox"
if [[ ! -f "$SANDBOX" ]] || [[ "$(stat -c '%U:%G:%a' "$SANDBOX")" != "root:root:4755" ]]; then
    echo "Electron's chrome-sandbox permissions are not configured." >&2
    echo "Run these commands from $FRONTEND_DIR:" >&2
    echo "  sudo chown root:root node_modules/electron/dist/chrome-sandbox" >&2
    echo "  sudo chmod 4755 node_modules/electron/dist/chrome-sandbox" >&2
    exit 1
fi

cleanup() {
    if [[ -n "$BACKEND_PID" ]] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        kill "$BACKEND_PID"
        wait "$BACKEND_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

if ! curl --silent --fail "$API_URL/health" >/dev/null 2>&1; then
    (
        cd "$PROJECT_ROOT"
        exec .venv/bin/python -m uvicorn backend.app:app --host 127.0.0.1 --port 8000
    ) >>"$BACKEND_LOG" 2>&1 &
    BACKEND_PID=$!

    for _ in {1..30}; do
        if curl --silent --fail "$API_URL/health" >/dev/null 2>&1; then
            break
        fi
        if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
            echo "UniTrack backend failed to start. See $BACKEND_LOG" >&2
            exit 1
        fi
        sleep 0.5
    done
fi

if ! curl --silent --fail "$API_URL/health" >/dev/null 2>&1; then
    echo "UniTrack backend did not become ready. See $BACKEND_LOG" >&2
    exit 1
fi

echo "Starting UniTrack..."
cd "$FRONTEND_DIR"
AEGIS_API_URL="$API_URL" AEGIS_ACADEMIC_API_URL="$API_URL" npm start
