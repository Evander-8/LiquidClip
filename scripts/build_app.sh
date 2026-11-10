#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Building LiquidClip for macOS..."
cd "${PROJECT_DIR}"

APP_NAME="LiquidClip"
DIST_DIR="${PROJECT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# 1. Clean previous build
rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 2. Compile optimized release binary
echo "==> Compiling Swift sources..."
mkdir -p /tmp/cache
SWIFT_SOURCES=$(find Sources/LiquidClip -name "*.swift")

swiftc -O \
    -module-cache-path /tmp/cache \
    -parse-as-library \
    -target arm64-apple-macos14.0 \
    ${SWIFT_SOURCES} \
    -o "${MACOS_DIR}/${APP_NAME}"

# 3. Copy Resources & Info.plist
echo "==> Packaging App Bundle..."
cp Resources/Info.plist "${CONTENTS_DIR}/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "${RESOURCES_DIR}/AppIcon.icns"
fi

# 4. Ad-hoc codesign
echo "==> Signing App Bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

echo "==> Build successful! App bundle created at:"
echo "    ${APP_BUNDLE}"
echo ""
echo "To run the app:"
echo "    open \"${APP_BUNDLE}\""
echo ""
