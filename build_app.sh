#!/bin/bash
set -e

APP_NAME="SnapPin"
BUILD_DIR="/Users/jiahaochen/Downloads/SnapPin"
APP_DIR="/Users/jiahaochen/Downloads/${APP_NAME}.app"

# Remove old app bundle if exists
if [ -d "$APP_DIR" ]; then
    rm -rf "$APP_DIR"
fi

# Create app bundle structure
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy executable

# Copy icon
cp "/Users/jiahaochen/Downloads/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
cp "${BUILD_DIR}/.build/debug/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Create Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SnapPin</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.snappin.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SnapPin</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>4</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>SnapPin needs screen recording permission to capture screenshots.</string>
</dict>
</plist>
PLIST

# Create entitlements file
cat > "/tmp/SnapPin.entitlements" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
ENTITLEMENTS

# Ad-hoc code sign with entitlements
codesign --force --deep --sign - --entitlements /tmp/SnapPin.entitlements "${APP_DIR}" 2>&1

echo "App bundle created and signed at: ${APP_DIR}"
echo "You can now run it with: open ${APP_DIR}"
