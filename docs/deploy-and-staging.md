# Deploy and Staging — SonicPlayer

**This file is the authority on the branch model.** Tooling that auto-detects a repo's branch
model reads a runbook first and falls back to guessing from branch names; the guess is wrong here,
which is why this file exists. See "Why this file exists" at the bottom.

## The branch model

| Role | Branch | What a merge here means |
|---|---|---|
| Feature work | `gh-<issue>-<slug>` | nothing — open a PR into `feat` |
| **Pre prod** | **`feat`** | integrated, but **not shipped**. No tester sees it |
| **Prod** | **`main`** | **RELEASES.** Pushing to `main` uploads a build to TestFlight |

Two stages, not one. A PR based on `main` skips pre prod entirely.

## Merging to `main` is the release

There is no separate promotion step, no tag to cut, no button to press afterwards. Pushing to
`main` triggers `.github/workflows/distribute.yml`, which archives, signs and uploads to
TestFlight. **The merge is the release.**

Treat a `main` merge with the caution that implies. In particular, never open a feature PR against
`main` — base it on `feat`.

## Before bumping the version

The workflow reads `RELEASE_NOTES.md` for the section whose heading equals `## <version>`, where
`<version>` is `CFBundleShortVersionString` from `SonicPlayer/Info.plist`, and ships it as What's
New.

**Add the section before bumping the version.** With no matching section, testers get a
placeholder and the build logs a warning — it still ships, so this fails quietly.

Write for testers, not for the changelog: what changed for someone using the app. Leave refactors,
dependency bumps and test work out.

## Proving the pipeline without shipping

Actions → **Distribute to TestFlight** → Run workflow, with **dry_run** checked (it defaults to
checked). That archives, exports and validates, then stops before the upload.

Use it after any change to the workflow, the signing setup, or the Xcode pin.

## The Xcode pin

The runner pins **Xcode 26.3**. Do not lower it. `ComposableArchitecture` and `swift-sharing`
declare `swift-tools-version: 6.1`, so anything below Xcode 16.3 fails during package resolution
with an error that never mentions Xcode. A guard step asserts the Swift version up front and fails
with a readable message instead of that one.

## Why this file exists

`feat` is a pre-prod branch with a feature-branch name. Automated tooling looks for
`staging` → `develop` → `main`/`master` and, finding none of the first two, resolves pre prod to
**`main`** — the one branch whose merge ships to TestFlight. A `/dev:pre-prod` run trusting that
detection would open its PR against `main` and merge it, releasing work that was never integrated.

A runbook outranks name-based detection, so stating the model here is what closes that gap.

The alternative fix is renaming `feat` to `develop`, which the detection already handles. That is
a better end state and it is not done: the rename moves a branch that open PRs target, so it wants
a moment when nothing is in flight. **If `feat` is ever renamed, update the table above in the
same change** — a runbook that outranks detection is worse than none when it is stale.
