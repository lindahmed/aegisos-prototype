#!/bin/bash

echo "Starting AegisOS setup..."

sudo apt update
sudo apt upgrade -y

sudo apt install -y \
    git \
    curl \
    wget \
    build-essential \
    unzip \
    zip \
    python3 \
    python3-pip \
    python3-venv \
    sqlite3 \
    nodejs \
    npm

echo "Creating AegisOS project folders..."

mkdir -p ~/aegisos-prototype/backend
mkdir -p ~/aegisos-prototype/frontend
mkdir -p ~/aegisos-prototype/database
mkdir -p ~/aegisos-prototype/workspace
mkdir -p ~/aegisos-prototype/vm
mkdir -p ~/aegisos-prototype/desktop
mkdir -p ~/aegisos-prototype/docs

echo "Checking installed software..."

python3 --version
git --version
node --version
npm --version
sqlite3 --version

if command -v code >/dev/null 2>&1; then
    echo "VS Code is installed."
else
    echo "VS Code is NOT installed."
    echo "Install VS Code manually."
fi

echo "AegisOS base setup completed."
