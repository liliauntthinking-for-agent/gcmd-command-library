#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/gcmd.app"
CLI="$ROOT/build/gcmd"
MINIMUM_MACOS="13.0"
HOST_ARCHITECTURE="$(uname -m)"
ARCHITECTURE_CHOICE="${GCMD_ARCH:-current}"

usage() {
    cat <<'EOF'
Usage: ./mac-app/build-app.sh [--arch ARCHITECTURE]

Architectures:
  current    Build only for this Mac (default)
  arm64      Build an Apple Silicon package
  x86_64     Build an Intel package
  universal  Build one package containing both architectures
  all        Build arm64, x86_64, and universal packages

You can also use GCMD_ARCH=arm64 ./mac-app/build-app.sh.
EOF
}

while (($#)); do
    case "$1" in
        --arch|-a)
            [[ $# -ge 2 ]] || { echo "gcmd: --arch requires a value" >&2; usage >&2; exit 2; }
            ARCHITECTURE_CHOICE="$2"
            shift 2
            ;;
        --arch=*)
            ARCHITECTURE_CHOICE="${1#*=}"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "gcmd: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$ARCHITECTURE_CHOICE" in
    current|native)
        ARCHITECTURE_CHOICE="$HOST_ARCHITECTURE"
        ;;
esac

typeset -a actual_architectures package_architectures
universal_requested=false
case "$ARCHITECTURE_CHOICE" in
    arm64|x86_64)
        actual_architectures=("$ARCHITECTURE_CHOICE")
        package_architectures=("$ARCHITECTURE_CHOICE")
        ;;
    universal)
        actual_architectures=(arm64 x86_64)
        package_architectures=(universal)
        universal_requested=true
        ;;
    all)
        actual_architectures=(arm64 x86_64)
        package_architectures=(arm64 x86_64 universal)
        universal_requested=true
        ;;
    *)
        echo "gcmd: unknown architecture: $ARCHITECTURE_CHOICE" >&2
        usage >&2
        exit 2
        ;;
esac

SWIFTC_BIN="${SWIFTC_BIN:-$(xcrun --find swiftc 2>/dev/null || command -v swiftc || true)}"
if [[ -z "$SWIFTC_BIN" || ! -x "$SWIFTC_BIN" ]]; then
    echo "gcmd: swiftc was not found." >&2
    echo "Install Xcode or Command Line Tools, then retry." >&2
    exit 1
fi

LIPO_BIN="${LIPO_BIN:-$(xcrun --find lipo 2>/dev/null || command -v lipo || true)}"
if [[ "$universal_requested" == true && (-z "$LIPO_BIN" || ! -x "$LIPO_BIN") ]]; then
    echo "gcmd: lipo was not found." >&2
    exit 1
fi

DEVELOPER_DIR_PATH="$(xcode-select --print-path 2>/dev/null || true)"
SDK_PATH="${SDK_PATH:-$(xcrun --show-sdk-path 2>/dev/null || true)}"
if [[ -z "$SDK_PATH" || ! -d "$SDK_PATH" ]]; then
    echo "gcmd: macOS SDK was not found." >&2
    exit 1
fi

echo "Host architecture: $HOST_ARCHITECTURE"
echo "Build architecture: $ARCHITECTURE_CHOICE"
echo "Using swiftc: $SWIFTC_BIN"
echo "Developer directory: ${DEVELOPER_DIR_PATH:-unknown}"
echo "SDK: $SDK_PATH"

CORE_SOURCES=(
    "$ROOT/mac-app/Sources/GcmdCore/GcmdCore.swift"
    "$ROOT/mac-app/Sources/GcmdCore/SSHBridge.swift"
)
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
        -parse-as-library \
        -target "${architecture}-apple-macos${MINIMUM_MACOS}" \
        -module-name GcmdCore \
        -emit-module \
        -emit-module-path "$output_directory/GcmdCore.swiftmodule" \
        "${CORE_SOURCES[@]}"

    local core_source
    for core_source in "${CORE_SOURCES[@]}"; do
        "$SWIFTC_BIN" \
            -sdk "$SDK_PATH" \
            -O \
            -parse-as-library \
            -target "${architecture}-apple-macos${MINIMUM_MACOS}" \
            -module-name GcmdCore \
            -c \
            -o "$output_directory/$(basename "$core_source" .swift).o" \
            "$core_source"
    done
}

compile_binary() {
    local architecture="$1"
    local output="$2"
    local is_application="$3"
    shift 3
    local output_directory="$BUILD_DIR/$architecture"
    local -a core_objects=(
        "$output_directory/GcmdCore.o"
        "$output_directory/SSHBridge.o"
    )

    local -a arguments=(
        -sdk "$SDK_PATH"
        -O
        -target "${architecture}-apple-macos${MINIMUM_MACOS}"
        -I "$output_directory"
        "${core_objects[@]}"
        -o "$output"
    )
    if [[ "$is_application" == "true" ]]; then
        arguments+=(-parse-as-library)
    fi
    "$SWIFTC_BIN" "${arguments[@]}" "$@"
}

make_app_bundle() {
    local output="$1"
    local binary="$2"

    rm -rf "$output"
    mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources"
    cp "$binary" "$output/Contents/MacOS/gcmd-app"
    cp "$ROOT/mac-app/Info.plist" "$output/Contents/Info.plist"
    codesign --force --sign - "$output" >/dev/null 2>&1 || true
}

make_package() {
    local package_architecture="$1"
    local app_binary="$2"
    local cli_binary="$3"
    local stage="$ROOT/build/gcmd-macos-$package_architecture"
    local zip="$ROOT/build/gcmd-macos-$package_architecture.zip"
    local architecture_description

    case "$package_architecture" in
        universal) architecture_description="Apple Silicon and Intel" ;;
        *) architecture_description="$package_architecture" ;;
    esac

    rm -rf "$stage" "$zip"
    mkdir -p "$stage"
    make_app_bundle "$stage/gcmd.app" "$app_binary"
    cp "$cli_binary" "$stage/gcmd"
    chmod +x "$stage/gcmd"
    codesign --force --sign - "$stage/gcmd" >/dev/null 2>&1 || true
    cp "$ROOT/gcmd/shell/gcmd.zsh" "$stage/gcmd.zsh"

    cat > "$stage/README.txt" <<EOF
gcmd macOS build

This package contains:

- gcmd.app: the on-demand macOS popup app
- gcmd: the CLI launcher used by zsh shortcuts
- gcmd.zsh: the shell integration for Ctrl-G and Ctrl-X
- gcmd ssh DESTINATION: optional bridge for shortcuts during SSH sessions

Keep these files in one folder. Add that folder to PATH and source gcmd.zsh:

    export PATH="/path/to/gcmd-macos-$package_architecture:\$PATH"
    source "/path/to/gcmd-macos-$package_architecture/gcmd.zsh"

Requires macOS $MINIMUM_MACOS or newer. Architecture: $architecture_description.
EOF

    ditto -c -k --sequesterRsrc --keepParent "$stage" "$zip"
    echo "Packaged $zip"
}

rm -rf "$APP" "$CLI"
for package_architecture in "${package_architectures[@]}"; do
    rm -rf \
        "$ROOT/build/gcmd-macos-$package_architecture" \
        "$ROOT/build/gcmd-macos-$package_architecture.zip"
done

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for architecture in "${actual_architectures[@]}"; do
    mkdir -p "$BUILD_DIR/$architecture"
    echo "Compiling GcmdCore ($architecture)..."
    compile_core_module "$architecture"

    echo "Compiling gcmd-app ($architecture)..."
    compile_binary "$architecture" "$BUILD_DIR/$architecture/gcmd-app" true \
        "$APP_SOURCE"

    echo "Compiling gcmd CLI ($architecture)..."
    compile_binary "$architecture" "$BUILD_DIR/$architecture/gcmd" false \
        "$CLI_SOURCE"
done

if (( ${#actual_architectures[@]} == 1 )); then
    local_architecture="$actual_architectures[1]"
    make_app_bundle "$APP" "$BUILD_DIR/$local_architecture/gcmd-app"
    cp "$BUILD_DIR/$local_architecture/gcmd" "$CLI"
    chmod +x "$CLI"
    codesign --force --sign - "$CLI" >/dev/null 2>&1 || true
    local_architecture_description="$local_architecture"
else
    mkdir -p "$BUILD_DIR/universal"
    "$LIPO_BIN" -create \
        "$BUILD_DIR/arm64/gcmd-app" "$BUILD_DIR/x86_64/gcmd-app" \
        -output "$BUILD_DIR/universal/gcmd-app"
    "$LIPO_BIN" -create \
        "$BUILD_DIR/arm64/gcmd" "$BUILD_DIR/x86_64/gcmd" \
        -output "$BUILD_DIR/universal/gcmd"
    make_app_bundle "$APP" "$BUILD_DIR/universal/gcmd-app"
    cp "$BUILD_DIR/universal/gcmd" "$CLI"
    chmod +x "$CLI"
    codesign --force --sign - "$CLI" >/dev/null 2>&1 || true
    local_architecture_description="universal"
fi

for package_architecture in "${package_architectures[@]}"; do
    if [[ "$package_architecture" == universal ]]; then
        make_package universal \
            "$BUILD_DIR/universal/gcmd-app" \
            "$BUILD_DIR/universal/gcmd"
    else
        make_package "$package_architecture" \
            "$BUILD_DIR/$package_architecture/gcmd-app" \
            "$BUILD_DIR/$package_architecture/gcmd"
    fi
done

echo "Built $APP"
echo "Built $CLI"
echo "Architectures: $local_architecture_description"
