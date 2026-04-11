#!/bin/bash
set -euo pipefail

# Shutdown all simulators and clean up
echo "Shutting down all simulators..."
xcrun simctl shutdown all 2>/dev/null || true

echo "All simulators shut down."
