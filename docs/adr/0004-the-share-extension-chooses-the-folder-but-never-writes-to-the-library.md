# 4. The share extension chooses the folder but never writes to the library

Date: 2026-08-15
Status: Accepted — partially implemented, see "What is live and what is intent"
Issue: [#112](https://github.com/hasansa007/SonicPlayer/issues/112)

## Context

Audio living in another app — a Voice Memos recording, a lecture posted to a Telegram channel —
reaches the library only through a detour: Save to Files, open Sonic Player, import, then move it to
the right folder. Four steps to file one recording is enough friction that the file does not make
the trip, and the app has no share extension, so it appears only as a buried "Copy to Sonic Player"
entry synthesised from its document types, landing everything at the library root.

Three shapes were drawn for the extension, differing in **where the destination folder is chosen**:

| | On tapping Sonic Player in the share sheet |
|---|---|
| Silent | Sheet closes, nothing visible. Files reviewed in the app later. |
| Confirm only | A one-line confirmation, then the sheet closes. Files reviewed in the app later. |
| Picker in the sheet | The extension's own screen lists real folders; files go straight to the chosen one. |

## Decision

**The extension shows the folder picker, and still writes only into its own queue.**

The two halves are independent, and treating them as one is what made the first two options look
safer than they are. Choosing a destination requires *reading* a list of folder names; writing to
that destination is a separate act that the app performs later. So the extension:

- reads `group.com.hasan.sonicplayer/folders.json`, a flat list of folder names the app maintains
- writes the shared files and a `manifest.json` recording the chosen destination into
  `group.com.hasan.sonicplayer/Inbox/.partial-<UUID>/`
- **renames that directory to `<UUID>` — the atomic rename is the commit**
- never opens `Documents/`, and therefore cannot damage the library

The app drains committed batches into the chosen folder on `.active` or `.background`, whichever
fires first, skipping while `player.isImporting`. `OpenInImport.run` is that drain: #41 already
taught it to consume a queue it owns and to test identity by bytes rather than by name, so no second
import path exists.

This deliberately differs from ADR 0003's rule for the **staging** drain, which runs on `.background`
alone because a launch-time drain races `.onOpenURL`. A group inbox has no such hand-off — nothing
delivers its files through `.onOpenURL` — so there is no race to lose, and `.background` alone would
mean shared files do not appear until the app has been opened *and then backgrounded*, which is
precisely when the user goes looking for them.

Two entry points are affordable because the drain is idempotent: a batch is wholly visible or not at
all, and one already moved is simply absent the second time.

## Rejected alternatives

**Silent, and Confirm-only — review the files in the app afterwards.** Both were recommended first
and both are wrong, for the same reason: **a review screen you must visit later is deferred work,
not removed work.** The problem being solved is "annoying enough that I didn't"; rescheduling the
annoyance does not answer it, and it leaves the files in limbo until the user remembers. Picking the
destination in the share sheet is also the conventional iOS pattern.

The argument advanced *for* them was that a picker forces the extension to write into the library,
where a kill mid-write leaves a half-imported mess. That argument does not survive the split above —
the extension records the choice and writes only to its own queue, so the safety property is kept for
free. The genuine cost of the picker is a second UI to build, test and localise into nine languages,
which is accepted knowingly and sliced separately so it can be cut back to a flat list if it starts
growing a hierarchy browser.

**A share extension that files directly into `Documents/`.** This is what makes the extension
dangerous rather than merely useful. Share extensions run under a hard memory cap and are killed
without notice; an interrupted write lands inside the user's library, where it is visible and theirs
to clean up. Under the chosen design an interruption leaves a half-drained *inbox* — invisible,
idempotent, and resumed on the next launch. The queue is the recovery.

**A Telegram channel subscription, so new posts arrive by themselves.** Out of scope, and it belongs
on a server. A bot only sees a channel it has been made admin of and `getFile` caps downloads at
20 MB, which rules out lectures; the alternative is a full protocol client — a large C++ dependency
into a codebase whose defining constraint is zero dependencies (#20 was an epic spent reaching that)
— asking for a phone number inside an audio player. If it is ever built, the reading belongs where
#7–#9 already put remote content.

**A Voice Memos sync.** Not rejected — unavailable. No public API for its library, no background
access, private container. Recorded so it is never planned.

**Downloading or extracting from YouTube.** Refused. App Store Guideline 5.2.3 names those sources
directly and the app has been live since 2026-08-13, so this is removal risk rather than rejection
risk — the same category as the 5.2.5 constraints in `2026-08-09-rotary-shell-design.md` §3.

**A dictionary activation rule (`NSExtensionActivationSupportsFileWithMaxCount`).** Simpler, and it
has no "audio" key — it offers Sonic Player for PDFs and spreadsheets, which the app then refuses.
Being offered for a file and then rejected is a worse first impression than not being offered. The
predicate on `public.audio` is used instead, and its filtering is verified in both directions.

## What is live and what is intent

**Live as of slices 1 and 2.** The target is embedded in `PlugIns/`, registered as a
`com.apple.share-services` extension, and appears in the share sheet for a share containing audio.
It **copies the audio attachments into the queue and commits the batch with an atomic rename**; the
app drains it on `.active` or `.background` and files everything at the library root. **It still has
no picker and no library access**, which is the property that makes it safe.

**The extension shows nothing at all**, and that is a decision rather than an omission: a screen
needs strings, strings need nine languages, and localisation is slice 5. Any copy shipped now would
be English in every locale or would hold the feature back. The app is a better place to say what
arrived, because by then it has actually filed it. Slice 3's picker brings its own strings.

Two precisions, because the looser phrasings were both wrong. The rule is **"at least one attachment
is audio"**, not "every attachment" — a mixed selection activates it, and slice 2 must therefore
filter attachments at copy time. And it matches `public.mpeg-4` as well as `public.audio`, so a
**video `.mp4` also offers Sonic Player** and is refused later at playback. That is a knowing trade,
inherited from `ImportFilter`, which accepts `.mp4` because audiobooks ship as `.m4b` and `.mp4`;
excluding it would hide the app from the long-form audio this feature exists for. It does sit against
the argument used to reject the dictionary activation rule above, and the difference is scale: the
dictionary rule offers Sonic Player for a share of PDFs with no audio in it at all.

**A localisation exception is accepted here, and is recorded rather than argued in a comment.**
CLAUDE.md requires every user-facing string to go through `Localizable.xcstrings` in nine languages,
without exceptions. The stub's two strings are English literals. Translating a dead end would make it
look like a finished feature, and the nine translations belong on the picker's real copy in slice 5
against final wording. **The condition that ends the exception:** the `SHARE-EXTENSION-STUB` marker
leaving `ShareViewController.swift`, which is also what the `distribute.yml` guard keys on — so the
exception cannot outlive the stub without a release failing.

**Intent, not built:** `folders.json`, the picker UI, the exception screen, and localisation —
slices 3–5. `AppViewModel.shareImportFailures` exists, is populated, and is read by nothing; it is
the seam slice 4 plugs into, present now because the drain has to put failures *somewhere* and
dropping them is the failure this design keeps legislating against.

**A duplication was accepted in slice 2 and is policed rather than trusted.** The two targets cannot
see each other's sources, so `ShareInbox` and `ShareInboxLayout` state the queue contract twice —
the App Group id, the directory names, the `.partial-` convention, and the accepted audio
extensions. The alternative was hand-maintained multi-target membership in `project.pbxproj`, which
fights the synchronized file groups this project uses. `ShareInboxLayoutAgreementTests` reads the
extension's source and both `.entitlements` as text and fails on any drift, because a silent
disagreement means the extension writes into a container the app never reads and every shared file
vanishes with no error anywhere.

**Proven, and it was not free.** `group.com.hasan.sonicplayer` was registered in the developer portal
on 2026-08-15 and enabled on both App IDs, and a `dry_run` of `distribute.yml` then archived, signed
and exported. The evidence is in the artifact rather than in the green tick: the exported `.ipa`
carries `PlugIns/SonicPlayerShare.appex`, both bundles at `3.0.0 (26)`, and
`com.apple.security.application-groups → group.com.hasan.sonicplayer` in the **signed** entitlements
of both binaries.

Getting there took five runs and cost nothing recoverable, which is the argument for shipping the
target empty restated. `-allowProvisioningUpdates` cannot create an App Group; Xcode reports the
resulting refusal as `Authentication failed`, which sends you to debug a credential that is fine; and
the account had silently filled its 12-certificate cap with one `Created via API` certificate per CI
run. All three are written up in `docs/deploy-and-staging.md`, and the last two are #114 and #115.

## Consequences

There are three targets, not two. The app and the extension are separate processes with separate
containers, and the group is the only thing they share — a queue, never shared storage.

**A version bump is now two plist edits.** An embedded extension must carry its own
`CFBundleShortVersionString` and `CFBundleVersion`, and App Store Connect rejects an upload where
they disagree with the host's. `$(MARKETING_VERSION)` cannot be used to deduplicate them: it is the
exact key this project deletes on purpose. So the guard step in `distribute.yml` asserts the two
plists agree and applies the stale-build-setting rule to the extension target as well. See
`docs/deploy-and-staging.md` → *Before bumping the version*.

`ShareViewController` is a `UIViewController` in a codebase whose rule is SwiftUI only. That is the
`NSExtensionPrincipalClass` contract, not a preference; the picker will be SwiftUI in a
`UIHostingController`, keeping the exception to one file rather than one target.
