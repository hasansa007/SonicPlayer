#!/bin/bash
# lint-magic-numbers.sh — the design system's enforcement gate (epic #6, #47).
#
# Flags inline layout literals in view files: spacing, padding, corner radius, control size,
# shadow and animation values that should resolve to a token in DesignSystem/Tokens.swift.
#
# Zero dependencies, on purpose. SwiftLint would catch more and cost a package, and the repo has
# been at zero packages since #20 — see ARCHITECTURE.md. A grep buys most of the value at none of
# the cost. Advisory locally; wiring it into CI is a candidate for a later slice.
#
#   ./scripts/lint-magic-numbers.sh              # only the screens already migrated
#   ./scripts/lint-magic-numbers.sh --all        # every view file, including un-migrated ones
#
# Exit 0 = clean. Exit 1 = at least one un-tokenised literal.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

# Screens that have been through the epic. Each slice appends its files here as it lands, so the
# gate tightens one screen at a time instead of failing on four screens nobody has touched yet.
MIGRATED=(
  "SonicPlayer/Features/Player/PlayerView.swift"
  "SonicPlayer/Features/Player/MiniPlayerView.swift"
  "SonicPlayer/DesignSystem/Components/IconControlButton.swift"
  "SonicPlayer/DesignSystem/Components/ArtworkView.swift"
  "SonicPlayer/DesignSystem/Components/SonicScrubber.swift"
)

if [[ "${1:-}" == "--all" ]]; then
  TARGETS=()
  while IFS= read -r f; do TARGETS+=("$f"); done < <(
    find SonicPlayer -name "*View*.swift" -o -name "*Section.swift" | sort
  )
  echo "Scanning every view file (--all). Un-migrated screens belong to slices #48–#51."
else
  TARGETS=("${MIGRATED[@]}")
fi

total=0
status=0

for file in "${TARGETS[@]}"; do
  [[ -f "$file" ]] || continue

  hits=$(awk '
    # Skip #Preview bodies — fixture values are the point of a preview, not a layout decision.
    /^[[:space:]]*#Preview/ { inpreview = 1; depth = 0 }
    inpreview {
      n = gsub(/{/, "{"); depth += n
      n = gsub(/}/, "}"); depth -= n
      if (depth <= 0 && /}/) inpreview = 0
      next
    }

    { line = $0 }

    # Drop trailing comments and skip whole-line comments, so prose about a number is not a hit.
    { sub(/\/\/.*$/, "", line) }
    line ~ /^[[:space:]]*$/ { next }

    # An explicit opt-out, for a value that genuinely belongs at the call site.
    $0 ~ /lint:allow-literal/ { next }

    # Declarations are where tokens are *defined*; they are not call sites.
    line ~ /^[[:space:]]*(static[[:space:]]+)?(var|let)[[:space:]]/ { next }

    {
      # A layout keyword immediately followed by a number is the thing being looked for.
      # 0 and 1 are exempt: absence and identity carry their own meaning.
      pattern = "(\\.padding\\(|\\.padding\\([.a-zA-Z]+, *|spacing: *|cornerRadius: *|" \
                "radius: *|width: *|height: *|duration: *|lineWidth: *|\\.offset\\(x: *|" \
                "\\.offset\\(y: *|size: *)-?([2-9]|[1-9][0-9]+)(\\.[0-9]+)?"
      if (line ~ pattern) printf "  %d:%s\n", NR, $0
    }
  ' "$file")

  if [[ -n "$hits" ]]; then
    count=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
    total=$((total + count))
    status=1
    printf '\n\033[1m%s\033[0m — %s\n' "$file" "$count"
    printf '%s\n' "$hits"
  fi
done

echo
if [[ $status -eq 0 ]]; then
  echo "✓ No un-tokenised layout literals in ${#TARGETS[@]} file(s)."
else
  echo "✗ $total un-tokenised literal(s)."
  echo "  Resolve each to a token in SonicPlayer/DesignSystem/Tokens.swift, or append"
  echo "  '// lint:allow-literal — <reason>' if the value genuinely belongs at the call site."
fi
exit $status
