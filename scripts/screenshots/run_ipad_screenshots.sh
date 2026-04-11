#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
SCHEME="SonicPlayer"
BUNDLE_ID="com.hasan.sonicplayer"
DEVICE="${DEVICE:-iPad Pro 13-inch (M4)}"
OUT_DIR="$PROJECT_DIR/artifacts/screenshots/ipad"
DELAY="${SCREENSHOT_DELAY:-4}"

echo "=== SonicPlayer iPad Screenshot Pipeline ==="
echo "Scheme:  $SCHEME"
echo "Device:  $DEVICE"
echo "Output:  $OUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUT_DIR"

# Step 1: Boot simulator
echo "[1/4] Booting simulator..."
"$SCRIPT_DIR/boot_simulator.sh" "$DEVICE"

# Step 2: Build the app
echo ""
echo "[2/4] Building app..."
cd "$PROJECT_DIR"
xcodebuild \
    -project SonicPlayer.xcodeproj \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -configuration Debug \
    build 2>&1 | tail -3

# Find the built .app
APP_PATH=$(xcodebuild \
    -project SonicPlayer.xcodeproj \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -showBuildSettings 2>/dev/null | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
APP_PATH="$APP_PATH/$SCHEME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Built app not found at $APP_PATH"
    exit 1
fi

# Step 3: Install the app
echo ""
echo "[3/4] Installing app..."
xcrun simctl install booted "$APP_PATH"

# Grant microphone permission for recording screenshot
echo "Granting microphone permission..."
xcrun simctl privacy booted grant microphone "$BUNDLE_ID" 2>/dev/null || true

# Step 4: Capture screenshots
echo ""
echo "[4/4] Capturing screenshots..."

capture() {
    local screen="$1"
    local file="$2"
    local extra_delay="${3:-0}"

    echo "  Capturing: $screen -> $file"

    # Terminate any running instance
    xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true
    sleep 1

    # Launch with screenshot arguments
    xcrun simctl launch booted "$BUNDLE_ID" \
        -screenshotMode YES \
        -screenshotScreen "$screen" \
        -screenshotUseDemoData YES

    # Wait for UI to render (iPad needs a bit more time)
    sleep "$DELAY"

    # Additional delay for complex screens
    if [ "$extra_delay" -gt 0 ]; then
        sleep "$extra_delay"
    fi

    # Capture
    xcrun simctl io booted screenshot "$OUT_DIR/$file"
    echo "  Done: $file"
}

# Screenshot sequence
capture "home"              "ipad_01_home.png"
capture "collections"       "ipad_02_collections.png"
capture "player"            "ipad_03_player.png"             1
capture "recording"         "ipad_04_recording.png"          1
capture "homeWithMiniPlayer" "ipad_05_home_mini_player.png"

# Terminate the app
xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true

echo ""
echo "=== iPad screenshots complete ==="
echo "Screenshots saved to: $OUT_DIR"
ls -la "$OUT_DIR"

# Cleanup
"$SCRIPT_DIR/cleanup_simulators.sh"
