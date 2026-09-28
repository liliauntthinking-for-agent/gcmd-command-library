#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/gcmd.app"

SWIFT_BIN="${SWIFT_BIN:-$(xcrun --find swift 2>/dev/null || command -v swift || true)}"
if [[ -z "$SWIFT_BIN" || ! -x "$SWIFT_BIN" ]]; then
    echo "gcmd: Swift was not found." >&2
    echo "Install Xcode or Command Line Tools, then retry." >&2
    exit 1
fi

DEVELOPER_DIR_PATH="$(xcode-select --print-path 2>/dev/null || true)"
echo "Using Swift: $SWIFT_BIN"
echo "Developer directory: ${DEVELOPER_DIR_PATH:-unknown}"

cd "$ROOT/mac-app"
if ! "$SWIFT_BIN" build -c release; then
    echo >&2
    echo "gcmd: Swift Package Manager failed while loading Package.swift." >&2
    echo "If the error mentions 'Invalid manifest' or 'PackageDescription'," >&2
    echo "select a matching Xcode toolchain or reinstall Command Line Tools:" >&2
    echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2
    echo "  xcode-select --install" >&2
    echo "Then retry: ./mac-app/build-app.sh" >&2
    exit 1
fi

BIN="$("$SWIFT_BIN" build -c release --show-bin-path)/gcmd-app"
CLI_BIN="$("$SWIFT_BIN" build -c release --show-bin-path)/gcmd"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/gcmd-app"
cp "$ROOT/mac-app/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$ROOT/build"
cp "$CLI_BIN" "$ROOT/build/gcmd"

echo "Built $APP and $ROOT/build/gcmd"
