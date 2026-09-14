#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "$EUID" -eq 0 ]]; then
    echo "Run this script as the Ubuntu user, not as root. It will use sudo when needed." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NVM_VERSION="v0.40.3"

echo "[1/6] Installing Ubuntu runtime packages..."
sudo apt update
sudo apt install -y build-essential curl git python3 python3-pip python3-venv sqlite3

echo "[2/6] Installing Node.js 22 with nvm..."
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    curl --fail --show-error --silent \
        "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | bash
fi
# shellcheck disable=SC1091
source "$NVM_DIR/nvm.sh"
nvm install 22
nvm use 22
nvm alias default 22

echo "[3/6] Creating the Python environment..."
python3 -m venv "$PROJECT_ROOT/.venv"
"$PROJECT_ROOT/.venv/bin/python" -m pip install --upgrade pip
"$PROJECT_ROOT/.venv/bin/python" -m pip install -r "$PROJECT_ROOT/backend/requirements.txt"

echo "[4/6] Installing Electron dependencies..."
(
    cd "$PROJECT_ROOT/frontend"
    npm ci
)

echo "[5/6] Configuring Electron's SUID sandbox..."
SANDBOX="$PROJECT_ROOT/frontend/node_modules/electron/dist/chrome-sandbox"
sudo chown root:root "$SANDBOX"
sudo chmod 4755 "$SANDBOX"

echo "[6/6] Initializing and checking AegisOS..."
(
    cd "$PROJECT_ROOT"
    .venv/bin/python -m database.init_db
    .venv/bin/python -m pytest
)
(
    cd "$PROJECT_ROOT/frontend"
    npm run check
)

python3 --version
git --version
node --version
npm --version
sqlite3 --version
ls -l "$SANDBOX"

if command -v code >/dev/null 2>&1; then
    code --version | head -n 1
else
    echo "VS Code is not installed. Install it before testing the Open VS Code action."
fi

echo "AegisOS runtime setup completed. Next run: desktop/setup-desktop.sh"
