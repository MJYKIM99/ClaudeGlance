#!/bin/bash
#
# build-dmg.sh
# Claude Glance DMG Builder (with code signing + notarization)
#
# 用法: ./Scripts/build-dmg.sh [--skip-build] [--skip-notarize] [--open]
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
APP_NAME="ClaudeGlance"
SCHEME="ClaudeGlance"
BUILD_DIR="build"
DMG_NAME="${APP_NAME}.dmg"
VOLUME_NAME="Claude Glance"
SIGN_IDENTITY="Developer ID Application: Shanghai TacticSpace Technology Co., Ltd. (2Z66884GZ3)"
TEAM_ID="2Z66884GZ3"
NOTARY_PROFILE="claudebench-notary"

# 获取脚本所在目录的父目录的父目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_DIR"

# 参数解析
SKIP_BUILD=false
SKIP_NOTARIZE=false
OPEN_DMG=false

for arg in "$@"; do
    case $arg in
        --skip-build)
            SKIP_BUILD=true
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            ;;
        --open)
            OPEN_DMG=true
            ;;
        --help|-h)
            echo "Usage: $0 [--skip-build] [--skip-notarize] [--open]"
            echo ""
            echo "Options:"
            echo "  --skip-build      Skip the build step, use existing build"
            echo "  --skip-notarize   Skip notarization (for local testing)"
            echo "  --open            Open the DMG after creation"
            exit 0
            ;;
    esac
done

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Claude Glance DMG Builder          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Step 1: 清理旧的构建
echo -e "${YELLOW}[1/7]${NC} Cleaning previous builds..."
rm -rf "$BUILD_DIR"
rm -f "$DMG_NAME"
rm -f "${APP_NAME}-temp.dmg"

# Step 2: 编译 Release 版本（带签名）
if [ "$SKIP_BUILD" = false ]; then
    echo -e "${YELLOW}[2/7]${NC} Building Release version with code signing..."
    xcodebuild -scheme "$SCHEME" \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -derivedDataPath "$BUILD_DIR" \
        -quiet \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGNING_REQUIRED=YES \
        OTHER_CODE_SIGN_FLAGS="--options runtime --timestamp"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Build failed!${NC}"
        exit 1
    fi
    echo -e "${GREEN}Build successful!${NC}"
else
    echo -e "${YELLOW}[2/7]${NC} Skipping build (--skip-build)..."
fi

# 检查 .app 是否存在
APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: ${APP_PATH} not found!${NC}"
    echo "Please run without --skip-build first."
    exit 1
fi

# Step 3: 重新签名（使用 Release entitlements，剥离 get-task-allow）
echo -e "${YELLOW}[3/7]${NC} Re-signing with release entitlements..."
ENTITLEMENTS="${PROJECT_DIR}/ClaudeGlance/ClaudeGlance.entitlements"

codesign --force --deep --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH" 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Code signature valid!${NC}"
    codesign -dvv "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Signature"
else
    echo -e "${RED}Code signature verification failed!${NC}"
    exit 1
fi

# Step 4: 创建 DMG
echo -e "${YELLOW}[4/7]${NC} Preparing DMG contents..."
DMG_TEMP_DIR="$BUILD_DIR/dmg-temp"
mkdir -p "$DMG_TEMP_DIR"
cp -R "$APP_PATH" "$DMG_TEMP_DIR/"
ln -sf /Applications "$DMG_TEMP_DIR/Applications"

echo -e "${YELLOW}[5/7]${NC} Creating DMG..."

if command -v create-dmg &> /dev/null; then
    echo "Using create-dmg..."
    create-dmg \
        --volname "$VOLUME_NAME" \
        --volicon "${PROJECT_DIR}/VolumeIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 150 190 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 450 190 \
        --no-internet-enable \
        "$DMG_NAME" \
        "$DMG_TEMP_DIR" \
        2>/dev/null || true

    if [ ! -f "$DMG_NAME" ]; then
        echo "create-dmg failed, falling back to hdiutil..."
        hdiutil create -volname "$VOLUME_NAME" \
            -srcfolder "$DMG_TEMP_DIR" \
            -ov -format UDZO \
            "$DMG_NAME"
    fi
else
    echo -e "${YELLOW}Note: Install create-dmg for prettier DMG: brew install create-dmg${NC}"
    hdiutil create -volname "$VOLUME_NAME" \
        -srcfolder "$DMG_TEMP_DIR" \
        -ov -format UDZO \
        "$DMG_NAME"
fi

rm -rf "$DMG_TEMP_DIR"

# Step 6: 签名 DMG
echo -e "${YELLOW}[6/7]${NC} Signing DMG..."
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_NAME"
echo -e "${GREEN}DMG signed!${NC}"

# Step 7: 公证
if [ "$SKIP_NOTARIZE" = false ]; then
    echo -e "${YELLOW}[7/7]${NC} Submitting for notarization..."
    echo "This may take a few minutes..."

    NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_NAME" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait 2>&1)
    echo "$NOTARY_OUTPUT"

    if echo "$NOTARY_OUTPUT" | grep -q "status: Accepted"; then
        echo -e "${GREEN}Notarization accepted!${NC}"

        echo "Stapling notarization ticket..."
        xcrun stapler staple "$DMG_NAME"
        echo -e "${GREEN}Stapled!${NC}"
    else
        echo -e "${RED}Notarization failed!${NC}"
        SUBMISSION_ID=$(echo "$NOTARY_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')
        if [ -n "$SUBMISSION_ID" ]; then
            echo "Fetching log..."
            xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" 2>&1
        fi
        exit 1
    fi
else
    echo -e "${YELLOW}[7/7]${NC} Skipping notarization (--skip-notarize)..."
fi

# 完成
if [ -f "$DMG_NAME" ]; then
    DMG_SIZE=$(du -h "$DMG_NAME" | cut -f1)
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Build Complete!              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  📦 DMG: ${BLUE}${DMG_NAME}${NC}"
    echo -e "  📏 Size: ${DMG_SIZE}"
    echo -e "  📍 Path: ${PROJECT_DIR}/${DMG_NAME}"
    echo -e "  ✅ Signed: ${SIGN_IDENTITY}"
    [ "$SKIP_NOTARIZE" = false ] && echo -e "  ✅ Notarized and stapled"
    echo ""

    if [ "$OPEN_DMG" = true ]; then
        echo "Opening DMG..."
        open "$DMG_NAME"
    fi
else
    echo -e "${RED}Failed to create DMG!${NC}"
    exit 1
fi
