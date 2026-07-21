#!/bin/bash
# Zip the built app into a Releases artifact (Calendar.app.zip).
# Run ./build_app.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Calendar"
APP="$ROOT/dist/$APP_NAME.app"
ZIP="$ROOT/dist/Calendar.app.zip"

[ -d "$APP" ] || { echo "!! $APP not found — run ./build_app.sh first"; exit 1; }

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Built: $ZIP"
ls -lh "$ZIP" | awk '{print $5, $9}'
