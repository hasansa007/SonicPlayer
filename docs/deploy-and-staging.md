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

**A version bump is now TWO plist edits, not one (#112).** `SonicPlayer/Info.plist` is still the
source of truth, but `SonicPlayerShare/Info.plist` carries its own `CFBundleShortVersionString` and
`CFBundleVersion`, and **App Store Connect rejects an upload where an embedded extension disagrees
with its host**. Edit one and not the other and the archive succeeds, the signing succeeds, the
upload succeeds, and the *validation* fails — against a build number that can never be reused.

No build setting removes the duplication: `$(MARKETING_VERSION)` is exactly the key this project
deletes on purpose, because Xcode's General tab writes it and the plist is what ships. So the guard
step asserts the two plists agree, and fails the run before the archive if they do not. Treat the
guard as the reason you can bump confidently, not as a reason to stop checking.

### What that guard CANNOT catch: a stale pair that agrees (#115)

**It compares the two plists to each other, never to what is already uploaded.** Leave both at a
build number that has already shipped and the guard passes cleanly, the archive succeeds, the
signing succeeds, the upload succeeds — and App Store Connect rejects with *"the bundle version must
be higher than the previously uploaded version"*, against a run that has done all the expensive work.

`RELEASE_NOTES.md` does not close it either: its check is `grep -qx "## $VERSION"`, so an unchanged
`CFBundleShortVersionString` finds the section from the release that already shipped and passes,
handing testers the notes for a build that did not contain the new work.

**So the pre-flight is on you: `CFBundleVersion` must be strictly greater than the highest build
already uploaded for this `CFBundleShortVersionString`.** 3.0.0 (25) is live as of 2026-08-13.

The workflow already mints an App Store Connect JWT and queries `/v1/builds`, but only *after* the
upload, to attach What's New. Moving that query before the archive — fail if
`filter[version]=$BUILD` already returns a build — would close this properly. Not done: it is a
change to the step ordering of a pipeline that has been wrong twice, and it wants its own dry run.

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
# ASC_API_KEY is the BASE64 of the .p8, not the .p8 — the table above says so and this
# command used to contradict it by piping the raw file. The workflow does
# `base64 --decode`, so a raw key decodes to garbage, fails the "did not decode to a
# private key" check, and sends you looking at Apple instead of at this line.
base64 -i AuthKey_XXXXXXXX.p8 | tr -d '\n' | gh secret set ASC_API_KEY
gh secret set ASC_API_KEY_ID --body XXXXXXXX
gh secret set ASC_API_ISSUER_ID --body 00000000-0000-0000-0000-000000000000
```

**Verify the triple against Apple before blaming CI.** A local call settles in seconds whether the
credential or the pipeline is at fault — mint a JWT (ES256, `kid` = key id, `iss` = issuer id,
`aud` = `appstoreconnect-v1`) and `GET /v1/apps`. A 200 means the credential is good and the problem
is somewhere else, which on 2026-08-15 it was: the archive was failing over a missing App Group and
reporting it as an authentication error.

### The two targets configure signing differently, and that is deliberate for now

`SonicPlayer`'s Release config carries `CODE_SIGN_IDENTITY = "Apple Development"` and an empty
`PROVISIONING_PROFILE_SPECIFIER`; `SonicPlayerShare` carries neither, only `CODE_SIGN_STYLE = Automatic`.
Both resolve correctly under automatic signing — the 2026-08-15 `dry_run` archived, signed and
exported both bundles — but they get there by different routes.

A development identity in a Release config is wrong on its face, and it is inert only because
automatic signing overrides it. The new target was given the minimal correct configuration rather
than inheriting the mistake. **Removing the keys from the app target as well is the tidy end state
and is deliberately not done here:** it changes the signing configuration of the bundle that actually
ships, on a slice that is not about signing, in the one area of this project that has already
produced an ITMS-90111 rejection and a five-run detour. It wants its own change and its own dry run.

**There is deliberately no `TEAM_ID` secret.** The team id is not a credential — it is committed in
`project.pbxproj`, and that is what the app is signed with. The export step reads it from there, so
it cannot drift from the build.

**This replaced four secrets** — `CERTIFICATE_P12`, `CERTIFICATE_PASSWORD`, `PROVISIONING_PROFILE`
and `TEAM_ID` — and the two steps that consumed them. That path required exporting a distribution
`.p12` by hand and re-exporting it whenever the certificate expired. It also asked for an artifact
this project never had: the machine that shipped 3.0.0 (23) by hand holds only an
`Apple Development` identity, because the app has always used automatic signing.

## The App Group is portal setup that CI cannot do for you (#112)

`-allowProvisioningUpdates` creates App IDs and mints profiles. **It cannot create an App Group, and
it cannot assign one.** That is the whole reason slice 1 of #112 shipped an empty extension and was
proven by a dry run before anything depended on it.

Done once, on 2026-08-15, and recorded because the failure mode is expensive and unrecognisable:

1. **Identifiers → App Groups → +** — `SonicPlayer Share` / `group.com.hasan.sonicplayer`
2. **App IDs → `com.hasan.sonicplayer`** → tick **App Groups** → Configure → assign the group → Save
3. **App IDs → +** → explicit `com.hasan.sonicplayer.share` → same capability, same group

**Step 3 is register-then-edit, and that detail is load-bearing.** The registration form lets you
tick App Groups but shows no group picker — Configure only appears once the App ID exists. So an App
ID that CI auto-creates arrives with the capability **on and zero groups assigned**, which fails
exactly like no capability at all. Anything that recreates these identifiers has to come back and
assign the group by hand.

### How this failure presents, so nobody spends three runs on it again

Xcode does not say "the App Group is missing". It says:

```
error: Authentication failed: Make sure a bearer token was provided, it is properly
       configured and signed, and it has not expired.
error: No profiles for 'com.hasan.sonicplayer' were found: Xcode couldn't find any
       iOS App Development provisioning profiles matching 'com.hasan.sonicplayer'.
```

Both lines are misleading. The credential is fine; Xcode simply cannot mint a profile carrying an
entitlement the App ID does not have, and it reports the resulting API refusal as an auth failure.
**The tell is the word "Development" in a Release archive** — it had already fallen back to a profile
class that could never match. Before suspecting the secrets, check whether the entitlements file
requests something the App ID does not grant:

```bash
security cms -D -i <profile>.mobileprovision | plutil -p - | grep -A5 Entitlements
```

## Every run burns a development certificate, and the account caps at 12 (#114)

**This is the standing cost of dropping imported certificates in favour of
`-allowProvisioningUpdates`, and it is invisible until the day it stops the build.**

Each runner is a fresh machine with an empty keychain, so `-allowProvisioningUpdates` cannot *fetch*
a certificate — it **creates** one, uses it for that archive, and the private key dies with the
machine. The certificate itself stays on the account forever, named `Created via API`.

Apple caps Apple Development certificates at **12**. On 2026-08-15 the account held 12: two of
yours and **ten created by CI**, seven from a single day of runs. The next archive failed with:

```
error: Choose a certificate to revoke. Your account has reached the maximum number of
       certificates. To create a new one, you must choose a certificate to revoke.
```

Note what makes this expensive to diagnose: **nothing fails while slots remain**, so the pipeline
looks healthy for months, and the failure arrives attached to whatever change happened to force a
fresh mint — in this case #112's App Group, which invalidated the existing profiles. The change gets
blamed for a debt the pipeline had been quietly accruing.

**To clear it**, revoke every DEVELOPMENT certificate named `Created via API`. They are single-use
and their private keys are gone; nothing can be signed with them again. Keep the certificates in
your own name, and keep the DISTRIBUTION certificate — that is the one that ships.

```bash
# List: GET  /v1/certificates?limit=200   → filter certificateType=DEVELOPMENT, displayName='Created via API'
# Kill: DELETE /v1/certificates/{id}      → 204
```

**This buys about ten more runs, it does not fix anything.** The real options are importing a
signing certificate in CI (what this workflow deliberately removed) or a cleanup step that revokes
`Created via API` certificates before archiving. Neither is done; pick one before the count climbs
again.

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

**It has now failed three times, each time for a different reason, and the pattern is the lesson.**
Fixing the globbing let the request be made. Fixing `filter[app]`, which had been handed a bundle id
where it takes a numeric app id, let it be made correctly. Each fix moved the failure one line down
to the next latent bug, and 3.0.0 (24), 3.0.0 (25) and 3.0.1 (26) all uploaded cleanly and all
shipped with no What's New.

The third was the JWT itself. `openssl dgst -sha256 -sign` emits ASN.1 DER for an EC key —
`SEQUENCE { INTEGER r, INTEGER s }`, 70 to 72 bytes — while ES256 requires the 64-byte raw form,
r and s each zero-padded to 32 bytes and concatenated. The token was malformed from the first
release, Apple answered 401, and `2>/dev/null || echo ""` on the app-id lookup converted that into
an empty variable and the error *"Could not resolve the app id"* — which names the app, the bundle
id and the query, and never the credential. **A swallowed error does not stay silent; it comes back
wearing a different failure's name.** Both are fixed: the signature is converted to raw form and
asserted to be 86 characters, and Apple's response body is printed before anything parses it.

Note what a lie that error told about *where* to look. Three sessions read it as a query problem
because it described one.

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
