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

## Merging to `main` releases to TestFlight — and stops there

Pushing to `main` triggers `.github/workflows/distribute.yml`, which archives, signs and uploads to
TestFlight. No button to press afterwards, no promotion step. **For testers, the merge is the
release.**

Treat a `main` merge with the caution that implies. In particular, never open a feature PR against
`main` — base it on `feat`.

### Reaching the public App Store is a separate, manual step

**This file said "the merge *is* the release" full stop, and that was true only while the app was
TestFlight-only.** SonicPlayer 3.0.0 (25) went live on the App Store on 2026-08-13, and nothing in
this repository performed that submission — it was done by hand in App Store Connect. Nothing
automates it today.

Two consequences that the old sentence hid:

- **The pipeline's What's New is not the store's.** `Set What's New in TestFlight` writes the
  *beta build's* localisation. The App Store version has its own *What's New in This Version*
  field, per language, which no workflow touches. `docs/appstore/<version>/` holds that copy and
  its README explains the split. Editing `RELEASE_NOTES.md` changes what testers see and nothing
  a shopper sees.
- **Guideline 5.2.5 now carries removal risk, not rejection risk.** A rejected upload costs a
  build number. A live listing taken down costs the listing. The word list in `CLAUDE.md` and the
  design spec did not change; what changed is the price of getting it wrong.

### Tag the commit that ships

**There is a tag to cut now, and this file previously said there was not.** 3.0.0 was released
untagged, and reconstructing which commit Apple approved afterwards meant diffing merge commits to
prove no `SonicPlayer/` file had changed since the build bump.

After an App Store release goes live, tag the commit that produced the approved binary:

```bash
git tag -a 3.0.1 <sha> -m "3.0.1 (26) — App Store release"
git push origin 3.0.1
```

**Bare version, no `v` prefix** — matching `1.1.2` and `1.0.6`. `v1.1.1` is the odd one out and is
not the pattern to copy. Pushing a tag does not ship anything: the workflow triggers on
`push: branches: [main]`, which a tag ref does not match.

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

## Signing — three secrets, and no certificates to manage

The workflow signs with an **App Store Connect API key** plus `-allowProvisioningUpdates`. The
runner fetches or creates its own signing assets, which is what Xcode does locally under automatic
signing.

| Secret | From |
|---|---|
| `ASC_API_KEY` | the `.p8`, base64-encoded — App Store Connect → Users and Access → Integrations |
| `ASC_API_KEY_ID` | shown beside the key |
| `ASC_API_ISSUER_ID` | shown above the key list |

The key needs the **App Manager** role; a weaker role authenticates but cannot create signing
assets, and the failure arrives at export as a provisioning error that does not mention the role.

```bash
gh secret set ASC_API_KEY < AuthKey_XXXXXXXX.p8    # never paste a key into a chat or a commit
gh secret set ASC_API_KEY_ID
gh secret set ASC_API_ISSUER_ID
```

**There is deliberately no `TEAM_ID` secret.** The team id is not a credential — it is committed in
`project.pbxproj`, and that is what the app is signed with. The export step reads it from there, so
it cannot drift from the build.

**This replaced four secrets** — `CERTIFICATE_P12`, `CERTIFICATE_PASSWORD`, `PROVISIONING_PROFILE`
and `TEAM_ID` — and the two steps that consumed them. That path required exporting a distribution
`.p12` by hand and re-exporting it whenever the certificate expired. It also asked for an artifact
this project never had: the machine that shipped 3.0.0 (23) by hand holds only an
`Apple Development` identity, because the app has always used automatic signing.

## Proving the pipeline without shipping

Actions → **Distribute to TestFlight** → Run workflow, with **dry_run** checked (it defaults to
checked). It archives, **signs, exports** and attaches the `.ipa` as a run artifact — then stops
before the upload.

Use it after any change to the workflow, the signing setup, or the Xcode pin.

**One step is invisible to it, and that is where the next bug will hide.** `Set What's New in
TestFlight` is gated on `push || !dry_run`, so **every dry run skips it** — it is the only step that
talks to the App Store Connect API, and the facility for proving the pipeline cannot reach it.

That is not hypothetical. 3.0.0 build 24 shipped with no What's New because the step's first `curl`
exited 3 before making a request: `curl` reads `[` and `]` as URL-globbing metacharacters, so
`filter[version]=` is a malformed range, and under `bash -e` the failing command substitution killed
the step in 210ms. Two green dry runs that day both skipped it, as had every dry run before them.

So when you change that step, **the only real test is the next release**. Read the run afterwards
rather than trusting the green tick on the promotion — and note that the upload succeeds *before*
this step, so a failure here never means the build did not ship.

**The export step is what a dry run exists to exercise.** It used to be skipped entirely on a dry
run — the step was gated on `push || !dry_run` — so the run archived and stopped, while this file
claimed it "archives, exports and validates". Signing happens at export, so the one facility for
proving the pipeline without shipping could not reach the part most likely to be broken. The step
now always runs and only its `destination` changes, `export` instead of `upload`.

**The Run workflow button now exists.** It did not once: GitHub only offers `workflow_dispatch` for
workflows present on the **default branch**, and `distribute.yml` lived only on `feat`, so the dry
run was unavailable *before* the first promotion and available ever after — exactly backwards from
when it is most wanted. `distribute.yml` has been on `main` since the 3.0.0 promotion, and `main`
is the default branch, so the button is there.

Kept because the failure mode recurs for any *new* workflow: `gh run list --workflow=<name>.yml`
reporting *"workflow not found on the default branch"* is not a missing file, it is a file on the
wrong branch for the purpose.

## The Xcode pin

The runner is `macos-26` and pins **Xcode 26.6**. The guard step asserts **two** floors, and the
distinction is the whole point of it: one that the toolchain can *compile* this project, and one
that Apple will *accept the upload*.

**The package constraint that originally forced this is gone.** Until #20 the reason was that
`ComposableArchitecture` and `swift-sharing` declared `swift-tools-version: 6.1`, so anything below
Xcode 16.3 failed during package resolution with an error that never mentioned Xcode. The project
now has zero packages, so that failure mode no longer exists.

**This section said 26.3, "the newest available on `macos-15` and the closest to the local
toolchain", for longer than that was safe — and that exact reasoning is what caused a rejection.**
3.0.0 build 23 archived, signed and uploaded cleanly under 26.3, then failed automated validation
with **ITMS-90111, unsupported SDK**, burning a build number that can never be reused.

So the pin is not a free choice between versions that compile. **Apple sets a moving floor on the
SDK, and an Xcode below it fails only after the upload.** `macos-15` carries nothing above 26.3,
which is why the image moved to `macos-26` too. When Apple raises the floor again — watch
`developer.apple.com/news/releases` — raise `REQUIRED_XCODE` in the guard, the `xcode-select` path,
and the image if it has nothing newer.

Do not re-derive "newest available on the image" from an older copy of this paragraph. That is the
reasoning that shipped a refused binary.

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
