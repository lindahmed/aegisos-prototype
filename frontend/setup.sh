#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "frontend/setup.sh now delegates to the complete runtime setup."
exec "$PROJECT_ROOT/vm/setup.sh" "$@"
