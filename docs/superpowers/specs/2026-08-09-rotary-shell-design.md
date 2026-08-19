# Rotary Shell — a wheel-driven, single-screen SonicPlayer

**Status:** DESIGN — approved in brainstorm, not yet filed to GitHub.
**Date:** 2026-08-09
**Relates to:** [#6](https://github.com/hasansa007/SonicPlayer/issues/6) — UI restructure epic (`P1`)
**Supersedes in part:** #51, #55, #57 · **Rescopes:** #49, #50 · **Absorbs:** #65

---

## 1. What this is

SonicPlayer becomes a single canvas driven by a **rotary control that occupies the bottom of the
screen permanently**. Navigation happens in card sheets that rise above the wheel and stack. Home
as a separate screen ceases to exist; Collections, Recordings, Queue and Settings become sheets.

The wheel is a real input device, not a shaped layout: dragging around the ring is tracked by
angle, quantised into discrete detents, and each detent fires a haptic. Touch continues to work
everywhere — the wheel is an additional, more precise path, never the only one.

**The idea this design is built around:** a finger is fast and coarse, a detented wheel is slow and
exact. Every continuous value in the app is driven by both — drag to get near, turn to land.

---

## 2. Decisions taken

| # | Question | Decision |
|---|---|---|
| D1 | How far does the wheel go? | **It becomes the app.** Home is deleted; everything becomes a sheet off the wheel. |
| D2 | Does the wheel rotate? | **Yes.** Angle tracking, detent quantisation, acceleration, haptics. Not a shaped hit area. |
| D3 | What appears on hub press? | **A card sheet** that rises above the wheel and stacks. Not a radial menu. |
| D4 | Does touch still work? | **Yes, everywhere.** Rows stay tappable, sheets flick-scroll, scrubbers stay draggable. |
| D5 | Where does trimming live? | **On the canvas**, driven by finger *and* wheel — coarse by drag, fine by detent. |
| D6 | Where does capturing live? | **Full screen, wheel hidden.** The one stated exception to the furniture rule. |
| D7 | How is wheel output routed? | **Command stream into an explicit focus owner** (§7). |
| D8 | Sequencing | **Straight at the shell**, but ordered so the entry-point flip is the last commit. |

---

## 3. What this deliberately is not

**Not a reproduction of Apple's iPod interface.** App Store Review Guideline 5.2.5 prohibits an app
that "appears confusingly similar to an existing Apple product, interface…". Apple removed *Rewound*
from the App Store in 2020 for recreating the iPod interface.

**The risk is no longer theoretical.** This paragraph used to say "this project ships to TestFlight
today, so the risk is currently theoretical" — and the reason for clearing the guideline anyway was
that retrofitting distance later costs more than starting with it. That bet paid: 3.0.0 (25) passed
review and has been publicly listed since 2026-08-13. What is at stake now is a live listing being
pulled, which is the outcome *Rewound* actually suffered — not an upload being refused.

What creates the distance, concretely:

| Kept | Changed |
|---|---|
| A rotary control with detents — a form that predates the iPod by decades (jog wheels, shuttle rings, tuning dials) | Colourway is the app's teal on charcoal; never silver-and-white polycarbonate |
| A small display area above a control surface | Flat and matte throughout; no chrome bevel, no brushed-metal ring, no gloss |
| Five discrete positions on the ring | **Different button map** — back is a chevron at 12, MENU drops to 6, play/pause moves into the hub |
| | Our own list chrome — not the blue-grey gradient title bar and scroll rail |

**The 6 o'clock label is unresolved and is tracked in §16.** The mockups read `MENU` there, on the
argument that moving it off 12 o'clock is itself the differentiator. That argument is real but thin:
the word is the single most recognisable token of the interface being avoided, and it is free to
change. The safe default is a different word (`BROWSE`, `LIBRARY`) or a glyph.

**Never, anywhere:** the words *iPod*, *Click Wheel*, *Classic Player*, *Retro* or *Nostalgia* in
the UI, the store copy, the release notes, the App Store keyword metadata, the screenshots, the type
names or the commit messages; "looks like an iPod" as marketing; an app icon depicting the device;
Apple product photography.

The three added to that list are not trademarks, which is exactly why they are worth naming. *iPod*
and *Click Wheel* are refused on trademark grounds; *Classic Player*, *Retro* and *Nostalgia* are
refused because they are the words a reviewer reaches for when arguing that an app is trading on a
resemblance. Guideline 5.2.5 turns on whether something "appears confusingly similar" — copy that
invites the comparison is evidence for the reading we are trying to avoid, and none of these words
is load-bearing enough to be worth it.

**Positioning, in the affirmative.** Describe this as **precision dial navigation** and
**gesture-based scrubbing**, framed for modern use — long lectures, podcasts, recordings you have to
land on a moment inside. That is what the control actually is, and it is a claim about capability
rather than about resembling anything.

**The visual rules follow from the same place.** Flat and matte, the app's dark palette and its
gradients; never a white or grey plastic wheel, a chrome bevel, brushed metal or gloss. The table
above is the concrete version and this is the standing rule: no skeuomorphic mimicry of Apple
hardware, in the app or in anything that depicts it.

**Rejected — a radial "bloom" menu around the wheel.** Items pinned to fixed angles build strong
muscle memory and would have been the more distinctive design. Rejected because fixed-angle labels
cannot reflow when a string triples in length at AX5 or in German, and this codebase has spent
#55, #57, #62 and #63 on exactly that class of failure. A card sheet is a real list, so Dynamic
Type, VoiceOver and nine languages work without bespoke work.

**Rejected — wheel-only input.** Coherent, but it needs a bespoke VoiceOver path and punishes anyone
who reaches out and taps a row.

**Rejected — shipping the wheel as a switchable mode alongside today's UI.** Two front ends to keep
working across nine languages, every accessibility size and every future feature, permanently.

---

## 4. The shape

**The governing rule: the wheel is furniture.** It occupies the bottom `Sizing.wheelZone` (200pt)
permanently. Nothing is drawn over it. Sheets rise into the stage above and stop at its edge. The
screen changes; the controls do not.

```
┌─────────────────────────┐
│ strip  (32pt)           │  context + transport status
├─────────────────────────┤
│                         │
│ stage                   │  Now Playing, or a sheet stack
│ (~256pt on a 6.1")      │
│                         │
├─────────────────────────┤
│ wheel zone (200pt)      │  never occluded — except D6
└─────────────────────────┘
```

**The one exception (D6):** while capturing audio, the recorder takes the full canvas and the wheel
is hidden. Capture is a mode of the app rather than a screen in it. This exception is stated here
so it is a decision rather than a drift.

**Ring positions.** Back `‹` at 12 · previous at 9 · next at 3 · the menu label at 6 (wording open,
§16) · play-pause (or the contextual action) in the hub. The hub's label is contextual: `❙❙` at rest, `OPEN` in a sheet,
`IN`/`OUT` in the trim editor, `■` while capturing.

**Cost accepted:** ~22% of the screen is spent permanently. Artwork drops from `Sizing.artworkFull`
(280) to ~150. At AX5 the sheet shows two or three rows, which is acceptable because scrolling it is
the wheel's job.

---

## 5. Interaction model

**Coarse by finger, fine by wheel.** This is the rule that makes both inputs worth having, and it
applies to every continuous value:

| Value | Coarse | Fine |
|---|---|---|
| Playback position | drag `SonicScrubber` | wheel, detent = 0.1s |
| Trim in/out point | drag the handle on the waveform | wheel, detent = 0.1s |
| Volume, speed | tap the control | wheel while that focus is active |
| List position | flick-scroll the sheet | wheel, detent = one row |

**How focus moves between seek, volume and speed:** touching a control claims the wheel. Tapping the
volume or speed control sets `WheelFocus` to it and raises the HUD pill; focus reverts to `.seek`
after `Motion.hudFade` elapses without a turn, or immediately when the scrubber is touched. There is
no mode that persists invisibly — the pill is on screen exactly while a non-default focus is held.

Consequences that must hold:

- **Both inputs write through one clamp**, so they can never disagree. Trim uses a `TrimBounds`
  type enforcing `in ≤ out − minLength`, the way `ScrubClamp` already guards seeking.
- **Snap tolerance scales with the input.** A finger snaps to a marker within a few points; the
  wheel snaps within one detent. Same markers, different tolerance, because "close enough" means
  something different per gesture.

**`SonicScrubber` survives.** It is the coarse half of the pair on Now Playing, not something the
wheel replaces.

**Transient HUD.** Turning the wheel raises a small pill stating the value being changed
(`SEEK 25:38`), which fades on release. Discrete choices use the sheet; continuous ones use the pill.

### Tuning constants

Settled against an interactive prototype — [`2026-08-09-rotary-trim-prototype.html`](./2026-08-09-rotary-trim-prototype.html),
which runs this exact algorithm in a browser — and written into `RotaryTracker` as named constants:

| Constant | Value | Note |
|---|---|---|
| Detent arc | 12° | 30 detents per revolution |
| Dead-zone radius | 34pt | Below this the angle is numerically unstable and sprays ticks |
| Detent granularity | 0.1s fine · one row in a list | Chosen by focus, not by the user |
| Acceleration | ×1 / ×2 / ×5 / ×15 / ×40 | Stepped on detents-per-220ms |

**These are prototype-derived and must be re-tuned on a device.** A browser with a mouse is not a
thumb on glass, and the haptic — which is most of the feel — is absent there entirely.

---

## 6. The recorder

The two halves want opposite things from the wheel, so they get opposite treatments.

**Capture — full screen, wheel hidden (D6).** Large live waveform, large stop target, **tap anywhere
to drop a marker**. The wheel contributes nothing here; a large tap area for markers is strictly
better than one small target aimed at while listening. At AX5 the full-screen waveform stays legible
where a 200pt-shorter stage would reduce it to texture — this was the deciding factor.

**Trim — on the canvas, wheel visible.** Drag a handle for coarse travel; turn for the last few
frames. One detent is 0.1s. Dragging the same 40-minute file across a ~357pt-wide waveform on a 6.1"
phone is about **6.7 seconds per point** — roughly 70× coarser than a detent, and no amount of care
closes that gap with a fingertip. Markers dropped during capture become the points both inputs snap
to.

**Markers are what make the wheel earn its place in the recorder.** They are new behaviour, and are
in scope: capture writes timestamps; the editor renders and snaps to them.

---

## 7. Architecture

Layering follows `ARCHITECTURE.md`. No new dependency — CoreHaptics ships with iOS.

```
touch → RotaryWheel (view)
      → RotaryTracker      Domain   angle → detent ticks
      → WheelCommand       Domain   the vocabulary
      → ShellViewModel.receive(_:)
      → WheelRouter        Domain   (command, focus, stack) → [ShellEffect]
      → applied to PlayerViewModel · HapticsClient · the menu stack
```

### `Domain/` — pure Foundation, no framework, no I/O

| Type | Responsibility |
|---|---|
| `RotaryTracker` | Touch points → detent ticks. Owns **the feel**, and is the only place it lives. |
| `WheelCommand` | `.tick(Int)` · `.select` · `.back` · `.menu` · `.transport(.previous/.next/.playPause)` |
| `WheelFocus` | `.nowPlaying(.seek/.volume/.speed)` · `.menu(depth:)` · `.trim(.in/.out)` |
| `MenuLevel` | Title, items, highlighted index. The stack is `[MenuLevel]`. |
| `WheelRouter` | `(WheelCommand, WheelFocus, [MenuLevel]) -> [ShellEffect]`. Pure, exhaustively testable. |
| `DetentFeedback` | Which haptic fires, expressed as data. |
| `TrimBounds` | The single clamp both trim inputs write through. |

`RotaryTracker` has four decisions that are each a bug if wrong:

1. **Shortest-arc delta** — crossing the 0°/360° seam must yield ±1 detent, not ∓29.
2. **Dead zone** — touches within 34pt of centre are ignored; the angle there is unstable.
3. **Residual accumulator** — slow drags must not drop sub-detent fractions.
4. **Acceleration** — a fast spin must cover a long list without changing the fine step.

**Reused unchanged:** `QueueMath` (track stepping) · `ScrubGeometry` (drag-to-position) ·
`SonicRow` (sheet rows — its fourth consumer) · `SonicScrubber` (the coarse half of the pair).

**Extended, not reused as-is: `ScrubClamp`.** An earlier draft of this spec said it already provided
seek bounds. It does not — it is the *recording editor's* clamp, and both its functions are built
around a fixed `interval: TimeInterval = 15`. It gains one bounds function,
`position(_:duration:)`, because "what are the bounds of a scrub position" should have exactly one
answer in this codebase and that type is already where the answer lives.

### `Clients/HapticsClient`

Struct of closures with `.live` and `.test`, matching the existing five. `.live` wraps
`CHHapticEngine` and must handle the two things that make CoreHaptics awkward in practice: the
engine stops when the app backgrounds and needs restarting, and it resets after a media-server
crash. Hardware reporting `supportsHaptics == false` falls back to `UIImpactFeedbackGenerator`.

### `DesignSystem/Components/`

`RotaryWheel` — the ring, its five tap targets, and the lit arc. Emits `WheelCommand` through a
closure and **owns no app state**. `WheelHUD` — the transient pill.

### `Features/Shell/`

`ShellViewModel` applies effects and owns focus + menu stack. `ShellView` composes strip, stage and
wheel zone. `MenuSheet` renders the stack.

**Why `WheelRouter` is its own type rather than a `switch` in the view model:** it is the piece that
grows — every new focus and menu level adds a case. `PlayerViewModel` reached 633 lines by absorbing
exactly this kind of growth. As a pure function it is a table that can be tested exhaustively with
nothing rendered.

---

## 8. RTL — measured, not argued

This repo has twice filed a bug on plausible reasoning about SwiftUI's RTL behaviour and twice been
wrong (#54, #63). The relevant measurements already exist and are recorded in
`Domain/ScrubGeometry.swift:23–33`:

- **A `DragGesture`'s `location.x` is NOT mirrored under RTL.** Measured on a physical iPhone in
  Arabic: touching the far left of a 234pt track reported `x=3` in both directions.
- **`.offset(x:)` IS mirrored** (measured separately in #54).
- **Layout is mirrored** — a leading-edge fill grows from the right in Arabic.

**Consequence for the wheel:** `atan2(dy, dx)` over unmirrored gesture coordinates is a *physical*
angle, identical in every language. `RotaryTracker` therefore needs **no RTL handling at all**, and
adding some would be the third instance of the same bug.

**The rendered ring is not reasoned about.** Whether a rotation transform mirrors is precisely the
unmeasured assumption that produced #54 and #63. Instead the wheel zone is pinned with
`.environment(\.layoutDirection, .leftToRight)`, exactly as `PlayerView.swift:319` and
`MiniPlayerView.swift:53` already pin transport — so the question cannot arise.

**The rule: the wheel zone is LTR; the stage mirrors.** Two rules on one screen, both correct.
Written down here so that a future reader does not "fix" one of them.

---

## 9. Accessibility

| Surface | Treatment |
|---|---|
| The ring | One `.accessibilityElement` with the `.isAdjustable` trait. `accessibilityIncrement()` / `accessibilityDecrement()` each emit `.tick(±1)`, so a VoiceOver swipe is one detent — full precision, no gesture required. `accessibilityValue` carries the live value, so it is spoken on change without announcement spam. |
| The five targets | Separate labelled elements: Back, Previous, Next, Menu, and the contextual hub action. |
| Arc, nubs, thumb | `accessibilityHidden(true)` — decorative. |
| Sheets | A real list. VoiceOver, Dynamic Type and nine languages work without bespoke code. |
| The wheel's size | **Does not scale.** It is a physical control at a fixed `Sizing.wheelDiameter`. Everything above it scales normally. |

---

## 10. States

Epic #6 requires designed empty, loading and error states per screen.

| Screen | Empty | Loading | Error |
|---|---|---|---|
| Sheet | "Nothing here yet" | row skeletons | **#65 lands here** |
| Now Playing | reuse `PlayerView`'s three | | |
| Capture | — | — | microphone permission denied |

**#65 is absorbed rather than inherited.** It reports a refused folder showing the user two
200-character filesystem paths; a narrow sheet makes that strictly worse, so the sheet's error state
must be designed against that bug and #65 closes with this work.

---

## 11. Tokens

New entries in `DesignSystem/Tokens.swift`, because `scripts/lint-magic-numbers.sh` will otherwise
catch them: `Sizing.wheelDiameter` · `Sizing.wheelHub` · `Sizing.wheelZone` · `Sizing.deadZone` ·
`Radius.sheet` · `Motion.detent` · `Motion.hudFade`.

Per ADR 0002, no parallel type scale is added. Ring labels are SF Symbols or semantic styles used
directly.

---

## 12. Testing

Swift Testing only, zero dependencies, `.test` clients — per `CLAUDE.md`.

| Suite | Covers |
|---|---|
| `RotaryTrackerTests` | Seam crossing (359°→1° is **+1**, not −29) · dead zone · residual accumulation across slow drags · acceleration thresholds |
| `WheelRouterTests` | Table-driven: command × focus → effects |
| `ShellViewModelTests` | Drives the real app with `.test` clients, nothing rendered |
| `AppViewModelTests` | The cross-feature edge: a sheet selects a file → the player loads it |
| `DetentFeedbackTests` | Which haptic fires, as data — no device needed |
| `TrimBoundsTests` | The shared clamp both trim inputs write through |

Suites touching `UserDefaults` or the shared `AudioPlayerManager` need `@Suite(.serialized)`.

**Stated as untestable:** whether it *feels* right. The prototype is the tuning surface; the
constants it produced (§5) are named constants, re-tuned on device.

---

## 13. Slicing and demolition order

Sequencing is "straight at the shell" (D8), ordered so the branch stays revertible by one line until
the end.

| Slice | Content | Deletes anything? |
|---|---|---|
| 1 | `Domain/` types · `HapticsClient` · `RotaryWheel` · tokens | No |
| 2 | `ShellViewModel` · `ShellView` · `MenuSheet`, built **alongside** Home | No |
| 3 | Trim editor onto the canvas (finger + wheel) | Rewrites `EditRecordingView` |
| 4 | Capture as a full-screen sheet | Rescopes `RecordingView` |
| 5 | **Flip `AppView`'s entry point — one line** | The commit that commits |
| 6 | Delete Home and the superseded player chrome; close issues | Yes |

Each slice must be independently shippable to pre-prod, per the decomposition rule in the epic #6
proposal.

---

## 14. Issue impact

| Issue | Effect |
|---|---|
| #51 UI restructure: Home | **Superseded** — Home ceases to exist. Close with a pointer here. |
| #50 UI restructure: Settings | **Rescoped** — Settings becomes a sheet. |
| #49 UI restructure: Recording | **Rescoped to capture only.** The editor half is rewritten by slice 3. |
| #55 Player portrait at AX5 | Superseded by the new layout. |
| #57 Home recent list at AX5 | Superseded with Home. |
| #65 Refused folder shows two long paths | **Absorbed** — fixed as the sheet's error state (§10). |
| #54 · #62 · #63 | Precedent to preserve. Must not regress; §8 depends on their measurements. |

---

## 15. Deliberately deferred

- **Landscape has no design yet.** 200pt of wheel in a 393pt-tall canvas does not work, so landscape
  needs the wheel moved to one side — a structurally different layout, not a rotation of this one.
  `PlayerView.landscapeLayout` is replaced by something not yet designed. **This must be answered
  before slice 2 ships**, since `ShellView` owns the layout decision.
- **iPad.** Out of scope; the shape assumes a phone.
- **StudyHub (#7, #8, #9).** Untouched. This ships on the local-file app.
- **App icon and store screenshots.** Out of scope, as in epic #6 — but §3's "never" list applies to
  them when they are done.

---

## 16. Open questions for implementation

**What word sits at 6 o'clock?** The mockups read `MENU`. Moving it from 12 to 6 is a genuine
differentiator, but the word itself is the most recognisable single token of the interface §3 sets
out to avoid, and replacing it costs nothing. Decide before slice 2 renders the ring; `BROWSE`,
`LIBRARY` or a glyph are all free.

**What does the wheel do at rest on Now Playing — seek, or step the queue?** §5 assumes seek, and
`.nowPlaying(.seek)` is the default focus. If stepping tracks turns out to be the more common intent
in use, the default focus changes and nothing else does — which is the point of routing through
`WheelFocus` rather than hard-wiring the gesture.
