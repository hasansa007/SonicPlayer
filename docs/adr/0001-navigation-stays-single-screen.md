# ADR 0001 — Navigation stays single-screen (mini-player + sheets)

**Status:** Accepted
**Date:** 2026-08-08
**Context:** epic #6, thread T5 (information architecture) · decided on slice 1 (#47)

---

## Question

Epic #6 asks whether "Home / Files / Player / Recording / Settings is still the right split". That
phrasing describes a **tab bar**, and the app does not have one. The decomposition settled this up
front rather than as its own slice, because an IA spike ships nothing to pre prod and every screen
slice after it would otherwise be guessing.

## Decision

Keep Home + a drill-down `NavigationStack`, with a persistent mini-player that expands into a
sheet. Recording and import stay sheets; Settings stays pushed. **No tab bar in this epic.**

## Rejected — a tab bar (Library / Now Playing / Record)

**The app has one content noun.** `CollectionsView` renders both the root and every folder depth;
Home's recent list and the player's queue are two more views of the same local library. A tab bar
earns its place by letting someone move between *parallel* bodies of content without losing their
place in either — there is only one body here.

**Player and Recording are tasks, not places.** The mini-player-expands idiom (Music, Podcasts)
lets browsing continue *during* playback; a "Now Playing" tab throws that away by making playback
somewhere you have to go. A "Record" tab is a category error — recording starts, produces a file,
and ends.

**It would be mostly empty**, and it costs ~49pt of a screen whose primary content is a 280pt
square, underneath a mini-player already occupying the same edge.

**It does not serve this epic.** #6's pain is layout, not findability — the defects that motivated
it are spacing, component and interaction bugs inside screens. Slice 1 found two more of exactly
that kind (#52 RTL scrub, #53 NaN seek) and zero wayfinding problems. A tab bar would also reshape
every remaining slice.

## Revisit trigger

**When #9 (StudyHub listening) adds a genuine second content domain.** A remote course list is not
another view of the local filesystem — it has its own hierarchy, its own empty state and its own
failure modes. At that point a `Local | StudyHub` split earns its place.

This is the condition-based rule `ARCHITECTURE.md` already uses for the Repository layer: add the
structure when two sources answer the same question, not when a feature feels important.

## Consequences

- Slices #48–#51 restructure screens **in place**; none is blocked on this decision.
- `AppViewModel` stays the single composition root with one `NavigationStack` path. No tab
  selection state, no per-tab stacks.
- Home keeps its inlined UI in `App/AppView.swift` until #51 — last, because it consumes every
  component the earlier slices extract.
- If #9 reverses this, the cost is a new root container and a re-parented `AppView`. The feature
  view models and the design-system components are unaffected, because none of them knows what
  contains it.
