# ADR 0002 — Design-system foundation: tokens now, component bodies on second consumer

**Status:** Accepted
**Date:** 2026-08-08
**Context:** epic #6, threads T2 (shared components) and T3 (tokens) · decided on slice 1 (#47)

---

## Decision

Static-`let` constants on caseless `enum` namespaces in `SonicPlayer/DesignSystem/Tokens.swift`.
**No parallel type scale.** Three components extracted, each with two or more consumers today.
`ColorPalette.swift` and `Theme.swift` stay in `Utilities/` this slice. Enforcement is a
zero-dependency grep.

The governing rule, and the reason most of what follows is a rejection: **nothing is built here
without a real consumer on this branch.** Slice 1 is a walking skeleton — the tokens are born used.

## Rejected — an Environment / `@Entry` theme object

Buys runtime theme swapping the app has never wanted, costs an `@Environment` read at every call
site, and is inconsistent with `ColorPalette`, which has exposed colour as statics on `Color` since
before the epic. Tokens that nothing overrides do not need to be injectable.

## Rejected — a parallel type scale (`Typography.body`, `Typography.caption`, …)

The tempting version of this was written and thrown away. `Font.sonicBody = .subheadline` is a
**name with no value behind it**: it adds a layer to read through, and when a role turns out to be
missing the next author reaches for `.system(size: 15)` rather than adding one — which is precisely
how Dynamic Type gets lost.

SwiftUI's semantic styles already scale, already honour the accessibility sizes, and already have
names. They stay, used directly.

What `Typography.swift` does carry is the two things a bare semantic style cannot express:

1. **Roles that are a style plus a weight or a numeric treatment**, with 2+ consumers —
   `sonicTransportGlyph` (3), `sonicControlGlyph` (6), `sonicTimeLabel` (2).
2. **Fixed point sizes**, which are the real accessibility bug. `.system(size: 80)` is 80 points
   at every accessibility setting. `DisplayFont.stateIcon` read through `@ScaledMetric` is what
   actually fixes it, and slice 1 does that for the player's empty and error states.

The app has **twelve more fixed sizes** — five in `RecordingView`, three in `OnboardingView`, one
each in `AboutView`, `CollectionsView`, `CollectionsSection` and `AppView`. Every one is the same
bug. They are not tokenised here because slices #49–#51 own those screens.

## Rejected — a full component library up front

`SurfaceCard`, `Pill`, `GrabberHandle`, a shared `Row`, a generalised state view. Each has fewer
than two consumers inside slice 1's scope, and building them now repeats the mistake
`ARCHITECTURE.md` already records against `AudioPlaying`: **a declared boundary with nothing behind
it.** They are deferred to the slice where the second consumer actually appears — the shared Row to
#48, `Pill` and `SurfaceCard` to #48/#50.

> **Resolved in #48, and the deferral paid.** `SonicRow` was built in slice 2 with three consumers
> at once — the browser's file rows, Home's recent list, and the player's queue row that slice 1
> left inline. Built in slice 1 it would have had one consumer and been shaped only by the queue;
> built in slice 2 it had to satisfy a selectable row with a date and a collection label as well,
> which is why it carries a `Leading` case for a marker *and* one for a tile. The extra slice of
> waiting is what produced the right seam rather than the first one.
>
> `FileItemRow` — the 111-line row #48 was nominally extracting *from* — turned out to have zero
> consumers and was deleted rather than absorbed.

The three that were built clear the bar:

| Component | Consumers today |
|---|---|
| `IconControlButton` | 7 — skip ±, repeat, shuffle, queue (`PlayerView`); previous, next, play/pause (`MiniPlayerView`) |
| `ArtworkView` | 2 — the player's 280/120/80pt artwork, the mini-player's 40pt thumbnail |
| `SonicScrubber` | 2 — the player's seeking track, the mini-player's display-only hairline |

`IconControlButton` also does something an extraction alone would not: it makes an undersized
control **unavailable**. The mini-player's previous and next buttons were a bare `Image` with no
frame — roughly 20 × 17 points against Apple's documented 44 × 44 minimum. That shape can no
longer be written.

## Rejected — moving `ColorPalette.swift` / `Theme.swift` into `DesignSystem/`

Load-bearing files imported everywhere. Moving them touches the `.xcodeproj` for a cosmetic gain,
in a repo where the project file has explicit file references and is being edited concurrently.
Deferred; worth revisiting at epic end, when the churn lands once instead of five times.

The cost of the deferral is honest and small: the design system is in two places for the duration
of the epic, and `Tokens.swift` says so at the top.

## Rejected — SwiftLint or a build-tool plugin for enforcement

A dependency. The repo has been at zero packages since #20 and the whole of epic #5 was spent
getting there. `scripts/lint-magic-numbers.sh` is a grep that buys most of the value at none of the
cost.

It is **advisory and scoped**: it checks only the screens a slice has already migrated, listed
explicitly in the script, so the gate tightens one screen at a time. Verified to bite rather than
pass vacuously — 0 hits on slice 1's five files, 298 across the un-migrated ones under `--all`.
Wiring it into CI is a candidate for a later slice.

## Consequences

- Slices #48–#51 adopt tokens and add their file to `MIGRATED` in the lint script as they land.
- The two off-scale insets (`barRowInsetV` 10, `chipInsetH` 14) are kept rather than snapped, in
  `Sizing` rather than `Spacing`, because they are insets *within* a component and not gaps
  *between* things. **Slice 1 changes no pixels.** A third off-scale inset is a smell; a fourth
  means the scale is wrong.
- `EmptyStateView` gained `LocalizedStringKey` parameters in this slice (it took `String`, and
  `Text(String)` does not localize — every empty state in the app rendered English in all nine
  languages). It survives alongside the epic until #51 removes its last caller.
