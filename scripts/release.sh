#!/usr/bin/env bash
#
# Builds a universal NTS.app and packs it into a disk image with an Applications shortcut,
# ready to attach to a GitHub release.
#
# Usage: scripts/release.sh 1.0.0
# Output: ./build/NTS.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:?usage: scripts/release.sh <version>}"
DMG="$ROOT/build/NTS.dmg"

VERSION="$VERSION" UNIVERSAL=1 bash scripts/build-app.sh

echo "==> Packing $(basename "$DMG")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto build/NTS.app "$STAGE/NTS.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "NTS" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> Done: $DMG"
