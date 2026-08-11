#!/usr/bin/env bash
# Files the 5 child slices of epic #6 and attaches each as a sub-issue.
# Run from anywhere:  bash docs/superpowers/specs/file-epic-6-slices.sh
# Requires: gh authenticated (gh auth status).  Safe to read before running.
set -euo pipefail

REPO="hasansa007/SonicPlayer"
PARENT=6
DOC="docs/superpowers/specs/2026-08-08-epic-6-ui-restructure-decomposition.md"

create() {   # $1 = title, $2 = body  ->  prints created issue number
  gh issue create --repo "$REPO" --label enhancement --title "$1" --body "$2" \
    | grep -oE '[0-9]+$'
}

attach() {   # $1 = child issue number  -> attaches to PARENT via sub_issues API
  local dbid
  dbid=$(gh api "repos/$REPO/issues/$1" -q .id)   # database id, NOT the number
  gh api --method POST "repos/$REPO/issues/$PARENT/sub_issues" -F sub_issue_id="$dbid" >/dev/null
  echo "  attached #$1 (id=$dbid) to #$PARENT"
}

# ---- Slice 1: Player + design-system foundation ----
N1=$(create "UI restructure: Player screen + design-system foundation" "$(cat <<EOF
Part of #$PARENT — UI restructure into a design system. Decomposition: \`$DOC\`.

**This is Slice 1 (walking skeleton): it births the shared foundation the other screens reuse.**

## Goal
Restructure the Player screen onto shared components + design tokens, and in doing so establish
the design-system foundation (tokens + first shared components) with real consumers from line one.

## Scope
- Extract shared components from \`PlayerView.swift\` (520) and \`MiniPlayerView.swift\` (141)
- **Create token set v1** in \`Theme.swift\`: spacing, type scale, elevation, motion (alongside \`ColorPalette\`)
- Design empty / loading / error states for the player
- Verify RTL + all 9 languages on the player
- File any "looks right, acts wrong" defect as its own linked \`bug\`

## Foundation this slice carries (one-time)
- Token set v1 in \`Theme.swift\`
- First shared components (buttons, cards, transport controls)
- **IA ADR**: stay single-screen + mini-player + sheets; revisit a tab split only when #9 (StudyHub listening) adds a second content domain
- Baseline screenshots of every screen (the "before")
- Create \`PROJECT_MAP.md\` (TECH_STACK / SYSTEM_FLOW / ORPHANS & PENDING)

## Done when
- No inline magic numbers remain in the player view files (grep-clean)
- Player layout/spacing come from tokens + shared components
- Empty/loading/error states designed
- RTL + 9 languages verified on the player
- Playback, queue, scrub, mini-player expand/collapse all behave unchanged
EOF
)")
echo "created #$N1  (Player + foundation)"; attach "$N1"

# ---- Slice 2: Files / Collections ----
N2=$(create "UI restructure: Files / Collections screen" "$(cat <<EOF
Part of #$PARENT — UI restructure into a design system. Decomposition: \`$DOC\`.

## Goal
Restructure the file/collection browser onto the shared components + tokens from Slice 1.

## Scope
- Extract shared **Row / List** components from \`CollectionsView.swift\` (477), \`FileItemRow.swift\`, \`MediaFileRowView.swift\` — these get reused by Home (recent) and the Player queue
- Adopt tokens; remove inline layout decisions
- Design empty / loading / error states for the browser
- Verify RTL + 9 languages
- File any interaction defect as its own linked \`bug\`

## Done when
- No inline magic numbers in the Files view files (grep-clean)
- Shared Row/List components in the design system, consumed here
- Empty/loading/error states designed
- RTL + 9 languages verified
- Browse, drill-down, select, move, delete all behave unchanged
EOF
)")
echo "created #$N2  (Files)"; attach "$N2"

# ---- Slice 3: Recording ----
N3=$(create "UI restructure: Recording screen" "$(cat <<EOF
Part of #$PARENT — UI restructure into a design system. Decomposition: \`$DOC\`.

## Goal
Restructure the recording + edit screens onto the shared components + tokens.

## Scope
- Extract components from \`RecordingView.swift\` (551) and \`EditRecordingView.swift\` (364) — the largest combined surface
- Adopt tokens; extract waveform / transport components as needed
- Design empty / loading / error states
- Verify RTL + 9 languages
- File any interaction defect as its own linked \`bug\`

## Done when
- No inline magic numbers in the recording view files (grep-clean)
- Recording/edit layout from tokens + shared components
- Empty/loading/error states designed
- RTL + 9 languages verified
- Record, trim, non-destructive edit, save all behave unchanged
EOF
)")
echo "created #$N3  (Recording)"; attach "$N3"

# ---- Slice 4: Settings ----
N4=$(create "UI restructure: Settings screen" "$(cat <<EOF
Part of #$PARENT — UI restructure into a design system. Decomposition: \`$DOC\`.

## Goal
Restructure Settings / About / Help onto the shared components + tokens.

## Scope
- Extract Form / Section row components from \`SettingsView.swift\` (471), \`AboutView.swift\` (275), \`HelpView.swift\` (332)
- Adopt tokens; remove inline layout
- Design empty / loading / error states where applicable
- Verify RTL + 9 languages
- File any interaction defect as its own linked \`bug\`

## Done when
- No inline magic numbers in the settings view files (grep-clean)
- Settings layout from tokens + shared components
- RTL + 9 languages verified
- All preference toggles/links behave unchanged
EOF
)")
echo "created #$N4  (Settings)"; attach "$N4"

# ---- Slice 5: Home ----
N5=$(create "UI restructure: Home screen" "$(cat <<EOF
Part of #$PARENT — UI restructure into a design system. Decomposition: \`$DOC\`.

## Goal
Restructure Home onto the shared components + tokens and remove the last inline layout.

## Scope
- Home's UI is currently inlined in \`App/AppView.swift\` (empty state, Recent Media list, Collections section, Record FAB) — extract it onto shared components
- Adopt tokens; reuse the Row/List components from Slice 2
- Design empty / loading / error states (the welcome/empty state lives here)
- Verify RTL + 9 languages
- File any interaction defect as its own linked \`bug\`

## Done when
- No inline layout decisions remain in \`AppView.swift\` for Home
- Home built from shared components + tokens
- Empty/loading/error states designed
- RTL + 9 languages verified
- Home browse, recent, collections, record FAB behave unchanged
EOF
)")
echo "created #$N5  (Home)"; attach "$N5"

echo
echo "Done. Children of #$PARENT: #$N1 #$N2 #$N3 #$N4 #$N5"
echo "Tell the assistant these numbers so it can continue on Slice 1 (#$N1)."
