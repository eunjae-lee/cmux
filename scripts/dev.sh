#!/usr/bin/env bash
# Quick shortcut to build and launch the dev app.
# Usage:
#   ./scripts/dev.sh              # build & launch with default tag "dev"
#   ./scripts/dev.sh my-feature   # build & launch with custom tag
set -euo pipefail

TAG="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/reload.sh" --tag "$TAG" --launch
