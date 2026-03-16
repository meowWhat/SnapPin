#!/bin/bash
set -e

APP_NAME="SnapPin"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_TEMP="temp_dmg"
DMG_DIR="/Users/jiahaochen/Downloads"
APP_PATH="${DMG_DIR}/${APP_NAME}.app"

echo "=== Creating DMG for ${APP_NAME} v${VERSION} ==="

# Check app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: ${APP_PATH} not found"
    exit 1
fi

# Clean up
rm -rf "${DMG_DIR}/${DMG_TEMP}" "${DMG_DIR}/${DMG_NAME}"

# Create temp directory with app and Applications symlink
mkdir -p "${DMG_DIR}/${DMG_TEMP}"
cp -R "$APP_PATH" "${DMG_DIR}/${DMG_TEMP}/"
ln -s /Applications "${DMG_DIR}/${DMG_TEMP}/Applications"

# Create DMG using hdiutil
echo "Creating DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "${DMG_DIR}/${DMG_TEMP}" \
    -ov \
    -format UDZO \
    "${DMG_DIR}/${DMG_NAME}"

# Clean up temp
rm -rf "${DMG_DIR}/${DMG_TEMP}"

# Sign the DMG
codesign -s - "${DMG_DIR}/${DMG_NAME}" 2>/dev/null || true

echo ""
echo "=== DMG created successfully ==="
echo "Location: ${DMG_DIR}/${DMG_NAME}"
ls -lh "${DMG_DIR}/${DMG_NAME}"
