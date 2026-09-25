#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/gcmd.app"

cd "$ROOT/mac-app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/gcmd-app"
CLI_BIN="$(swift build -c release --show-bin-path)/gcmd"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/gcmd-app"
cp "$ROOT/mac-app/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$ROOT/build"
cp "$CLI_BIN" "$ROOT/build/gcmd"

echo "Built $APP and $ROOT/build/gcmd"
