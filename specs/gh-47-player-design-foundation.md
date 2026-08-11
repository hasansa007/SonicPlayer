# gh-47 — Player screen + design-system foundation

Issue | Type | Tier | Branch | Base
--- | --- | --- | --- | ---
[#47](https://github.com/hasansa007/SonicPlayer/issues/47) (child of epic [#6](https://github.com/hasansa007/SonicPlayer/issues/6)) | Enhancement | **Deep** | `gh-47-player-design-foundation` | `feat`

## Understanding

Slice 1 of the #6 UI-restructure epic. It restructures the **Player** screen onto shared
components + design tokens and, in doing so, **births the design-system foundation** the other four
screens (Files, Recording, Settings, Home) will reuse. The foundation is created with the Player as
its first and only consumer — no speculative tokens or components.

The epic's real pain is that layout/spacing/motion decisions are inlined per-screen. A grep of the
Player files confirms the values already cluster on an implicit 4-pt grid with real drift; this
slice makes that grid explicit and adopts it.

## Approach (settled in Phase 6)

- **Tokens = static-`let` constants on caseless `enum` namespaces** (`Spacing.md`, `Radius.lg`,
  `Sizing.playButton`, `Elevation.control`, `Motion.panel`). Same shape as `ColorPalette`. No
  Environment/`@Entry` — nothing overrides tokens at runtime.
- **No parallel type scale.** SwiftUI semantic fonts (`.title3`, `.subheadline`, …) already scale
  with Dynamic Type and stay. Only the ~7 fixed `.system(size:)` display sizes get tokens, wrapped
  in `@ScaledMetric` — which *fixes* a real Dynamic-Type accessibility gap (the player/recording
  numerals don't currently scale).
- **Slice-1 components** (each has 2+ consumers within Player + MiniPlayer today):
  - `IconControlButton` — the transport/tool icon button (skip/repeat/shuffle/queue + mini-player
    transport). Enforces the 44pt tap target several current buttons miss.
  - `ArtworkView` — image-or-gradient-fallback tile (full player + mini-player thumbnail).
  - `SonicScrubber` — the progress track + optional seek gesture (player scrubber + mini progress).
    Calls the existing `Domain/ScrubClamp`, does not re-derive clamping.
  - **Deferred:** `SurfaceCard`, `Pill` — their second consumer lands in the Files/Settings slices,
    so they are built there, not here.
- **File structure:** new `SonicPlayer/DesignSystem/` folder for the new files. `ColorPalette.swift`
  and `Theme.swift` **stay in `Utilities/`** this slice (moving load-bearing files mid-epic, with a
  concurrent agent editing the project, is churn/risk that doesn't pay for itself now). Recorded as
  a deliberate deferral in the ADR.
- **Enforcement:** a zero-dependency `scripts/lint-magic-numbers.sh` grep + a line in CLAUDE.md.
  Advisory (local) this slice; wiring it into CI is a candidate for a later slice. No SwiftLint
  (would break the zero-dependency rule).

## Success criteria

- `PlayerView.swift` and `MiniPlayerView.swift` contain **no inline layout magic numbers** for
  spacing / corner radius / control size / shadow / animation — all resolve to a token. Verified by
  `scripts/lint-magic-numbers.sh` returning only the documented exemptions.
- The three components are consumed by both the full player and the mini-player (proving reuse).
- Player behaviour is **unchanged**: play/pause, skip, scrub-to-seek, speed, repeat/shuffle, queue
  reveal, mini-player expand/collapse, artwork/waveform display.
- Empty/loading/error states for the player are designed (not just the happy path).
- RTL + all 9 languages render correctly on the player.
- `@ScaledMetric` display sizes scale under large Dynamic Type without clipping.
- The full test suite passes; a build on the iPhone 17 simulator succeeds.

## File Map

**New — `SonicPlayer/DesignSystem/`:**
- `Tokens.swift` — `Spacing`, `Radius`, `Sizing`, `Elevation` (+ `Shadow` struct & `.sonicShadow`), `Motion` namespaces.
- `Typography.swift` — `Font.sonic*` semantic roles + `DisplayFont` constants for the fixed sizes.
- `Components/IconControlButton.swift`
- `Components/ArtworkView.swift`
- `Components/SonicScrubber.swift`

**Modified:**
- `SonicPlayer/Features/Player/PlayerView.swift` — adopt tokens + the three components; remove inline literals.
- `SonicPlayer/Features/Player/MiniPlayerView.swift` — same, as the second consumer.

**New — docs / tooling:**
- `docs/adr/0001-navigation-stays-single-screen.md` — IA decision (see ADR below).
- `docs/adr/0002-design-system-foundation.md` — token/component shape + rejected alternatives.
- `scripts/lint-magic-numbers.sh` — advisory grep gate.
- `PROJECT_MAP.md` — created (the repo has none today).
- Baseline screenshots of every screen → `artifacts/baseline/` (the epic's "before").

**Project:** new files added to the app target via xcode-tools (`XcodeWrite`) — the app target uses
explicit file references, not a synchronized group, so membership is not automatic.

## Implementation Plan (granular)

1. `DesignSystem/Tokens.swift` — declare `Spacing` (4/8/12/16/20/24/40), `Radius` (3/4/8/12/16),
   `Sizing` (tap 44 / secondary 56 / primary 64 / thumbnail 40), `Elevation` (artwork / control /
   bar shadows + `.sonicShadow`), `Motion` (scrub / miniProgress / panel / press). Grounded in the
   grep counts.
2. `DesignSystem/Typography.swift` — `Font.sonic*` roles aliasing semantic styles; `DisplayFont`
   constants for the fixed display numerals.
3. `Components/IconControlButton.swift` — build + `#Preview` with production-shaped fixtures.
4. `Components/ArtworkView.swift` — build + `#Preview` (image + gradient-fallback states).
5. `Components/SonicScrubber.swift` — build (display-only + seek variants), call `ScrubClamp`, + `#Preview`.
6. Refactor `MiniPlayerView.swift` onto the three components + tokens (smaller surface first).
7. Refactor `PlayerView.swift` onto tokens + components; convert fixed numerals to `@ScaledMetric`.
8. Player empty/loading/error states designed via `EmptyStateView` + token spacing.
9. `scripts/lint-magic-numbers.sh` + add the enforcement line to CLAUDE.md; run it, drive to the documented exemptions.
10. Create `PROJECT_MAP.md` (TECH_STACK / SYSTEM_FLOW / ORPHANS & PENDING) + capture baseline screenshots.
11. Write ADR 0001 (IA) and 0002 (design system).

## ADR content (captured now while the reasoning is fresh — Phase 12 copies these)

### ADR 0001 — Navigation stays single-screen (mini-player + sheets)
**Decision:** keep Home + drill-down `NavigationStack` + a persistent mini-player that expands to a
sheet; Recording/Import as sheets; Settings pushed. Do **not** introduce a tab bar in this epic.
**Rejected — tab bar (Library / Now Playing / Record):** the app has one content noun (the library;
`CollectionsView` renders both root and folder depth). Player and Recording are tasks, not places —
the mini-player-expands idiom (Music/Podcasts) lets browsing continue during playback, which a
"Now Playing tab" throws away; a "Record tab" is a category error. A tab bar here would be mostly
empty. It also doesn't serve the epic (whose pain is layout, not findability) and would reshape
every slice.
**Revisit trigger:** when #9 (StudyHub listening) adds a genuine second content domain (courses vs
local files), a `Local | StudyHub` split earns its place — condition-based, per ARCHITECTURE.md.

### ADR 0002 — Design-system foundation: tokens now, component bodies on second-consumer
**Decision:** static-`let` enum tokens; no parallel type scale; three components extracted; new
`DesignSystem/` folder; `ColorPalette`/`Theme` not moved this slice.
**Rejected — Environment/`@Entry` theme object:** buys runtime theme swapping the app never needs;
costs a `@Environment` read at every call site; inconsistent with the existing static color layer.
**Rejected — full component library up front (`SurfaceCard`, `Pill`, `GrabberHandle`, relocate
existing shared views):** most have <2 consumers in slice-1 scope; building them now repeats the
`AudioPlaying` mistake (a declared boundary with nothing behind it). Deferred to the slice where the
second consumer actually appears.
**Rejected — move `ColorPalette.swift`/`Theme.swift` into `DesignSystem/` now:** load-bearing files
imported everywhere; moving them touches the `.xcodeproj` while a concurrent agent edits it, for a
cosmetic gain. Deferred; may be revisited at epic end.
**Rejected — parallel type scale (`Typography.body` etc.):** re-wrapping semantic fonts adds names
without values and *breaks* Dynamic Type. Only fixed display sizes are tokenized.
**Rejected — SwiftLint / build-tool plugin for enforcement:** a dependency; the repo is
deliberately zero-dependency. A CI/local grep buys ~90% at 0% dependency cost.

## Effort Estimate
~6–9 hours (foundation + two-view refactor + states + a11y + evidence).

## Testing Checklist
- Unit: existing `PlayerViewModelTests`, `ScrubClampTests`, `QueueMathTests` still green (behaviour unchanged).
- Build: iPhone 17 simulator succeeds.
- Manual/agent (simulator): play/pause, skip ±, scrub-to-seek lands at the right time, speed cycle,
  repeat/shuffle toggles, queue reveal animation, mini↔full transition, artwork + waveform render,
  empty/loading/error states, RTL layout, largest Dynamic Type size (no clipping).
- Falsification row: scrubbing to 0 and to end must not overrun (ScrubClamp) — must still hold.
- `scripts/lint-magic-numbers.sh` returns only documented exemptions.

## PROJECT_MAP.md Impact
Created this slice. Adds `DesignSystem/` to TECH_STACK; records the token/component layer in
SYSTEM_FLOW; lists deferred items (SurfaceCard/Pill, ColorPalette/Theme relocation, CI lint wiring)
under ORPHANS & PENDING.

## PR Notes
Foundation + Player only. Tokens are born used (Player is a real consumer). Two ADRs included.
`ColorPalette`/`Theme` intentionally not moved — see ADR 0002. Behaviour is unchanged; the diff is
structural.
