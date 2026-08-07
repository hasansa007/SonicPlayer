#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/SonicPlayer.xcodeproj"
SCHEME="SonicPlayer"
ARCHIVE_PATH="/tmp/SonicPlayer.xcarchive"
EXPORT_PATH="/tmp/SonicPlayerExport"
EXPORT_OPTIONS="/tmp/ExportOptions.plist"

# Read version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/SonicPlayer/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PROJECT_DIR/SonicPlayer/Info.plist")

echo "========================================="
echo "  SonicPlayer — Distribute to TestFlight"
echo "  Version: $VERSION ($BUILD)"
echo "========================================="
echo ""

# Clean previous artifacts
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

# Archive
echo "→ Archiving..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -configuration Release \
  -skipMacroValidation \
  -allowProvisioningUpdates \
  -quiet

echo "✓ Archive succeeded"

# Write ExportOptions
cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>uploadSymbols</key>
  <true/>
  <key>destination</key>
  <string>upload</string>
</dict>
</plist>
EOF

# Export and upload
echo "→ Uploading to TestFlight..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  -quiet

echo ""
echo "========================================="
echo "  ✓ Uploaded v$VERSION ($BUILD) to TestFlight"
echo "========================================="
