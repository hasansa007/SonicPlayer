#!/bin/bash
# run.sh — build SonicPlayer and launch it on a simulator, in one command.
#
# The three-step xcodebuild → simctl install → simctl launch dance is easy to get subtly wrong,
# and the wrong version does not error, it succeeds against the wrong device. This machine has two
# simulators sharing the name "iPhone 17 Pro" (iOS 26.5 and 27.0), so `name=iPhone 17 Pro` is
# ambiguous and so is `simctl … booted`. This script resolves exactly one UDID and hands the same
# one to all three commands.
#
#   ./scripts/run.sh                      # newest booted iPhone, else the newest available one
#   ./scripts/run.sh "iPhone 17 Pro Max"  # by name — newest runtime wins when the name repeats
#   ./scripts/run.sh <UDID>               # exactly that device
#   ./scripts/run.sh --shot               # also write and open a screenshot after launching
#   ./scripts/run.sh --release            # Release configuration instead of Debug
#
# Zero dependencies, like the rest of the repo (#20) — bash, xcrun, and the python3 that ships with
# macOS. python3 reads `simctl list -j` rather than grepping the text listing, because picking the
# newest runtime out of that listing by eye is the ambiguity this script exists to remove.
#
# Builds into the shared DerivedData, deliberately: the point is that a run here and a run from
# Xcode.app reuse each other's incremental build rather than each keeping their own copy.
#
# Exit 0 = app launched. Exit 1 = build, install or launch failed. Exit 2 = could not resolve the
# toolchain, the scheme, or a device.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

CONFIGURATION="Debug"
WANT_SHOT=false
DEVICE_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shot)     WANT_SHOT=true ;;
    --release)  CONFIGURATION="Release" ;;
    --debug)    CONFIGURATION="Debug" ;;
    -h|--help)  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    -*)         echo "run.sh: unknown flag $1" >&2; exit 2 ;;
    *)          DEVICE_ARG="$1" ;;
  esac
  shift
done

# --- Toolchain -------------------------------------------------------------------------------
# `xcode-select -p` pointing at Command Line Tools ships no simctl, and every step below then dies
# with "unable to find utility simctl" — which reads like "no simulators" on a machine that has
# plenty. DEVELOPER_DIR fixes this run without sudo and without changing global state.
if ! xcrun simctl help >/dev/null 2>&1; then
  for candidate in /Applications/Xcode*.app; do
    if [[ -x "$candidate/Contents/Developer/usr/bin/simctl" ]]; then
      export DEVELOPER_DIR="$candidate/Contents/Developer"
      break
    fi
  done
fi
if ! xcrun simctl help >/dev/null 2>&1; then
  echo "run.sh: no usable Xcode toolchain." >&2
  echo "  xcode-select -p: $(xcode-select -p 2>/dev/null)" >&2
  echo "  searched:        /Applications/Xcode*.app/Contents/Developer/usr/bin/simctl" >&2
  exit 2
fi
DEVELOPER_ROOT="${DEVELOPER_DIR:-$(xcode-select -p)}"

# --- Project and scheme ----------------------------------------------------------------------
PROJECT="$(ls -d ./*.xcodeproj 2>/dev/null | head -1)"
if [[ -z "$PROJECT" ]]; then
  echo "run.sh: no .xcodeproj in $(pwd)." >&2
  exit 2
fi

SCHEME=""
ALL_SCHEMES=""
SCHEME_COUNT=0
while IFS= read -r candidate; do
  [[ -z "$candidate" ]] && continue
  SCHEME_COUNT=$((SCHEME_COUNT + 1))
  [[ -z "$SCHEME" ]] && SCHEME="$candidate"
  ALL_SCHEMES="${ALL_SCHEMES:+$ALL_SCHEMES, }$candidate"
done < <(xcodebuild -list -json -project "$PROJECT" 2>/dev/null | python3 -c '
import json, sys
try:
    schemes = json.load(sys.stdin)["project"]["schemes"]
except Exception:
    sys.exit(0)
for s in schemes:
    if s.endswith(("Tests", "UITests")):
        continue
    print(s)
')

if [[ "$SCHEME_COUNT" -eq 0 ]]; then
  # Say "no SHARED schemes", never "no schemes": unshared ones live in xcuserdata/, which is
  # gitignored, so a fresh clone legitimately lists none while the project has plenty.
  echo "run.sh: no shared app scheme in $PROJECT (unshared schemes live in gitignored xcuserdata/)." >&2
  exit 2
elif [[ "$SCHEME_COUNT" -gt 1 ]]; then
  echo "run.sh: more than one app scheme ($ALL_SCHEMES) — this script assumes one." >&2
  exit 2
fi

# --- Device ----------------------------------------------------------------------------------
# Prefers a device that is already booted over a newer one that is not: booting a third simulator
# to run on it is slower and leaves the developer with three.
PICK_DEVICE=$(cat <<'PY'
import json, re, sys

want = sys.argv[1] if len(sys.argv) > 1 else ""
data = json.load(sys.stdin)

def runtime_version(identifier):
    m = re.search(r"iOS-(\d+)-(\d+)", identifier)
    return (int(m.group(1)), int(m.group(2))) if m else (-1, -1)

candidates = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if not d.get("isAvailable", True):
            continue
        candidates.append({
            "udid": d["udid"],
            "name": d["name"],
            "booted": d.get("state") == "Booted",
            "version": runtime_version(runtime),
        })

if not candidates:
    sys.stderr.write("run.sh: no available iOS simulators.\n")
    sys.exit(1)

if want:
    matches = [c for c in candidates if c["udid"] == want] or \
              [c for c in candidates if c["name"] == want]
    if not matches:
        sys.stderr.write("run.sh: no available simulator named or identified by %r.\n" % want)
        sys.exit(1)
    pick = max(matches, key=lambda c: c["version"])
else:
    phones = [c for c in candidates if c["name"].startswith("iPhone")] or candidates
    def rank(c):
        tier = 2 if "Pro Max" in c["name"] else 1 if "Pro" in c["name"] else 0
        return (c["booted"], c["version"], tier)
    pick = max(phones, key=rank)

print("\t".join([
    pick["udid"],
    pick["name"],
    "iOS %d.%d" % pick["version"],
    "booted" if pick["booted"] else "shutdown",
]))
PY
)

DEVICE="$(xcrun simctl list devices available -j | python3 -c "$PICK_DEVICE" "$DEVICE_ARG")" || exit 2
UDID="$(printf '%s' "$DEVICE" | cut -f1)"
SIM_LABEL="$(printf '%s' "$DEVICE" | cut -f2,3 | tr '\t' ' ')"
SIM_STATE="$(printf '%s' "$DEVICE" | cut -f4)"

echo "==> $SCHEME · $CONFIGURATION · $SIM_LABEL ($SIM_STATE)"

if [[ "$SIM_STATE" != "booted" ]]; then
  xcrun simctl boot "$UDID" || exit 2
fi

# The GUI is a separate component from the runtime, and an Xcode install can be missing it while
# simctl drives the device perfectly well. Headless is a working state, not a failure — say so
# once and carry on, rather than reporting a launch that did work as a launch that did not.
SIMULATOR_APP="$DEVELOPER_ROOT/Applications/Simulator.app"
if [[ -d "$SIMULATOR_APP" ]]; then
  open "$SIMULATOR_APP"
else
  echo "    note: no Simulator.app in this Xcode install — the device runs headless. Use --shot to see it."
fi

# --- Build -----------------------------------------------------------------------------------
# Not piped into tail/grep on purpose: a pipeline takes the LAST command's exit status, so a failed
# build would report success and the install below would happily push the previous .app.
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -configuration "$CONFIGURATION" \
  -quiet || exit 1

# --- Locate the product ------------------------------------------------------------------------
# Newest by mtime: DerivedData accumulates directories per project path, and a stale sibling from
# an old worktree is otherwise indistinguishable from the one just built.
APP="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -maxdepth 6 -type d \
    -path "*/Build/Products/$CONFIGURATION-iphonesimulator/$SCHEME.app" 2>/dev/null |
  while IFS= read -r path; do printf '%s\t%s\n' "$(stat -f '%m' "$path")" "$path"; done |
  sort -rn | head -1 | cut -f2-
)"
if [[ -z "$APP" ]]; then
  echo "run.sh: build succeeded but no $SCHEME.app found under DerivedData." >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null)"
if [[ -z "$BUNDLE_ID" ]]; then
  echo "run.sh: could not read CFBundleIdentifier from $APP/Info.plist." >&2
  exit 1
fi

# --- Install and launch ------------------------------------------------------------------------
xcrun simctl install "$UDID" "$APP" || exit 1
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1
xcrun simctl launch "$UDID" "$BUNDLE_ID" || exit 1

if [[ "$WANT_SHOT" == true ]]; then
  SHOT="${TMPDIR:-/tmp}/$SCHEME-$(date +%Y%m%d-%H%M%S).png"
  if xcrun simctl io "$UDID" screenshot "$SHOT" >/dev/null 2>&1; then
    echo "Screenshot: $SHOT"
    open "$SHOT"
  fi
fi

echo "App launched successfully on $SIM_LABEL."
