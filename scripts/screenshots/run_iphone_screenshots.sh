#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
SCHEME="SonicPlayer"
BUNDLE_ID="com.hasan.sonicplayer"
# **Chosen for its native resolution, not its recency.** 1320x2868 is Apple's 6.9" size, so a
# capture here needs no resize — see the note where the resize step used to be. The previous
# default, iPhone 16 Pro Max, is also 1320x2868 but is not installed with Xcode 27.
DEVICE="${DEVICE:-iPhone 17 Pro Max}"
OUT_DIR="$PROJECT_DIR/artifacts/screenshots/iphone"
DELAY="${SCREENSHOT_DELAY:-3}"

echo "=== SonicPlayer iPhone Screenshot Pipeline ==="
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

    # Wait for UI to render
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
# Dial routes, which is what the app has. `collections`, `editRecording` and
# `homeWithMiniPlayer` named screens that stopped being reachable — they kept producing images,
# of the dial, under the wrong filenames. `home` has now gone the same way: it named the
# Listen-or-Record fork, and the library became the root.
capture "library"           "01_library.png"
capture "player"            "02_player.png"             1
capture "recording"         "03_recording.png"          1
capture "edit"              "04_edit.png"               1
capture "settings"          "05_settings.png"

# Terminate the app
xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true

# **There is no resize step, and its absence is the point.**
#
# This ended with `sips -z 2688 1242 "$img" --out "$img"`, which had three faults at once: it wrote
# to the path it read, so the only copy was overwritten with no way back; 1242x2688 is the 6.5"
# size, which stopped being Apple's primary; and `-z` forces exact dimensions, so every image was
# stretched by the 0.4% its aspect ratio differed.
#
# The fix is not a better resize. $DEVICE is natively 1320x2868 — the 6.9" size — so a capture is
# already an accepted asset and post-processing it can only make it worse. If the required size
# ever changes, change the DEVICE, not the arithmetic.
echo ""
echo "=== iPhone screenshots complete ==="
echo "Screenshots saved to: $OUT_DIR ($(sips -g pixelWidth -g pixelHeight "$OUT_DIR/01_library.png" | awk '/pixel/{printf "%s ", $2}')native, $DEVICE)"
ls -la "$OUT_DIR"

# Cleanup
"$SCRIPT_DIR/cleanup_simulators.sh"
