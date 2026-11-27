#!/bin/bash
# Builds Disque.app into ./build
# Usage: scripts/build-app.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"

# The macOS 27 SDK implements @State as a macro whose plugin only ships with full Xcode.
# When building with the Command Line Tools, fall back to the newest macOS 26 SDK.
if [[ -z "${SDKROOT:-}" ]] && [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
  SDK_DIR="$(xcode-select -p)/SDKs"
  CANDIDATE="$(ls -d "$SDK_DIR"/MacOSX26.*.sdk "$SDK_DIR"/MacOSX26.sdk 2>/dev/null | sort -V | tail -n 1 || true)"
  if [[ -n "$CANDIDATE" ]]; then
    export SDKROOT="$CANDIDATE"
    echo "Using SDK: $SDKROOT"
  fi
fi

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Disque.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Disque" "$APP/Contents/MacOS/Disque"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
