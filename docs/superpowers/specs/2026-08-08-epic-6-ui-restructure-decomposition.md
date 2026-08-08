# Epic #6 — UI Restructure into a Design System · Decomposition Proposal

**Status:** DRAFT — for decision. Nothing filed to GitHub yet.
**Date:** 2026-08-08
**Parent:** [#6](https://github.com/hasansa007/SonicPlayer/issues/6) — `enhancement, epic, P1`

---

## 1. What the epic actually asks for

Restructure the UI into a real, *enforced* design system so a screen that looks finished
also behaves that way. Seven in-scope threads from the issue body:

| # | Thread |
|---|---|
| T1 | Baseline capture of the current UI, screen by screen (the documented "before") |
| T2 | Extract shared components out of the large per-feature view files |
| T3 | Design tokens — spacing, type scale, elevation, motion — **extending `Theme.swift`** |
| T4 | Close the look-vs-behave gap (interaction defects) |
| T5 | Information architecture — is Home/Files/Player/Recording/Settings the right split? |
| T6 | Empty, loading, error states as first-class designs |
| T7 | RTL + all 9 shipped languages verified as part of the work |

**Done when** (from the issue): no screen uses pre-redesign spacing/type; a grep finds no new
magic numbers; per-feature view files no longer carry their own layout decisions; every linked
behaviour defect is closed by its own issue; every screen has designed empty/loading/error
states; all 9 languages render correctly incl. RTL; browse/play/record/trim/move/collections
all work unchanged.

Blocker `#5` (TCA→MVVM migration) is **done**, so the epic is unblocked.

---

## 2. Current state (facts, not opinions)

| Thing | State |
|---|---|
| `ColorPalette.swift` | Mature — colors, gradients, `.dynamic(light:dark:)` dark-mode. **Keep as-is.** |
| `Theme.swift` | **Thin** — only gradient helpers + one `ScaleButtonStyle`. No spacing/type/elevation/motion tokens. This is the file T3 extends. |
| `EmptyStateView` | Exists (empty-state seed). No loading/error equivalents. |
| Big view files carrying inline layout | `RecordingView` 551 · `PlayerView` 520 · `CollectionsView` 477 · `SettingsView` 471 · `EditRecordingView` 364 |
| Navigation model | Single screen: Home + sheets (player/recording/import), Settings pushed. No tab bar. |
| `PROJECT_MAP.md` | **Absent** — to be created during the first slice. |

---

## 3. The governing rule

Every child slice becomes its own **branch → PR → merge to pre-prod**. The dev pipeline's hard
rule for decomposition:

> Each slice must be **independently shippable** — able to reach pre-prod on its own, with a real
> user-visible change and no dead code / stubs.

This rule is what the three options below differ on.

---

## 4. Threads that are NOT their own slices (all options agree)

- **T4 — interaction defects** → the epic says each gets its **own linked `bug` issue**, closed
  on its own. So they are filed as bugs (linked to #6) *as each screen slice surfaces them*, not
  bundled into the epic. (#41 is already one such bug.)
- **T6 states + T7 RTL/i18n** → folded **into each per-screen slice** (verified screen-by-screen),
  not done as a late horizontal sweep.

---

## 5. The three candidate shapes

### Option A — 7 slices: dedicated foundation + IA spike, then 5 screens

```
1. Foundation:  tokens in Theme.swift + baseline screenshots     (no screen changed)
2. IA spike:    review nav model → ADR recommendation            (no shippable code)
3. Player   4. Files   5. Recording   6. Settings   7. Home
```

- 👍 Clean separation; tokens "exist" before any screen consumes them.
- 👎 **Slice 1 ships dead code** — tokens with zero consumers violate "every line serves the user
  journey / no stubs" (same smell `ARCHITECTURE.md` flags for `AudioPlaying`).
- 👎 **Slice 2 ships nothing to pre-prod** — a pure-ADR spike is a *decision*, not a release; it
  fails the independently-shippable rule.

### Option B — 5 slices: walking skeleton (RECOMMENDED)

```
IA decision made up front, written as an ADR committed on Slice 1's branch (no separate issue).
1. Player   ← births the tokens + shared components it needs; captures baseline as its "before"
2. Files    ← extends + reuses the foundation; row/list components extracted here
3. Recording
4. Settings
5. Home     ← also tidies the inlined Home UI in App/AppView.swift
```

- 👍 Every slice ships a real, restructured, user-visible screen — no dead code.
- 👍 The design system **accretes with real consumers** (tokens are born used, not speculative).
- 👍 IA call is made once, up front, and lives as an ADR next to a real diff.
- 👎 Slice 1 is the heaviest (it carries the first tokens + first components + Player itself).
- 👎 Foundation choices made in Slice 1 may need small revisions when Slice 2/3 reveal gaps
  (normal for a design system; cheap because each is a small PR).

### Option C — 6 slices: thin-but-live foundation, then 5 screens

```
1. Foundation-live:  tokens applied to a REAL small shared surface
                     (EmptyStateView + MiniPlayerView) so it is not dead code
2. Player   3. Files   4. Recording   5. Settings   6. Home
```

- 👍 Keeps a dedicated foundation slice **without** shipping dead code (it has 2 real consumers).
- 👍 Slice 1 is small and low-risk; de-risks the token API before the big screens.
- 👎 Slightly artificial — EmptyStateView/MiniPlayer are chosen as consumers to justify the slice.
- 👎 One more PR than Option B for roughly the same outcome.

---

## 6. Recommended option: **B**, with per-slice detail

Order confirmed by you: **Player first** (richest visual surface stress-tests the tokens).

| Slice | Title (draft) | Ships | Primary files | Foundation work it carries |
|---|---|---|---|---|
| 1 | UI restructure: Player screen + design-system foundation | Restructured Player + mini-player; token set v1; IA ADR; baseline screenshots; `PROJECT_MAP.md` created | `PlayerView` (520), `MiniPlayerView` (141), `Theme.swift`, new component files | **Creates** spacing/type/elevation/motion tokens + first shared components (buttons, cards, controls) |
| 2 | UI restructure: Files / Collections screen | Restructured browser | `CollectionsView` (477), `FileItemRow`, `MediaFileRowView` | **Extracts** shared Row / List components (reused by Home + Player queue) |
| 3 | UI restructure: Recording screen | Restructured record + edit | `RecordingView` (551), `EditRecordingView` (364) | Reuses foundation; adds waveform/transport components as needed |
| 4 | UI restructure: Settings screen | Restructured settings | `SettingsView` (471), `AboutView` (275), `HelpView` (332) | Reuses foundation; extracts Form/Section row components |
| 5 | UI restructure: Home screen | Restructured Home | inlined UI in `App/AppView.swift` | Reuses everything; removes the last inline layout |

**Each per-screen slice includes, for that screen only:** extract components → adopt tokens →
design empty/loading/error states → verify RTL + 9 languages → file any behave-defect as a linked
`bug`.

**Epic parent (#6)** takes no branch and stays open until slices 1–5 close.

---

## 7. Open questions before filing

1. **Pick the option:** A (7), **B (5, recommended)**, or C (6)?
2. **Labels for children:** reuse `enhancement`? add a `P2`/`P3`? (parent is P1). — I'll propose
   `enhancement` + inherit no priority unless you want one.
3. **IA (T5):** under Option B I make the stay-single-screen-vs-tabs recommendation up front as an
   ADR on Slice 1. Are you OK deciding it there, or do you want the recommendation in *this*
   conversation before Slice 1 starts?

---

## 8. What happens after you decide

1. File the chosen slices as child issues **attached to #6 via the sub-issues API** (node id, not
   number — checkbox lines are invisible to the board).
2. Continue this `/dev` run on **Slice 1 (Player + foundation)** — cut branch `gh-<N>-...`, then
   Phase 6/7 (architecture + plan) for that slice only.
