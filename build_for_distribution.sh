#!/bin/bash

# Exit on error
set -e

# Configuration
APP_NAME="Review"
SCHEME_NAME="Review"
WORKSPACE_PATH="Review.xcodeproj"
ARCHIVE_PATH="./build/${APP_NAME}.xcarchive"
EXPORT_PATH="./build/Export"
EXPORT_OPTIONS_PATH="./Review/ExportOptions.plist"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
NOTARIZE_EMAIL="slyfoxalpha@gmail.com"  # Your Apple ID email
BUNDLE_ID="com.foxycorps.Review"
DMG_PATH="./build/${APP_NAME}.dmg"

# Check for required environment variables
if [ -z "${APP_SPECIFIC_PASSWORD}" ]; then
  echo "❌ Error: APP_SPECIFIC_PASSWORD environment variable is not set!"
  echo "Please set this environment variable before running the script:"
  echo "export APP_SPECIFIC_PASSWORD='your-app-specific-password'"
  exit 1
fi

# Create build directory if it doesn't exist
mkdir -p ./build

echo "🚀 Building ${APP_NAME}..."

# Clean build folder
if [ -d "${EXPORT_PATH}" ]; then
    rm -rf "${EXPORT_PATH}"
fi

# Archive project
echo "📦 Archiving project..."
xcodebuild archive \
    -project "${WORKSPACE_PATH}" \
    -scheme "${SCHEME_NAME}" \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="43TJNHX42U" \
    CODE_SIGN_STYLE=Manual \
    PROVISIONING_PROFILE_SPECIFIER="Review Developer ID"

# Export archive
echo "📤 Exporting archive..."
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PATH}"

# Create a temporary file for the notarization password
NOTARIZE_PWD_FILE=$(mktemp)
echo "${APP_SPECIFIC_PASSWORD}" > "${NOTARIZE_PWD_FILE}"

# Notarize the app
echo "🔏 Notarizing ${APP_NAME}.app..."
xcrun notarytool submit "${APP_PATH}" \
    --apple-id "${NOTARIZE_EMAIL}" \
    --password "${NOTARIZE_PWD_FILE}" \
    --team-id "43TJNHX42U" \
    --wait

# Clean up the password file
rm "${NOTARIZE_PWD_FILE}"

# Staple the notarization ticket
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "${APP_PATH}"

# Create a DMG for distribution
echo "📀 Creating DMG for distribution..."
if [ -f "${DMG_PATH}" ]; then
    rm "${DMG_PATH}"
fi

# Create a temporary directory for the DMG contents
DMG_TEMP_DIR=$(mktemp -d)
cp -R "${APP_PATH}" "${DMG_TEMP_DIR}"

# Create a symlink to Applications folder for easy drag-and-drop installation
ln -s /Applications "${DMG_TEMP_DIR}"

hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_TEMP_DIR}" -ov -format UDZO "${DMG_PATH}"

# Clean up
rm -rf "${DMG_TEMP_DIR}"

echo "✅ Distribution build completed successfully!"
echo "📍 Your app is available at: ${APP_PATH}"
echo "📀 Your DMG installer is available at: ${DMG_PATH}"
echo ""
echo "To distribute the app to company devices, you can:"
echo "1. Share the DMG file directly with users"
echo "2. Upload the DMG to your company's MDM system"
echo "3. Host the DMG on an internal server for download" 