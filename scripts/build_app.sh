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

# 5. Build DMG Package (if --dmg flag provided)
if [ "$1" == "--dmg" ]; then
    echo "==> Packaging DMG installer..."
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || echo "1.0.1")
    DMG_PATH="${DIST_DIR}/${APP_NAME}-v${VERSION}.dmg"
    STAGING="/tmp/${APP_NAME}_dmg_staging"
    rm -rf "${STAGING}"
    mkdir -p "${STAGING}"
    cp -R "${APP_BUNDLE}" "${STAGING}/"
    ln -s /Applications "${STAGING}/Applications"

    # Add quick-unlock helper for Gatekeeper quarantine
    cat << 'EOF' > "${STAGING}/打不开点我 (解除系统安全拦截).command"
#!/bin/bash
clear
echo "==============================================="
echo "   LiquidClip macOS 首次打开安全授权工具"
echo "==============================================="
echo ""
TARGET="/Applications/LiquidClip.app"
if [ ! -d "$TARGET" ]; then
    echo "⚠️ 未在「应用程序」目录中找到 LiquidClip.app。"
    echo "👉 请先将本安装包窗口中的 LiquidClip 拖入 Applications 文件夹！"
    echo ""
    read -p "按回车键退出..."
    exit 1
fi

echo "正在解除 macOS Gatekeeper 安全隔离限制..."
xattr -cr "$TARGET" 2>/dev/null || true
echo "✅ 成功解除安全拦截！"
echo "🚀 正在启动 LiquidClip..."
open "$TARGET"
exit 0
EOF
    chmod +x "${STAGING}/打不开点我 (解除系统安全拦截).command"

    hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING}" -ov -format UDZO "${DMG_PATH}"
    rm -rf "${STAGING}"
    echo "==> DMG installer created at: ${DMG_PATH}"
fi

echo "==> Build successful! App bundle created at:"
echo "    ${APP_BUNDLE}"
echo ""
echo "To run the app:"
echo "    open \"${APP_BUNDLE}\""
echo ""
