#!/bin/bash
set -euo pipefail

# Boot a specific simulator device
# Usage: ./boot_simulator.sh "iPhone 16 Pro Max"

DEVICE="${1:-iPhone 16 Pro Max}"

echo "Booting simulator: $DEVICE"

# Check if the device exists
if ! xcrun simctl list devices available | grep -q "$DEVICE"; then
    echo "Error: Device '$DEVICE' not found. Available devices:"
    xcrun simctl list devices available | grep -E "iPhone|iPad"
    exit 1
fi

# Shutdown all running simulators first
xcrun simctl shutdown all 2>/dev/null || true

# Boot the target device
xcrun simctl boot "$DEVICE" 2>/dev/null || true

# Open Simulator app
open -a Simulator

# Wait for simulator to be ready
echo "Waiting for simulator to boot..."
sleep 3

# Set clean status bar (iOS 16+)
xcrun simctl status_bar "$DEVICE" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --cellularMode active \
    --cellularBars 4 \
    --wifiBars 3 \
    --operatorName "" 2>/dev/null || true

echo "Simulator '$DEVICE' is ready."
