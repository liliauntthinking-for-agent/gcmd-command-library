#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/gcmd.app"
CLI="$ROOT/build/gcmd"
STAGE="$ROOT/build/gcmd-macos-universal"
ZIP="$ROOT/build/gcmd-macos-universal.zip"
MINIMUM_MACOS="13.0"

SWIFTC_BIN="${SWIFTC_BIN:-$(xcrun --find swiftc 2>/dev/null || command -v swiftc || true)}"
LIPO_BIN="${LIPO_BIN:-$(xcrun --find lipo 2>/dev/null || command -v lipo || true)}"
if [[ -z "$SWIFTC_BIN" || ! -x "$SWIFTC_BIN" ]]; then
    echo "gcmd: swiftc was not found." >&2
    echo "Install Xcode or Command Line Tools, then retry." >&2
    exit 1
fi
if [[ -z "$LIPO_BIN" || ! -x "$LIPO_BIN" ]]; then
    echo "gcmd: lipo was not found." >&2
    exit 1
fi

DEVELOPER_DIR_PATH="$(xcode-select --print-path 2>/dev/null || true)"
SDK_PATH="${SDK_PATH:-$(xcrun --show-sdk-path 2>/dev/null || true)}"
if [[ -z "$SDK_PATH" || ! -d "$SDK_PATH" ]]; then
    echo "gcmd: macOS SDK was not found." >&2
    exit 1
fi
echo "Using swiftc: $SWIFTC_BIN"
echo "Developer directory: ${DEVELOPER_DIR_PATH:-unknown}"
echo "SDK: $SDK_PATH"

CORE_SOURCE="$ROOT/mac-app/Sources/GcmdCore/GcmdCore.swift"
APP_SOURCE="$ROOT/mac-app/Sources/GcmdApp/main.swift"
CLI_SOURCE="$ROOT/mac-app/Sources/GcmdCLI/main.swift"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

compile_core_module() {
    local architecture="$1"
    local output_directory="$BUILD_DIR/$architecture"

    "$SWIFTC_BIN" \
        -sdk "$SDK_PATH" \
        -O \
        -target "${architecture}-apple-macos${MINIMUM_MACOS}" \
        -module-name GcmdCore \
        -emit-module \
        -emit-module-path "$output_directory/GcmdCore.swiftmodule" \
        -parse-as-library \
        -c \
        -o "$output_directory/GcmdCore.o" \
        "$CORE_SOURCE"
}

compile_binary() {
    local architecture="$1"
    local output="$2"
    local is_application="$3"
    shift 3
    local output_directory="$BUILD_DIR/$architecture"

    local -a arguments=(
        -sdk "$SDK_PATH"
        -O
        -target "${architecture}-apple-macos${MINIMUM_MACOS}"
        -I "$output_directory"
        "$output_directory/GcmdCore.o"
        -o "$output"
    )
    if [[ "$is_application" == "true" ]]; then
        arguments+=(-parse-as-library)
    fi
    "$SWIFTC_BIN" "${arguments[@]}" "$@"
}

rm -rf "$APP" "$STAGE" "$ZIP"
mkdir -p \
    "$APP/Contents/MacOS" \
    "$APP/Contents/Resources" \
    "$BUILD_DIR/arm64" \
    "$BUILD_DIR/x86_64" \
    "$STAGE"

for architecture in arm64 x86_64; do
    echo "Compiling GcmdCore ($architecture)..."
    compile_core_module "$architecture"

    echo "Compiling gcmd-app ($architecture)..."
    compile_binary "$architecture" "$BUILD_DIR/$architecture/gcmd-app" true \
        "$APP_SOURCE"

    echo "Compiling gcmd CLI ($architecture)..."
    compile_binary "$architecture" "$BUILD_DIR/$architecture/gcmd" false \
        "$CLI_SOURCE"
done

"$LIPO_BIN" -create \
    "$BUILD_DIR/arm64/gcmd-app" "$BUILD_DIR/x86_64/gcmd-app" \
    -output "$APP/Contents/MacOS/gcmd-app"
"$LIPO_BIN" -create \
    "$BUILD_DIR/arm64/gcmd" "$BUILD_DIR/x86_64/gcmd" \
    -output "$STAGE/gcmd"
cp "$STAGE/gcmd" "$CLI"

cp "$ROOT/mac-app/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
codesign --force --sign - "$STAGE/gcmd" >/dev/null 2>&1 || true
cp -R "$APP" "$STAGE/gcmd.app"
cp "$ROOT/gcmd/shell/gcmd.zsh" "$STAGE/gcmd.zsh"

cat > "$STAGE/README.txt" <<'EOF'
gcmd macOS universal build

This package contains:

- gcmd.app: the on-demand macOS popup app
- gcmd: the CLI launcher used by zsh shortcuts
- gcmd.zsh: the shell integration for Ctrl-G and Ctrl-X

Keep these files in one folder. Add that folder to PATH and source gcmd.zsh:

    export PATH="/path/to/gcmd-macos-universal:$PATH"
    source "/path/to/gcmd-macos-universal/gcmd.zsh"

Requires macOS 13 or newer. The executables support Apple Silicon and Intel.
EOF

ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIP"

echo "Built $APP"
echo "Built $CLI"
echo "Built $STAGE"
echo "Packaged $ZIP"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/gcmd-app")"
