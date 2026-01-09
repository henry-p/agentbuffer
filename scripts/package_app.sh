#!/bin/sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/AgentBuffer.app"
INFO_PLIST="$ROOT_DIR/Packaging/Info.plist"
SKIP_BUILD="false"

for arg in "$@"; do
    case "$arg" in
        --skip-build)
            SKIP_BUILD="true"
            ;;
        *)
            ;;
    esac
done

if [ "$SKIP_BUILD" != "true" ]; then
    swift build -c release
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/AgentBuffer" "$APP_DIR/Contents/MacOS/AgentBuffer"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

if [ -d "$BUILD_DIR/AgentBuffer_AgentBuffer.bundle" ]; then
    cp -R "$BUILD_DIR/AgentBuffer_AgentBuffer.bundle" "$APP_DIR/Contents/Resources/"
fi

codesign --force --deep --sign - "$APP_DIR"
