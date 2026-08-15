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

**Live as of this ADR — slice 1 only.** The target exists, is embedded in `PlugIns/`, is registered
with the system as a `com.apple.share-services` extension, and appears in the share sheet's app row
for audio and not for anything else. It shows a stub and cancels the request. **It has no queue, no
picker and no library access.**

**Intent, not built:** `folders.json`, the manifest, the atomic-rename batch commit, `InboxDrain`,
`ImportInbox`, the picker UI, the exception screen, and localisation. Slices 2–5 in
`docs/superpowers/specs/2026-08-14-share-import-design.md` §11.

**Also unproven:** that the App Group survives a real signed archive. Simulator builds sign ad-hoc
and never exercise entitlements, so nothing has yet tested it. `group.com.hasan.sonicplayer` does not
exist in the developer portal at time of writing. A `dry_run` of `distribute.yml` is what settles it.

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
