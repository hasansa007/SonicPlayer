# Rotary Shell — Slice 1: the wheel canvas

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the full-screen player with a canvas whose bottom 200pt is a detented rotary control that seeks, transports and adjusts volume and speed — with touch still working everywhere.

**Architecture:** Touch enters `RotaryWheel` (a view that owns no app state), is quantised into detents by `RotaryTracker` (pure Foundation), expressed as `WheelCommand`, routed by `WheelRouter` (pure) against a `WheelFocus`, and applied by `ShellViewModel` to `PlayerViewModel` and `HapticsClient`. Every decision is testable with nothing rendered and no device attached.

**Tech Stack:** Swift 5, SwiftUI, iOS 18+, CoreHaptics, Swift Testing. Zero third-party dependencies.

**Spec:** [`2026-08-09-rotary-shell-design.md`](../specs/2026-08-09-rotary-shell-design.md)

---

## Scope

This plan is **slice 1 of six**. It ends with the wheel canvas replacing `PlayerView` in the sheet at `SonicPlayer/App/AppView.swift:120-121`. Home still exists and still launches it.

**Not in this plan** — each gets its own: the menu sheet stack and deleting Home (slice 2), the trim editor (slice 3), full-screen capture (slice 4), the entry-point flip and issue closures (slices 5–6).

**Deliberately deferred and tracked in the spec §15:** landscape. `ShellView` in Task 11 handles portrait only and falls back to the existing `PlayerView` in compact height. That fallback is removed in slice 2, which is where landscape must be designed.

---

## File Structure

| File | Responsibility |
|---|---|
| `SonicPlayer/Domain/RotaryTracker.swift` | Angle → signed detents + acceleration. **The feel lives only here.** |
| `SonicPlayer/Domain/WheelCommand.swift` | The vocabulary the wheel can speak, and `WheelFocus` |
| `SonicPlayer/Domain/DetentFeedback.swift` | Which haptic fires, as data |
| `SonicPlayer/Domain/WheelRouter.swift` | `(command, focus) → [ShellEffect]`. Pure, table-testable |
| `SonicPlayer/Clients/HapticsClient.swift` | CoreHaptics wrapper, `.live` only (`.test` lives in the test target) |
| `SonicPlayer/DesignSystem/Components/RotaryWheel.swift` | The ring, five tap targets, lit arc. Emits commands |
| `SonicPlayer/DesignSystem/Components/WheelHUD.swift` | The transient value pill |
| `SonicPlayer/Features/Shell/ShellViewModel.swift` | Owns focus, applies effects |
| `SonicPlayer/Features/Shell/ShellView.swift` | Strip + stage + wheel zone |
| `SonicPlayer/DesignSystem/Tokens.swift` | **Modify** — wheel sizing, sheet radius, motion |
| `SonicPlayer/App/AppView.swift:120-121` | **Modify** — present `ShellView` instead of `PlayerView` |
| `SonicPlayer/App/AppViewModel.swift` | **Modify** — own and wire `ShellViewModel` |
| `SonicPlayerTests/TestClients.swift` | **Modify** — add `HapticsClient.test` |

Test files (the test target is filesystem-synchronized — dropping a file in is enough):
`RotaryTrackerTests.swift` · `WheelRouterTests.swift` · `DetentFeedbackTests.swift` · `ShellViewModelTests.swift`

---

## Task 0: Convert the app target to a filesystem-synchronized group

`SonicPlayerTests` is already a `PBXFileSystemSynchronizedRootGroup`; the app target is not, so each of its 69 Swift files is listed four times in `project.pbxproj`. This plan adds nine files. Doing this first removes 36 hand edits from this plan and the same again from slices 2–6.

**This task changes nothing about the app.** It must leave the build and the entire test suite exactly as they are. If it does not, restore the backup and fall back to explicit registration.

**Files:**
- Modify: `SonicPlayer.xcodeproj/project.pbxproj`

- [ ] **Step 1: Record the baseline, so "unchanged" is a measurement**

```bash
cd /Users/hasan/Developer/SonicPlayer
cp SonicPlayer.xcodeproj/project.pbxproj /tmp/pbxproj.backup
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5 > /tmp/baseline-tests.txt
cat /tmp/baseline-tests.txt
```

Expected: `** TEST SUCCEEDED **`. If it does not pass now, stop — this task cannot prove anything against a red baseline.

- [ ] **Step 2: Write the migration script**

This is a one-time migration, run from the scratchpad and never committed.

Create `/tmp/migrate-pbxproj.py`:

```python
import re, pathlib, sys

p = pathlib.Path("SonicPlayer.xcodeproj/project.pbxproj")
src = p.read_text()

SYNC_ID = "AC000200000000000000001"

def section(name):
    m = re.search(r"/\* Begin %s section \*/\n(.*?)/\* End %s section \*/" % (name, name), src, re.S)
    if not m: sys.exit("missing section: " + name)
    return m

# 1. every PBXBuildFile belongs to the app target (the test target is already synced),
#    so collect them all and the file references they point at.
build = section("PBXBuildFile")
file_refs = set(re.findall(r"fileRef = ([0-9A-F]{24,}) ", build.group(1)))
build_ids = set(re.findall(r"^\t\t([0-9A-F]{24,}) ", build.group(1), re.M))
print("build files: %d  file refs: %d" % (len(build_ids), len(file_refs)))

# 2. the Info.plist reference is not in a build phase; find it by path so it goes too.
info = re.search(r"^\t\t([0-9A-F]{24,}) /\* Info\.plist \*/", src, re.M)
if info: file_refs.add(info.group(1))

# 3. the SonicPlayer group and every group beneath it.
groups = section("PBXGroup")
blocks = re.findall(r"\t\t([0-9A-F]{24,}) /\* (.*?) \*/ = \{isa = PBXGroup;.*?\n\t\t\};", groups.group(1), re.S)
by_id = {}
for gid, _ in blocks:
    m = re.search(r"\t\t%s /\* .*? \*/ = \{isa = PBXGroup;(.*?)\n\t\t\};" % gid, groups.group(1), re.S)
    by_id[gid] = m.group(1)

root = None
for gid, body in by_id.items():
    if re.search(r"path = SonicPlayer;", body) and "children" in body:
        root = gid
if not root: sys.exit("could not find the SonicPlayer group")

doomed, stack = set(), [root]
while stack:
    gid = stack.pop()
    if gid in doomed: continue
    doomed.add(gid)
    for child in re.findall(r"([0-9A-F]{24,}) /\*", by_id.get(gid, "")):
        if child in by_id: stack.append(child)
print("groups removed: %d  root: %s" % (len(doomed), root))

out = src

# 4. drop every PBXBuildFile line.
out = re.sub(r"^\t\t[0-9A-F]{24,} /\* .*? in (Sources|Resources) \*/ = \{isa = PBXBuildFile;.*?\n", "", out, flags=re.M)

# 5. drop the file references those pointed at, plus Info.plist.
for fid in file_refs:
    out = re.sub(r"^\t\t%s /\* .*?\n" % fid, "", out, flags=re.M)

# 6. empty the app target's Sources and Resources file lists.
for phase in ("PBXSourcesBuildPhase", "PBXResourcesBuildPhase"):
    out = re.sub(r"(isa = %s;\n\t\t\tbuildActionMask = \d+;\n\t\t\tfiles = \()\n(?:\t+.*\n)*?(\t\t\t\);)" % phase,
                 r"\1\n\2", out)

# 7. remove the group subtree and its mention in any parent's children list.
for gid in doomed:
    out = re.sub(r"\t\t%s /\* .*? \*/ = \{isa = PBXGroup;.*?\n\t\t\};\n" % gid, "", out, flags=re.S)
    out = re.sub(r"^\t\t\t\t%s /\* .*?\n" % gid, "", out, flags=re.M)

# 8. declare the synchronized root group and hand it to the target and the main group.
out = out.replace(
    "/* End PBXFileSystemSynchronizedRootGroup section */",
    '\t\t%s /* SonicPlayer */ = {isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {}; explicitFolders = (); path = SonicPlayer; sourceTree = "<group>"; };\n/* End PBXFileSystemSynchronizedRootGroup section */' % SYNC_ID)

out = re.sub(r"(name = SonicPlayer;\n\t\t\tpackageProductDependencies)",
             "fileSystemSynchronizedGroups = (\n\t\t\t\t%s /* SonicPlayer */,\n\t\t\t);\n\t\t\t\\1" % SYNC_ID, out, count=1)

out = re.sub(r"(isa = PBXGroup;\n\t\t\tchildren = \(\n)", r"\1\t\t\t\t%s /* SonicPlayer */,\n" % SYNC_ID, out, count=1)

p.write_text(out)
print("done: %d lines -> %d lines" % (len(src.splitlines()), len(out.splitlines())))
```

- [ ] **Step 3: Run it**

```bash
cd /Users/hasan/Developer/SonicPlayer && python3 /tmp/migrate-pbxproj.py
```

Expected, approximately: `build files: 71  file refs: 71` · `groups removed: 9` · `done: 878 lines -> ~600 lines`

- [ ] **Step 4: Prove the build is unchanged**

```bash
xcodebuild build -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

**If it fails: `cp /tmp/pbxproj.backup SonicPlayer.xcodeproj/project.pbxproj`, stop, and report.** Do not debug forward — the fallback is explicit registration, and this task is not worth more than one attempt.

- [ ] **Step 5: Prove the resources still ship**

The two things filesystem sync most plausibly breaks are the asset catalog and the string catalog, and a missing string catalog does not fail the build — it silently ships English.

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "SonicPlayer.app" -path "*Debug-iphonesimulator*" | head -1)
ls "$APP/Assets.car" && ls "$APP" | grep -i lproj | head -3 && ls "$APP/Info.plist"
```

Expected: `Assets.car` exists, several `.lproj` directories are listed, `Info.plist` exists.

- [ ] **Step 6: Prove the whole suite still passes**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`, matching `/tmp/baseline-tests.txt`.

- [ ] **Step 7: Prove a new file needs no project edit — the whole point**

```bash
printf 'enum SyncSmokeTest { static let ok = true }\n' > SonicPlayer/Domain/SyncSmokeTest.swift
xcodebuild build -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
rm SonicPlayer/Domain/SyncSmokeTest.swift
```

Expected: `** BUILD SUCCEEDED **` with no change to `project.pbxproj`. Confirm with `git diff --stat SonicPlayer.xcodeproj/project.pbxproj` — only the migration's deletions should appear.

- [ ] **Step 8: Commit**

```bash
git add SonicPlayer.xcodeproj/project.pbxproj
git commit -m "build: sync the app target from the filesystem like the test target

Every Swift file in the app target was listed four times in project.pbxproj
— 276 of its 878 lines were bookkeeping. SonicPlayerTests has been a
PBXFileSystemSynchronizedRootGroup since it was created, which is why
CLAUDE.md can promise a test file just compiles. The app target now makes
the same promise.

Verified: clean build, full suite, Assets.car and the .lproj directories
present in the built product, and a new file compiling with no project edit."
```

---

## Task 1: Tokens for the wheel

**Files:**
- Modify: `SonicPlayer/DesignSystem/Tokens.swift`

- [ ] **Step 1: Add the sizing tokens**

In `enum Sizing`, after `static let rowHeight: CGFloat = 64`:

```swift
    /// The wheel's outer diameter. **Deliberately not scaled by Dynamic Type** — it is a physical
    /// control, and a control that moves under the thumb between accessibility settings is worse
    /// than one that stays put. Everything above it scales normally.
    static let wheelDiameter: CGFloat = 168
    static let wheelHub: CGFloat = 70
    /// The band at the bottom of the canvas the wheel owns. Nothing is drawn over it — except
    /// while capturing audio, which is the one stated exception (spec §4).
    static let wheelZone: CGFloat = 200
```

- [ ] **Step 2: Add the radius and motion tokens**

In `enum Radius`, after `static let lg: CGFloat = 16`:

```swift
    static let sheet: CGFloat = 18
```

In `enum Motion`, after `static let selectionMode`:

```swift
    /// The lit arc catching up to the thumb. Shorter than `.scrub` because the arc tracks a finger
    /// that is still moving — anything slower reads as lag rather than smoothing.
    static let detent: Animation = .linear(duration: 0.06)
    static let hudFade: Animation = .easeOut(duration: 0.25)
```

- [ ] **Step 3: Verify it builds**

```bash
xcodebuild build -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add SonicPlayer/DesignSystem/Tokens.swift
git commit -m "feat: tokens for the rotary wheel (#6)"
```

---

## Task 2: `RotaryTracker` — angle to detents

The feel of the whole feature is four numbers and four decisions, all of them here and none of them in a view.

**Files:**
- Create: `SonicPlayer/Domain/RotaryTracker.swift`
- Test: `SonicPlayerTests/RotaryTrackerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SonicPlayerTests/RotaryTrackerTests.swift`:

```swift
import Foundation
import Testing

@testable import SonicPlayer

/// The four things that are each a bug if wrong. Angles below are measured the way
/// `atan2(dy, dx)` reports them: 0° is due east, and y grows downward in a view's coordinate
/// space, so positive degrees run clockwise on screen.
@Suite
struct RotaryTrackerTests {

    private let centre = CGPoint(x: 100, y: 100)

    /// A point on the ring at `degrees`, far enough out to clear the dead zone.
    private func point(_ degrees: Double, radius: CGFloat = 80) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: centre.x + radius * cos(r), y: centre.y + radius * sin(r))
    }

    @Test func oneDetentIsTwelveDegrees() {
        var tracker = RotaryTracker()
        #expect(tracker.began(at: point(0), centre: centre))

        let step = tracker.moved(to: point(12), centre: centre, at: 1.0)

        #expect(step.detents == 1)
    }

    @Test func belowOneDetentEmitsNothingButIsNotLost() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)

        // Three 5° nudges are 15° — one detent, with 3° left over.
        #expect(tracker.moved(to: point(5), centre: centre, at: 1.0).detents == 0)
        #expect(tracker.moved(to: point(10), centre: centre, at: 2.0).detents == 0)
        #expect(tracker.moved(to: point(15), centre: centre, at: 3.0).detents == 1)
    }

    /// The seam. Reasoning about this produces ∓29 instead of ±1 and the wheel jumps a screen.
    @Test func crossingTheSeamIsOneDetentNotTwentyNine() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(174), centre: centre)

        let step = tracker.moved(to: point(-174), centre: centre, at: 1.0)

        #expect(step.detents == 1)
    }

    @Test func crossingTheSeamBackwardsIsMinusOne() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(-174), centre: centre)

        let step = tracker.moved(to: point(174), centre: centre, at: 1.0)

        #expect(step.detents == -1)
    }

    /// Near the centre the angle is numerically unstable — a one-point wobble is tens of degrees.
    @Test func touchesInsideTheDeadZoneAreRefused() {
        var tracker = RotaryTracker()

        #expect(!tracker.began(at: point(0, radius: 20), centre: centre))
    }

    @Test func draggingThroughTheDeadZoneEmitsNothing() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)

        let step = tracker.moved(to: point(90, radius: 12), centre: centre, at: 1.0)

        #expect(step.detents == 0)
    }

    /// Leaving and re-entering must not bank the angle swept while inside.
    @Test func leavingTheDeadZoneResumesWithoutABankedJump() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)
        _ = tracker.moved(to: point(90, radius: 12), centre: centre, at: 1.0)

        let step = tracker.moved(to: point(180), centre: centre, at: 2.0)

        #expect(step.detents == 0)
    }

    @Test func aSlowTurnIsNotAccelerated() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)

        let step = tracker.moved(to: point(12), centre: centre, at: 1.0)

        #expect(step.multiplier == 1)
    }

    @Test func aFastSpinAccelerates() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)

        // 20 detents inside one 220ms window.
        var last = RotaryTracker.Step(detents: 0, multiplier: 1)
        for i in 1...20 {
            last = tracker.moved(to: point(Double(i) * 12), centre: centre, at: 1.0 + Double(i) * 0.01)
        }

        #expect(last.multiplier > 1)
    }

    @Test func accelerationDecaysOnceTheWindowPasses() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)
        for i in 1...20 {
            _ = tracker.moved(to: point(Double(i) * 12), centre: centre, at: 1.0 + Double(i) * 0.01)
        }

        // One more detent, a full second later.
        let step = tracker.moved(to: point(21 * 12), centre: centre, at: 5.0)

        #expect(step.multiplier == 1)
    }

    @Test func endingClearsTheResidual() {
        var tracker = RotaryTracker()
        _ = tracker.began(at: point(0), centre: centre)
        _ = tracker.moved(to: point(10), centre: centre, at: 1.0)
        tracker.ended()

        _ = tracker.began(at: point(0), centre: centre)
        let step = tracker.moved(to: point(5), centre: centre, at: 2.0)

        #expect(step.detents == 0)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SonicPlayerTests/RotaryTrackerTests 2>&1 | tail -8
```

Expected: compilation failure — `cannot find 'RotaryTracker' in scope`.

- [ ] **Step 3: Write the implementation**

Create `SonicPlayer/Domain/RotaryTracker.swift`:

```swift
import CoreGraphics
import Foundation

/// Touch points on a ring, turned into discrete detents (#6, spec §5).
///
/// **This type is the feel of the wheel, and it is the only place the feel lives.** Tuning is
/// changing a constant here and a test beside it — never a number in a view. `CoreGraphics` is
/// imported for `CGPoint` only, the same concession `ScrubGeometry` makes.
///
/// Time arrives as a parameter rather than being read, which is what keeps acceleration pure:
/// a test drives twenty detents through a 200ms window without waiting 200ms.
struct RotaryTracker {

    /// 30 detents per revolution. Tuned in the browser prototype beside the spec and **not yet
    /// re-tuned on a device** — a mouse is not a thumb and there is no haptic in a browser.
    static let detentDegrees: Double = 12

    /// Below this, `atan2` is numerically unstable: a one-point wobble near the centre is tens of
    /// degrees, and the wheel sprays detents while the thumb is still.
    static let deadZoneRadius: CGFloat = 34

    /// How long a detent counts toward the spin rate.
    static let accelerationWindow: TimeInterval = 0.22

    /// Detents per window → multiplier. Read as: below 5 in a window, no acceleration.
    static let accelerationSteps: [(detents: Int, multiplier: Int)] = [
        (18, 40), (12, 15), (7, 5), (5, 2)
    ]

    struct Step: Equatable {
        /// Signed, and **not** multiplied — the caller applies `multiplier` to its own unit, so a
        /// list moves by rows and a scrub moves by seconds from the same number.
        var detents: Int
        var multiplier: Int
    }

    private var lastAngle: Double?
    private var residual: Double = 0
    private var recentDetents: [TimeInterval] = []

    init() {}

    /// Returns `false` when the touch starts inside the dead zone, which the caller should treat as
    /// "this drag is not a turn".
    mutating func began(at point: CGPoint, centre: CGPoint) -> Bool {
        residual = 0
        recentDetents = []
        guard Self.radius(point, centre) >= Self.deadZoneRadius else {
            lastAngle = nil
            return false
        }
        lastAngle = Self.angle(point, centre)
        return true
    }

    mutating func moved(to point: CGPoint, centre: CGPoint, at timestamp: TimeInterval) -> Step {
        guard Self.radius(point, centre) >= Self.deadZoneRadius else {
            // Drop the anchor rather than banking the sweep. Re-entering the ring somewhere else
            // must not pay out the angle crossed while inside it.
            lastAngle = nil
            return Step(detents: 0, multiplier: multiplier(at: timestamp))
        }

        let angle = Self.angle(point, centre)
        defer { lastAngle = angle }

        guard let previous = lastAngle else {
            return Step(detents: 0, multiplier: multiplier(at: timestamp))
        }

        residual += Self.shortestArc(from: previous, to: angle)

        var detents = 0
        while abs(residual) >= Self.detentDegrees {
            let direction = residual > 0 ? 1 : -1
            detents += direction
            residual -= Double(direction) * Self.detentDegrees
            recentDetents.append(timestamp)
        }

        return Step(detents: detents, multiplier: multiplier(at: timestamp))
    }

    mutating func ended() {
        lastAngle = nil
        residual = 0
        recentDetents = []
    }

    private mutating func multiplier(at timestamp: TimeInterval) -> Int {
        recentDetents.removeAll { timestamp - $0 > Self.accelerationWindow }
        let rate = recentDetents.count
        for step in Self.accelerationSteps where rate >= step.detents {
            return step.multiplier
        }
        return 1
    }

    // MARK: - Geometry

    private static func radius(_ point: CGPoint, _ centre: CGPoint) -> CGFloat {
        hypot(point.x - centre.x, point.y - centre.y)
    }

    /// Degrees, 0° due east, growing clockwise on screen because a view's y grows downward.
    private static func angle(_ point: CGPoint, _ centre: CGPoint) -> Double {
        atan2(Double(point.y - centre.y), Double(point.x - centre.x)) * 180 / .pi
    }

    /// The short way round. Without this, 174° → -174° reads as -348° — the wheel jumps 29 detents
    /// backwards at the seam instead of one forwards.
    static func shortestArc(from: Double, to: Double) -> Double {
        var delta = to - from
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SonicPlayerTests/RotaryTrackerTests 2>&1 | tail -8
```

Expected: `** TEST SUCCEEDED **`, 11 tests passing.

- [ ] **Step 5: Commit**

```bash
git add SonicPlayer/Domain/RotaryTracker.swift SonicPlayerTests/RotaryTrackerTests.swift
git commit -m "feat: RotaryTracker — angle to detents, with the seam tested (#6)"
```

---

## Task 3: `WheelCommand` and `WheelFocus`

**Files:**
- Create: `SonicPlayer/Domain/WheelCommand.swift`

- [ ] **Step 1: Write it**

There is no test for this task. It is a pair of enums with no behaviour; `WheelRouterTests` in Task 5 is what exercises them, and a test asserting that an enum has cases tests the compiler.

Create `SonicPlayer/Domain/WheelCommand.swift`:

```swift
import Foundation

/// Everything the wheel can say (#6, spec §7).
///
/// The view knows only these. It does not know what seeking is, which is what lets the same
/// component drive Now Playing, a menu and the trim editor without growing a mode flag.
enum WheelCommand: Equatable {
    /// Signed detents, already multiplied by the caller's acceleration.
    case tick(Int)
    case select
    case back
    case menu
    case transport(Transport)

    enum Transport: Equatable {
        case previous
        case next
        case playPause
    }
}

/// Where a command lands.
///
/// Slice 1 carries only the Now Playing cases. `.menu` and `.trim` arrive with slices 2 and 3, and
/// the reason this is an enum rather than a boolean is that they will.
enum WheelFocus: Equatable {
    case nowPlaying(Axis)

    enum Axis: Equatable {
        case seek
        case volume
        case speed
    }

    /// What the wheel does when nothing has claimed it.
    static let `default` = WheelFocus.nowPlaying(.seek)
}
```

- [ ] **Step 2: Verify it builds**

```bash
xcodebuild build -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SonicPlayer/Domain/WheelCommand.swift
git commit -m "feat: the wheel's vocabulary and focus (#6)"
```

---

## Task 4: `DetentFeedback` — which haptic, as data

**Files:**
- Create: `SonicPlayer/Domain/DetentFeedback.swift`
- Test: `SonicPlayerTests/DetentFeedbackTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SonicPlayerTests/DetentFeedbackTests.swift`:

```swift
import Foundation
import Testing

@testable import SonicPlayer

/// The haptic design, asserted without a device that can vibrate.
@Suite
struct DetentFeedbackTests {

    @Test func anOrdinaryDetentIsALightTick() {
        let pulse = DetentFeedback.pulse(for: .detent)

        #expect(pulse.intensity == 0.5)
        #expect(pulse.sharpness == 0.8)
    }

    /// Hitting the start or end of a track must feel different from turning through it, or you
    /// keep turning against a wall you cannot see.
    @Test func reachingALimitIsHeavierAndDuller() {
        let limit = DetentFeedback.pulse(for: .limit)
        let detent = DetentFeedback.pulse(for: .detent)

        #expect(limit.intensity > detent.intensity)
        #expect(limit.sharpness < detent.sharpness)
    }

    @Test func committingIsTheStrongestOfTheThree() {
        let commit = DetentFeedback.pulse(for: .commit)

        #expect(commit.intensity == 1.0)
    }

    @Test func everyPulseIsInsideCoreHapticsRange() {
        for event in DetentFeedback.Event.allCases {
            let pulse = DetentFeedback.pulse(for: event)
            #expect((0...1).contains(pulse.intensity), "\(event) intensity out of range")
            #expect((0...1).contains(pulse.sharpness), "\(event) sharpness out of range")
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SonicPlayerTests/DetentFeedbackTests 2>&1 | tail -8
```

Expected: `cannot find 'DetentFeedback' in scope`.

- [ ] **Step 3: Write the implementation**

Create `SonicPlayer/Domain/DetentFeedback.swift`:

```swift
import Foundation

/// The haptic design, expressed as data so it can be reviewed and tested rather than felt (#6).
///
/// Pure Foundation on purpose: `HapticsClient` turns these into `CHHapticEvent`s, and nothing
/// about *which* pulse fires needs CoreHaptics to decide.
enum DetentFeedback {

    enum Event: CaseIterable {
        /// One click of the ring.
        case detent
        /// The value could not move — start or end of a track, top or bottom of a list.
        case limit
        /// A choice was taken.
        case commit
    }

    /// CoreHaptics' two axes, both `0...1`. Intensity is how hard; sharpness is how crisp — a low
    /// sharpness reads as a dull thud, a high one as a tap.
    struct Pulse: Equatable {
        var intensity: Double
        var sharpness: Double
    }

    static func pulse(for event: Event) -> Pulse {
        switch event {
        case .detent: Pulse(intensity: 0.5, sharpness: 0.8)
        case .limit:  Pulse(intensity: 0.9, sharpness: 0.3)
        case .commit: Pulse(intensity: 1.0, sharpness: 0.9)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SonicPlayerTests/DetentFeedbackTests 2>&1 | tail -8
```

Expected: `** TEST SUCCEEDED **`, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add SonicPlayer/Domain/DetentFeedback.swift SonicPlayerTests/DetentFeedbackTests.swift
git commit -m "feat: the haptic design as data (#6)"
```

---

## Task 5: `WheelRouter` — the routing table

**Files:**
- Create: `SonicPlayer/Domain/WheelRouter.swift`
- Test: `SonicPlayerTests/WheelRouterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SonicPlayerTests/WheelRouterTests.swift`:

```swift
import Foundation
import Testing

@testable import SonicPlayer

/// Command × focus → effects, exhaustively, with nothing rendered.
@Suite
struct WheelRouterTests {

    @Test func turningWhileSeekingSeeksBySecondsPerDetent() {
        let effects = WheelRouter.route(.tick(3), focus: .nowPlaying(.seek))

        #expect(effects == [.seekBy(0.3), .feedback(.detent)])
    }

    @Test func turningBackwardsSeeksBackwards() {
        let effects = WheelRouter.route(.tick(-2), focus: .nowPlaying(.seek))

        #expect(effects == [.seekBy(-0.2), .feedback(.detent)])
    }

    @Test func aZeroTickDoesNothingAtAll() {
        #expect(WheelRouter.route(.tick(0), focus: .nowPlaying(.seek)).isEmpty)
    }

    @Test func turningWhileOnVolumeChangesVolume() {
        let effects = WheelRouter.route(.tick(2), focus: .nowPlaying(.volume))

        #expect(effects == [.volumeBy(0.04), .feedback(.detent)])
    }

    @Test func turningWhileOnSpeedStepsThePresets() {
        let effects = WheelRouter.route(.tick(1), focus: .nowPlaying(.speed))

        #expect(effects == [.speedBy(1), .feedback(.detent)])
    }

    @Test func theHubPlaysAndPauses() {
        let effects = WheelRouter.route(.select, focus: .nowPlaying(.seek))

        #expect(effects == [.playPause, .feedback(.commit)])
    }

    @Test func transportIsIndependentOfFocus() {
        for axis in [WheelFocus.Axis.seek, .volume, .speed] {
            let effects = WheelRouter.route(.transport(.next), focus: .nowPlaying(axis))
            #expect(effects == [.nextTrack, .feedback(.commit)], "axis \(axis)")
        }
    }

    /// Slice 1 has nothing to go back to. It must be inert rather than crash or seek.
    @Test func backAndMenuAreInertInSliceOne() {
        #expect(WheelRouter.route(.back, focus: .nowPlaying(.seek)).isEmpty)
        #expect(WheelRouter.route(.menu, focus: .nowPlaying(.seek)).isEmpty)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SonicPlayerTests/WheelRouterTests 2>&1 | tail -8
```

Expected: `cannot find 'WheelRouter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `SonicPlayer/Domain/WheelRouter.swift`:

```swift
import Foundation

/// What a command does, given what has the wheel (#6, spec §7).
///
/// **This is a separate type because it is the piece that grows.** Every focus and every menu level
/// this epic adds is a case here; `PlayerViewModel` reached 633 lines by absorbing exactly this kind
/// of growth. As a pure function it is a table, and a table can be tested exhaustively.
enum WheelRouter {

    /// One detent of seeking. The fine step — coarse travel is dragging `SonicScrubber`, which is
    /// the pairing the whole design rests on (spec §5).
    static let secondsPerDetent: TimeInterval = 0.1

    /// One detent of volume, as a fraction of the full range. 50 detents end to end.
    static let volumePerDetent: Double = 0.02

    static func route(_ command: WheelCommand, focus: WheelFocus) -> [ShellEffect] {
        switch command {
        case .tick(let detents):
            guard detents != 0 else { return [] }
            switch focus {
            case .nowPlaying(.seek):
                return [.seekBy(TimeInterval(detents) * secondsPerDetent), .feedback(.detent)]
            case .nowPlaying(.volume):
                return [.volumeBy(Double(detents) * volumePerDetent), .feedback(.detent)]
            case .nowPlaying(.speed):
                return [.speedBy(detents), .feedback(.detent)]
            }

        case .select:
            return [.playPause, .feedback(.commit)]

        case .transport(.previous):
            return [.previousTrack, .feedback(.commit)]
        case .transport(.next):
            return [.nextTrack, .feedback(.commit)]
        case .transport(.playPause):
            return [.playPause, .feedback(.commit)]

        // Slice 1 has no menu and no level to pop. Inert, not absent — the ring already draws these
        // two targets, and a target that silently does nothing beats one that moves under the thumb
        // when slice 2 lands.
        case .back, .menu:
            return []
        }
    }
}

/// What the shell should do about it. A value, so `ShellViewModelTests` can assert intent rather
/// than observe side effects.
enum ShellEffect: Equatable {
    case seekBy(TimeInterval)
    case volumeBy(Double)
    case speedBy(Int)
    case playPause
    case nextTrack
    case previousTrack
    case feedback(DetentFeedback.Event)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SonicPlayerTests/WheelRouterTests 2>&1 | tail -8
```

Expected: `** TEST SUCCEEDED **`, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add SonicPlayer/Domain/WheelRouter.swift SonicPlayerTests/WheelRouterTests.swift
git commit -m "feat: WheelRouter — command x focus as a testable table (#6)"
```

---

## Task 6: `HapticsClient`

**Files:**
- Create: `SonicPlayer/Clients/HapticsClient.swift`
- Modify: `SonicPlayerTests/TestClients.swift`

- [ ] **Step 1: Write the client**

Create `SonicPlayer/Clients/HapticsClient.swift`:

```swift
import CoreHaptics
import Foundation
import UIKit

/// The wheel's haptics (#6). A struct of closures with a `.live`, like the other five.
///
/// No new dependency — CoreHaptics ships with iOS. `.test` lives in the test target, which is where
/// every `.test` has lived since #20.
struct HapticsClient {
    /// Called before the first pulse. Starting the engine lazily on the first detent costs a
    /// perceptible delay on exactly the pulse the user is judging the feature by.
    var prepare: @Sendable () -> Void = {}
    var fire: @Sendable (DetentFeedback.Pulse) -> Void = { _ in }
    var stop: @Sendable () -> Void = {}
}

extension HapticsClient {

    static let live: HapticsClient = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            // iPad, the simulator, and older phones. `UIImpactFeedbackGenerator` is a coarser
            // instrument — one fixed pulse shape — but silence would make the wheel feel broken.
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            return Self(
                prepare: { generator.prepare() },
                fire: { pulse in generator.impactOccurred(intensity: pulse.intensity) },
                stop: {}
            )
        }

        let box = EngineBox()
        return Self(
            prepare: { box.start() },
            fire: { pulse in box.fire(pulse) },
            stop: { box.stop() }
        )
    }()
}

/// Holds the engine and the two lifecycle facts that make CoreHaptics awkward in practice: it stops
/// when the app backgrounds, and it resets if the media server restarts. Both hand back a running
/// engine only if something asks it to start again.
private final class EngineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: CHHapticEngine?

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard engine == nil else { return }
        do {
            let created = try CHHapticEngine()
            created.stoppedHandler = { [weak self] _ in self?.clear() }
            created.resetHandler = { [weak self] in self?.restart() }
            try created.start()
            engine = created
        } catch {
            // A wheel that does not buzz is worse than one that does; a wheel that crashes is worse
            // than both. There is nothing the user can do about a haptic engine that will not start.
            engine = nil
        }
    }

    func fire(_ pulse: DetentFeedback.Pulse) {
        lock.lock()
        let current = engine
        lock.unlock()
        guard let current else { return }

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(pulse.intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(pulse.sharpness))
            ],
            relativeTime: 0
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try current.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            // Same reasoning as `start`.
        }
    }

    func stop() {
        lock.lock()
        let current = engine
        engine = nil
        lock.unlock()
        current?.stop()
    }

    private func clear() {
        lock.lock()
        engine = nil
        lock.unlock()
    }

    private func restart() {
        lock.lock()
        let current = engine
        lock.unlock()
        try? current?.start()
    }
}
```

- [ ] **Step 2: Add the `.test` client**

In `SonicPlayerTests/TestClients.swift`, after the `ArtworkClient` extension:

```swift
extension HapticsClient {
    /// `fire` reports, so a test that reaches the wheel's feedback path without meaning to says so.
    /// `prepare` and `stop` are lifecycle no-ops every path calls — reporting them would only ever
    /// produce noise.
    static var test: Self {
        Self(
            prepare: {},
            fire: { _ in Issue.record("HapticsClient.fire is unimplemented") },
            stop: {}
        )
    }
}
```

- [ ] **Step 3: Verify it builds and nothing regressed**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add SonicPlayer/Clients/HapticsClient.swift SonicPlayerTests/TestClients.swift
git commit -m "feat: HapticsClient — CoreHaptics with a generator fallback (#6)"
```

---

## Task 7: `ShellViewModel`

**Files:**
- Modify: `SonicPlayer/Domain/ScrubClamp.swift`
- Create: `SonicPlayer/Features/Shell/ShellViewModel.swift`
- Test: `SonicPlayerTests/ScrubClampTests.swift` (add to it if it exists)
- Test: `SonicPlayerTests/ShellViewModelTests.swift`

- [ ] **Step 1: Give `ScrubClamp` a bounds function**

`ScrubClamp` today is the *recording editor's* clamp — both its functions are built around a fixed
`interval: TimeInterval = 15`, so neither answers "where does an arbitrary seek land". It gains one
function rather than the shell growing a second answer to the same question.

Append to `enum ScrubClamp` in `SonicPlayer/Domain/ScrubClamp.swift`:

```swift
    /// An arbitrary position, held inside the recording.
    ///
    /// The two functions above step by a fixed `interval`; this one takes a position already
    /// computed by the caller — the wheel's detent seek, where the step is 0.1s and comes from
    /// `WheelRouter`. Kept here so the bounds of a scrub position have one answer in this codebase.
    ///
    /// A non-positive duration means the asset has not loaded, and the answer is the start rather
    /// than a negative time: this feeds `seek(to:)`, and an `AVPlayer` seeked to a bad value does
    /// not recover.
    static func position(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return min(max(0, time), duration)
    }
```

Add to `SonicPlayerTests/ScrubClampTests.swift` (create it with the `import Foundation` /
`import Testing` / `@testable import SonicPlayer` header if it does not exist):

```swift
@Suite
struct ScrubClampPositionTests {

    @Test func aPositionInsideTheTrackIsUnchanged() {
        #expect(ScrubClamp.position(30, duration: 100) == 30)
    }

    @Test func pastTheEndClampsToTheEnd() {
        #expect(ScrubClamp.position(140, duration: 100) == 100)
    }

    @Test func beforeTheStartClampsToZero() {
        #expect(ScrubClamp.position(-4, duration: 100) == 0)
    }

    /// An unloaded asset reports zero duration, and seeking to a negative time is unrecoverable.
    @Test func anUnloadedDurationAnswersTheStart() {
        #expect(ScrubClamp.position(30, duration: 0) == 0)
    }
}
```

- [ ] **Step 2: Run those four and verify they pass**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SonicPlayerTests/ScrubClampPositionTests 2>&1 | tail -6
```

Expected: `** TEST SUCCEEDED **`, 4 tests.

- [ ] **Step 3: Write the failing shell tests**

Create `SonicPlayerTests/ShellViewModelTests.swift`:

```swift
import Foundation
import Testing

@testable import SonicPlayer

/// The whole shell, driven with nothing rendered — the thing routing through a command stream buys.
@Suite(.serialized)
struct ShellViewModelTests {

    @MainActor
    private func makeShell() -> (ShellViewModel, PlayerViewModel) {
        var haptics = HapticsClient.test
        haptics.fire = { _ in }
        let player = PlayerViewModel(audioPlayer: .test)
        player.duration = 100
        player.currentTime = 50
        return (ShellViewModel(player: player, haptics: haptics), player)
    }

    @MainActor
    @Test func turningSeeksByTheDetentSize() {
        let (shell, _) = makeShell()
        var sought: TimeInterval?
        shell.onSeek = { sought = $0 }

        shell.receive(.tick(5))

        #expect(sought == 50.5)
    }

    @MainActor
    @Test func seekingIsClampedToTheTrack() {
        let (shell, player) = makeShell()
        player.currentTime = 99.95
        var sought: TimeInterval?
        shell.onSeek = { sought = $0 }

        shell.receive(.tick(20))

        #expect(sought == 100)
    }

    @MainActor
    @Test func aRefusedSeekFeelsDifferentFromAnAcceptedOne() {
        let (shell, player) = makeShell()
        player.currentTime = 100
        var fired: [DetentFeedback.Pulse] = []
        var haptics = HapticsClient.test
        haptics.fire = { fired.append($0) }
        let atLimit = ShellViewModel(player: player, haptics: haptics)
        atLimit.onSeek = { _ in }

        atLimit.receive(.tick(3))

        #expect(fired == [DetentFeedback.pulse(for: .limit)])
    }

    @MainActor
    @Test func theHubTogglesPlayback() {
        let (shell, _) = makeShell()
        var toggled = false
        shell.onPlayPause = { toggled = true }

        shell.receive(.select)

        #expect(toggled)
    }

    @MainActor
    @Test func focusStartsOnSeek() {
        let (shell, _) = makeShell()

        #expect(shell.focus == .nowPlaying(.seek))
    }

    @MainActor
    @Test func claimingVolumeMovesTheFocusAndRaisesTheHUD() {
        let (shell, _) = makeShell()

        shell.claim(.volume)

        #expect(shell.focus == .nowPlaying(.volume))
        #expect(shell.hud != nil)
    }

    @MainActor
    @Test func releasingReturnsToSeekAndDropsTheHUD() {
        let (shell, _) = makeShell()
        shell.claim(.volume)

        shell.release()

        #expect(shell.focus == .nowPlaying(.seek))
        #expect(shell.hud == nil)
    }

    /// Slice 1's inert targets. They must not seek, and must not crash.
    @MainActor
    @Test func menuAndBackDoNothingYet() {
        let (shell, _) = makeShell()
        var sought = false
        shell.onSeek = { _ in sought = true }

        shell.receive(.menu)
        shell.receive(.back)

        #expect(!sought)
    }
}
```

- [ ] **Step 4: Run them to verify they fail**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SonicPlayerTests/ShellViewModelTests 2>&1 | tail -8
```

Expected: `cannot find 'ShellViewModel' in scope`.

- [ ] **Step 5: Write the implementation**

Create `SonicPlayer/Features/Shell/ShellViewModel.swift`:

```swift
import Foundation
import Observation

/// Owns what has the wheel, and applies what the router decides (#6, spec §7).
///
/// **It applies effects; it does not decide them.** Every "what should this do" question is
/// `WheelRouter`'s, which is why this type stays small while the epic adds focuses.
///
/// The outbound edges are closures rather than direct calls on `PlayerViewModel`, following
/// `CollectionsViewModel.onWillRemoveItems` — the shape that lets `AppViewModelTests` exercise an
/// edge without a view. `AppViewModel.wire()` connects them.
@MainActor
@Observable
final class ShellViewModel {

    private(set) var focus: WheelFocus = .default

    /// What the transient pill is showing, or `nil` when nothing is claimed.
    private(set) var hud: HUD?

    struct HUD: Equatable {
        var label: String
        var value: String
    }

    var onSeek: ((TimeInterval) -> Void)?
    var onPlayPause: (() -> Void)?
    var onNextTrack: (() -> Void)?
    var onPreviousTrack: (() -> Void)?
    var onVolumeBy: ((Double) -> Void)?
    var onSpeedBy: ((Int) -> Void)?

    private let player: PlayerViewModel
    private let haptics: HapticsClient

    init(player: PlayerViewModel, haptics: HapticsClient = .live) {
        self.player = player
        self.haptics = haptics
        haptics.prepare()
    }

    /// The single entry point. Every gesture, tap and VoiceOver adjustment arrives here.
    func receive(_ command: WheelCommand) {
        for effect in WheelRouter.route(command, focus: focus) {
            apply(effect)
        }
    }

    /// A control claims the wheel — spec §5: touching a control takes the wheel, and it goes back
    /// to seeking when the pill fades. There is no mode that persists invisibly.
    func claim(_ axis: WheelFocus.Axis) {
        focus = .nowPlaying(axis)
        hud = hudContents(for: axis)
    }

    func release() {
        focus = .default
        hud = nil
    }

    private func apply(_ effect: ShellEffect) {
        switch effect {
        case .seekBy(let delta):
            let target = ScrubClamp.position(player.currentTime + delta, duration: player.duration)
            guard target != player.currentTime else {
                // At a limit. Reported as a distinct pulse rather than nothing, so turning against
                // the end of a track feels like a wall instead of a dead wheel.
                haptics.fire(DetentFeedback.pulse(for: .limit))
                return
            }
            onSeek?(target)
            hud = HUD(label: String(localized: "Seek"), value: Self.formatted(target))

        case .volumeBy(let delta):
            onVolumeBy?(delta)

        case .speedBy(let steps):
            onSpeedBy?(steps)

        case .playPause:
            onPlayPause?()

        case .nextTrack:
            onNextTrack?()

        case .previousTrack:
            onPreviousTrack?()

        case .feedback(let event):
            haptics.fire(DetentFeedback.pulse(for: event))
        }
    }

    private func hudContents(for axis: WheelFocus.Axis) -> HUD {
        switch axis {
        case .seek:
            HUD(label: String(localized: "Seek"), value: Self.formatted(player.currentTime))
        case .volume:
            HUD(label: String(localized: "Volume"), value: "")
        case .speed:
            HUD(label: String(localized: "Speed"), value: player.playbackSpeed.displayText)
        }
    }

    private static func formatted(_ time: TimeInterval) -> String {
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 6: Run the shell tests to verify they pass**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SonicPlayerTests/ShellViewModelTests 2>&1 | tail -8
```

Expected: `** TEST SUCCEEDED **`, 8 tests.

- [ ] **Step 7: Commit**

```bash
git add SonicPlayer/Domain/ScrubClamp.swift SonicPlayerTests/ScrubClampTests.swift \
        SonicPlayer/Features/Shell/ShellViewModel.swift SonicPlayerTests/ShellViewModelTests.swift
git commit -m "feat: ShellViewModel — applies effects, decides nothing (#6)

ScrubClamp gains position(_:duration:). Its two existing functions step by
a fixed 15s interval, so neither answered where an arbitrary seek lands —
and the bounds of a scrub position should have one answer, in the type that
already owns it."
```

---

## Task 8: `RotaryWheel` — the component

**Files:**
- Create: `SonicPlayer/DesignSystem/Components/RotaryWheel.swift`

- [ ] **Step 1: Write it**

Create `SonicPlayer/DesignSystem/Components/RotaryWheel.swift`:

```swift
import SwiftUI

/// The ring, its five targets, and the lit arc (#6, spec §4).
///
/// **It owns no app state and knows nothing about playback.** It emits `WheelCommand` and that is
/// all — which is what lets slices 2 and 3 point it at a menu and a trim editor unchanged.
///
/// **Pinned to `.leftToRight`, and that is deliberate (spec §8).** `PlayerView.swift:319` pins
/// transport for the same reason: these controls point at the direction the *media* travels, not
/// the direction text is read. Pinning also removes the question of whether a rotation transform
/// mirrors — a question that produced two wrong bug reports in this repo (#54, #63) before anyone
/// measured it. The drag maths does not need it either way: `ScrubGeometry` records that a
/// `DragGesture`'s `location.x` is **not** mirrored, so `atan2` already yields a physical angle.
struct RotaryWheel: View {

    let hubLabel: String
    let isPlaying: Bool
    let onCommand: (WheelCommand) -> Void

    @State private var tracker = RotaryTracker()
    @State private var thumbAngle: Double?

    private var diameter: CGFloat { Sizing.wheelDiameter }

    var body: some View {
        ZStack {
            ring
            targets
            hub
        }
        .frame(width: diameter, height: diameter)
        .environment(\.layoutDirection, .leftToRight)
        .gesture(turn)
    }

    // MARK: - Pieces

    private var ring: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.sonicPrimary.opacity(0.2), lineWidth: Sizing.hairlineTrackHeight)

            if let thumbAngle {
                Circle()
                    .trim(from: 0, to: 0.08)
                    .stroke(Color.sonicPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(thumbAngle - 104))
                    .animation(Motion.detent, value: thumbAngle)
            }
        }
        .accessibilityHidden(true)
    }

    /// The five taps. Separate elements with labels, so VoiceOver gets the whole app without the
    /// rotation gesture — which it cannot perform.
    private var targets: some View {
        ZStack {
            target("chevron.up", Text("Back"), at: .top) { onCommand(.back) }
            target("backward.end.fill", Text("Previous track"), at: .leading) {
                onCommand(.transport(.previous))
            }
            target("forward.end.fill", Text("Next track"), at: .trailing) {
                onCommand(.transport(.next))
            }
            target("line.3.horizontal", Text("Menu"), at: .bottom) { onCommand(.menu) }
        }
    }

    private func target(
        _ systemImage: String,
        _ label: Text,
        at edge: Alignment,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.sonicControlGlyph)
                .foregroundColor(.sonicTextSecondary)
                .frame(width: Sizing.compactControl, height: Sizing.compactControl)
        }
        .accessibilityLabel(label)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge)
        .padding(Spacing.sm)
    }

    private var hub: some View {
        Button {
            onCommand(.select)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.sonicSurface)
                    .frame(width: Sizing.wheelHub, height: Sizing.wheelHub)
                    .sonicShadow(Elevation.control)

                Text(hubLabel)
                    .font(.sonicControlGlyph)
                    .foregroundColor(.sonicPrimary)
            }
        }
        .accessibilityLabel(Text(isPlaying ? "Pause" : "Play"))
        // The wheel's adjustable behaviour hangs off the hub, because it is the one element
        // VoiceOver reliably lands on. A swipe up or down is one detent — full precision without
        // the gesture.
        .accessibilityValue(Text(hubLabel))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCommand(.tick(1))
            case .decrement: onCommand(.tick(-1))
            @unknown default: break
            }
        }
    }

    // MARK: - The turn

    private var turn: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let centre = CGPoint(x: diameter / 2, y: diameter / 2)
                if thumbAngle == nil {
                    guard tracker.began(at: value.startLocation, centre: centre) else { return }
                }
                let step = tracker.moved(
                    to: value.location,
                    centre: centre,
                    at: value.time.timeIntervalSinceReferenceDate
                )
                thumbAngle = Self.degrees(of: value.location, centre: centre)
                guard step.detents != 0 else { return }
                onCommand(.tick(step.detents * step.multiplier))
            }
            .onEnded { _ in
                tracker.ended()
                thumbAngle = nil
            }
    }

    private static func degrees(of point: CGPoint, centre: CGPoint) -> Double {
        atan2(Double(point.y - centre.y), Double(point.x - centre.x)) * 180 / .pi
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
xcodebuild build -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SonicPlayer/DesignSystem/Components/RotaryWheel.swift
git commit -m "feat: RotaryWheel — the ring, its targets, and an adjustable action (#6)"
```

---

## Task 9: `WheelHUD` — the transient pill

**Files:**
- Create: `SonicPlayer/DesignSystem/Components/WheelHUD.swift`

- [ ] **Step 1: Write it**

Create `SonicPlayer/DesignSystem/Components/WheelHUD.swift`:

```swift
import SwiftUI

/// The pill that states what the wheel is changing, then fades (#6, spec §5).
///
/// Discrete choices belong in a sheet; continuous ones belong here. It is `accessibilityHidden`
/// because the value it shows is already `RotaryWheel`'s `accessibilityValue` — announcing it twice
/// is how a VoiceOver user ends up hearing every detent read out.
struct WheelHUD: View {

    let label: String
    let value: String

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .foregroundColor(.sonicTextSecondary)

            if !value.isEmpty {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(.sonicPrimary)
            }
        }
        .padding(.horizontal, Sizing.chipInsetH)
        .padding(.vertical, Spacing.sm)
        .background(
            Color.sonicBackground.opacity(0.94),
            in: RoundedRectangle(cornerRadius: Radius.md)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.sonicPrimary.opacity(0.3), lineWidth: 1)
        )
        .sonicShadow(Elevation.control)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
xcodebuild build -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SonicPlayer/DesignSystem/Components/WheelHUD.swift
git commit -m "feat: the transient value pill (#6)"
```

---

## Task 10: `ShellView` — the canvas

**Files:**
- Create: `SonicPlayer/Features/Shell/ShellView.swift`

- [ ] **Step 1: Write it**

Create `SonicPlayer/Features/Shell/ShellView.swift`:

```swift
import SwiftUI

/// The wheel canvas (#6, spec §4).
///
/// **The governing rule: the wheel is furniture.** It owns the bottom `Sizing.wheelZone` and nothing
/// is drawn over it. The stage above changes; the controls do not.
///
/// **Landscape is deliberately unanswered** (spec §15): 200pt of wheel in a 393pt-tall canvas does
/// not work, and the answer is the wheel moved to one side rather than this layout rotated. Until
/// that is designed, compact height falls back to `PlayerView`. Slice 2 removes this fallback and
/// must not ship without the landscape design.
struct ShellView: View {

    let shell: ShellViewModel
    let player: PlayerViewModel

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        if isLandscape {
            PlayerView(player: player)
        } else {
            portrait
        }
    }

    private var portrait: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.sonicPrimaryLight.opacity(0.15),
                    Color.sonicBackground,
                    Color.sonicBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                stage
                Spacer(minLength: 0)
            }
            .padding(.bottom, Sizing.wheelZone)

            if let hud = shell.hud {
                WheelHUD(label: hud.label, value: hud.value)
                    .padding(.bottom, Sizing.wheelZone - Spacing.xs)
                    .animation(Motion.hudFade, value: hud)
            }

            wheelZone
        }
    }

    /// Everything above the wheel.
    ///
    /// **All three states, in `PlayerView`'s order and for its reasons** (spec §10 — epic #6
    /// requires every screen to have them). The order matters: `loadTrack` sets `currentTrack` and
    /// `isLoadingTrack` in the same breath, so "loading" is not "no track", and gating the loading
    /// state on a zero duration keeps it off the screen during a track *switch*, where the previous
    /// duration is still valid and blanking would be a regression.
    private var stage: some View {
        VStack(spacing: Spacing.xl) {
            if let error = player.openError {
                VStack(spacing: Spacing.xl) {
                    EmptyStateView(
                        icon: "exclamationmark.triangle",
                        title: "Couldn't Open This File",
                        iconStyle: AnyShapeStyle(Color.sonicOrange),
                        iconSize: DisplayFont.stateIcon,
                        spacing: Spacing.lg
                    )

                    // Rendered separately because this string comes from the failing `Error` and is
                    // already localised — running it through the catalog looks up a key that by
                    // definition is not there.
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.sonicTextSecondary)
                        .multilineTextAlignment(.center)

                    Button("Dismiss") { player.openError = nil }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicPrimary)
                        .padding(.horizontal, Sizing.chipInsetH)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            Color.sonicPrimary.opacity(ControlTint.on),
                            in: RoundedRectangle(cornerRadius: Radius.sm)
                        )
                        .buttonStyle(ScaleButtonStyle())
                }
            } else if player.currentTrack == nil {
                EmptyStateView(
                    icon: "music.note",
                    title: "No Track Selected",
                    message: "Select a file from the Library to start playing",
                    iconStyle: AnyShapeStyle(LinearGradient.sonicGradient),
                    iconSize: DisplayFont.stateIcon,
                    spacing: Spacing.lg
                )
            } else if player.isLoadingTrack && player.duration == 0 {
                VStack(spacing: Spacing.lg) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.sonicPrimary)
                        .frame(height: DisplayFont.stateIcon)

                    Text("Loading Track")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextPrimary)
                }
                .accessibilityElement(children: .combine)
            } else {
                ArtworkView(
                    image: player.artwork,
                    side: Sizing.artworkCompact,
                    cornerRadius: Radius.lg,
                    isPlaying: player.isPlaying && player.progress > 0,
                    showsWaveform: true
                )

                ScrollingText(text: player.currentTrack?.title ?? String(localized: "Unknown Track"))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicTextPrimary)
                    .frame(height: Sizing.titleLine)

                // Coarse travel. The wheel is the fine half of the same control (spec §5).
                SonicScrubber(
                    progress: player.progress,
                    duration: player.duration,
                    onSeek: { player.seek(to: $0) }
                )

                HStack {
                    Text(player.currentTimeFormatted ?? "0:00")
                    Spacer()
                    Text(player.durationFormatted ?? "0:00")
                }
                .font(.sonicTimeLabel)
                .foregroundColor(.sonicTextSecondary)
                .monospacedDigit()
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.xl)
    }

    private var wheelZone: some View {
        RotaryWheel(
            hubLabel: player.isPlaying ? "❙❙" : "▶",
            isPlaying: player.isPlaying,
            onCommand: { shell.receive($0) }
        )
        .frame(height: Sizing.wheelZone, alignment: .center)
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
xcodebuild build -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SonicPlayer/Features/Shell/ShellView.swift
git commit -m "feat: ShellView — the wheel canvas, portrait only (#6)"
```

---

## Task 11: Wire it into the app

**Files:**
- Modify: `SonicPlayer/App/AppViewModel.swift`
- Modify: `SonicPlayer/App/AppView.swift:120-121`
- Test: `SonicPlayerTests/ShellWiringTests.swift`

- [ ] **Step 1: Write the failing wiring test**

Create `SonicPlayerTests/ShellWiringTests.swift`:

```swift
import Foundation
import Testing

@testable import SonicPlayer

/// The cross-feature edge, exercised through the composition root — the shape `CLAUDE.md`
/// prescribes for anything wired in `AppViewModel.wire()`.
@Suite(.serialized)
struct ShellWiringTests {

    @MainActor
    @Test func theShellSeeksThePlayer() {
        let app = AppViewModel(
            player: PlayerViewModel(audioPlayer: .test),
            recording: RecordingViewModel(audioRecorder: .test, audioPlayer: .test, fileManager: .test),
            settings: SettingsViewModel(),
            filesRoot: CollectionsViewModel(currentDirectory: nil, fileManager: .test),
            onboarding: nil,
            fileManager: .test
        )
        var sought: TimeInterval?
        app.shell.onSeek = { sought = $0 }
        app.player.duration = 100
        app.player.currentTime = 10

        app.shell.receive(.tick(5))

        #expect(sought == 10.5)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SonicPlayerTests/ShellWiringTests 2>&1 | tail -8
```

Expected: `value of type 'AppViewModel' has no member 'shell'`.

- [ ] **Step 3: Own the shell in `AppViewModel`**

In `SonicPlayer/App/AppViewModel.swift`, in the `// MARK: - Children` block after `let filesRoot: CollectionsViewModel`:

```swift
    /// Holds the *same* player instance, for the same reason `home` does — the shell is a second
    /// face on one playback engine, not a second engine.
    let shell: ShellViewModel
```

In `init(...)`, immediately after `self.home = HomeViewModel(player: player)`:

```swift
        self.shell = ShellViewModel(player: player)
```

- [ ] **Step 4: Wire its out-edges**

In `wire()`, after the `filesRoot` block:

```swift
        // The shell's out-edges. Closures rather than direct calls for the reason every other edge
        // here is: it makes the edge reachable from a test without a view.
        shell.onSeek = { [player] time in player.seek(to: time) }
        shell.onPlayPause = { [player] in player.playPauseTapped() }
        shell.onNextTrack = { [player] in player.nextTrack() }
        shell.onPreviousTrack = { [player] in player.previousTrack() }
        shell.onSpeedBy = { [player] steps in
            let all = PlaybackSpeed.allCases
            guard let index = all.firstIndex(of: player.playbackSpeed) else { return }
            let next = min(max(0, index + steps), all.count - 1)
            player.setPlaybackSpeed(all[next])
        }
        // Volume is `MPVolumeView`'s, which owns the system slider and has no programmatic setter
        // worth having. Left unwired in slice 1 rather than faked — an effect that silently does
        // nothing is better than one that fights the system volume.
```

- [ ] **Step 5: Present it**

In `SonicPlayer/App/AppView.swift`, replace lines 120-121:

```swift
        .sheet(isPresented: $player.isExpanded) {
            PlayerView(player: player)
```

with:

```swift
        .sheet(isPresented: $player.isExpanded) {
            ShellView(shell: app.shell, player: player)
```

`app` is the identifier already in scope — `AppView.swift:7` declares
`@Environment(AppViewModel.self) private var app`, and the recording sheet three lines below uses
`app.recording`. Leave `.presentationDetents` and `.presentationDragIndicator` as they are.

- [ ] **Step 6: Run the whole suite**

```bash
xcodebuild test -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add SonicPlayer/App/AppViewModel.swift SonicPlayer/App/AppView.swift \
        SonicPlayerTests/ShellWiringTests.swift
git commit -m "feat: the wheel canvas replaces the player sheet (#6)"
```

---

## Task 12: Prove it on a device-like target

Everything above is testable without rendering. These three are not, and they are the ones this
codebase has historically got wrong by reasoning.

**Files:** none — this task produces evidence.

- [ ] **Step 1: Check for new magic numbers**

```bash
./scripts/lint-magic-numbers.sh
```

Expected: clean. If it reports the new files, add them to the script's list and resolve every
literal to a token.

- [ ] **Step 2: Verify the ring does not mirror in Arabic**

Run the app in Arabic and confirm that turning the ring clockwise moves playback *forwards*, and
that the four ring targets keep their positions (back at top, previous at leading-as-drawn, next at
trailing-as-drawn, menu at bottom).

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null
xcodebuild -project SonicPlayer.xcodeproj -scheme SonicPlayer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/dd build
xcrun simctl install booted /tmp/dd/Build/Products/Debug-iphonesimulator/SonicPlayer.app
xcrun simctl launch booted com.hasan.sonicplayer -AppleLanguages '(ar)' -AppleLocale ar_SA
```

Expected: clockwise seeks forward, exactly as in English. **If it is mirrored, do not flip a sign —
measure first**, and record the numbers next to the fix the way `ScrubGeometry` and `ScrollingText`
already do. Reasoning about this has produced the wrong answer three times in this repo.

- [ ] **Step 3: Verify VoiceOver reaches the whole wheel without the gesture**

With VoiceOver on, confirm: the hub is announced as Play/Pause and carries a value; a swipe up or
down moves playback by one detent; and Back, Previous, Next and Menu are each reachable and labelled.

- [ ] **Step 4: Verify AX5 does not break the stage**

Set the largest accessibility text size and confirm the artwork, title, scrubber and time labels all
remain visible above the wheel, and that the wheel itself has not moved or resized.

- [ ] **Step 5: Commit any fixes and record the evidence**

**Stage by path, never `git add -A`.** This is a shared checkout and it currently has an unrelated
modification to `SonicPlayer/Clients/AudioPlayerClient.swift` that is not part of this work. Run
`git status --short` first and stage only the files you changed.

```bash
git status --short
git add <the specific files you changed>
git commit -m "fix: RTL, VoiceOver and AX5 corrections from the slice 1 evidence pass (#6)"
```

---

## Done when

- [ ] `project.pbxproj` no longer lists app source files, and a new file compiles without touching it
- [ ] `RotaryTracker` handles the seam, the dead zone, sub-detent residuals and acceleration, each under test
- [ ] `WheelRouter` is a pure table with every slice-1 command × focus pair asserted
- [ ] `ShellViewModel` is drivable from a test with nothing rendered
- [ ] The wheel canvas replaces `PlayerView` in portrait; landscape still falls back to `PlayerView`
- [ ] The stage renders all three states — empty, loading and error — as epic #6 requires
- [ ] Turning the ring seeks by 0.1s per detent, accelerating on a fast spin, with a haptic per detent
- [ ] Clockwise means forward in Arabic, verified by running it rather than by argument
- [ ] VoiceOver can drive the wheel with no rotation gesture
- [ ] `./scripts/lint-magic-numbers.sh` is clean
- [ ] The full suite passes
