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

**Add the section before bumping the version.** With no matching section **the run now fails**,
early, before the archive. It used to ship a placeholder and log a warning, which meant the whole
thing failed quietly — testers got *"see the commit history for what changed"* and the only evidence
was a line in a log nobody opens.

**The half that is still on you: a section that exists and describes the wrong release.** Nothing
can check that. It happened here — `## 2.3.0` described multi-select in the file browser and the
Home screen's recents while the branch waiting to promote had deleted both and replaced the entire
interface with the dial. A wrong section passes every check a machine can make, and reads as current.

Write for testers, not for the changelog: what changed for someone using the app. Leave refactors,
dependency bumps and test work out. **What ships is plain text** — `**bold**` arrives as literal
asterisks, and blank lines are stripped, so read the extracted output rather than the Markdown.

## Proving the pipeline without shipping

Actions → **Distribute to TestFlight** → Run workflow, with **dry_run** checked (it defaults to
checked). That archives, exports and validates, then stops before the upload.

Use it after any change to the workflow, the signing setup, or the Xcode pin.

**There is no Run workflow button until this file is on `main`.** GitHub only offers
`workflow_dispatch` for workflows present on the **default branch**, and `distribute.yml` lives on
`feat`. So the dry run is unavailable *before* the first promotion and available ever after —
which is exactly backwards from when it is most wanted. Until then the first promotion merge both
installs the pipeline and fires it for real.

`gh run list --workflow=distribute.yml` says so plainly if you forget: *"workflow distribute.yml not
found on the default branch"*. That is not a missing file; it is a file on the wrong branch for the
purpose.

## The Xcode pin

The runner pins **Xcode 26.3**, and a guard step asserts up front that the toolchain can build
the project.

**The package constraint that originally forced this is gone.** Until #20 the reason was that
`ComposableArchitecture` and `swift-sharing` declared `swift-tools-version: 6.1`, so anything below
Xcode 16.3 failed during package resolution with an error that never mentioned Xcode. The project
now has zero packages, so that failure mode no longer exists. 26.3 remains the pin because it is
the newest available on `macos-15` and the closest to the local toolchain.

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
