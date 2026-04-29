#!/bin/bash
#
# build-dmg.sh
# Repository-root entrypoint for the canonical signed/notarized DMG builder.
#
# Usage: ./Scripts/build-dmg.sh [--skip-build] [--skip-notarize] [--open]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CANONICAL_SCRIPT="${PROJECT_DIR}/ClaudeGlance/Scripts/build-dmg.sh"

if [ ! -f "$CANONICAL_SCRIPT" ]; then
    echo "Error: canonical DMG builder not found: $CANONICAL_SCRIPT" >&2
    exit 1
fi

exec bash "$CANONICAL_SCRIPT" "$@"
