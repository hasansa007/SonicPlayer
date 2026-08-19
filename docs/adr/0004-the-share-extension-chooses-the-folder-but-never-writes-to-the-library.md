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

**Live as of slices 1, 2 and 3.** The target is embedded in `PlugIns/`, registered as a
`com.apple.share-services` extension, and appears in the share sheet for a share containing audio.
It **asks which folder**, copies the audio into the queue, and commits the batch with an atomic
rename; the app drains it on `.active` or `.background` and files it where you chose. **It still has
no library access** — it is handed a list of folder names and nothing else — which is the property
that makes it safe.

**The picker doubles as the confirmation, and that was not the original reason for it.** Slice 2
shipped a silent extension, and the first real share left the user with nothing to look at: share,
see nothing, open the app to find out. That is the deferred-work problem this ADR rejected the
silent options over, reintroduced by accident under a *localisation* justification — nobody noticed
it was also a feedback decision. Choosing a folder answers "did that work?" at no extra screen.

**It ships no strings of its own — with one exception that is worse than "inherited".** The picker
has no title and no labels; `UIButton(type: .close)` carries Apple's glyph and its own localised
label. The one word displayed is the library root, `"Library"`.

That word is untranslated on the app's Move screen already, and the first version of this paragraph
called it a pre-existing gap the picker merely inherits. **That defence does not hold**, and review
caught it: the Move screen sits in the app target, where `Localizable.xcstrings` exists and the
string could be translated tomorrow. `ShareInboxLayout.rootTitle` is a **new declaration in a target
that has no catalogue at all** — so this extends the gap rather than inheriting it, into the one
place a first-time user of the feature is guaranteed to look.

It is accepted for slice 3 because giving the extension a catalogue is slice 5's work and doing it
here would be that slice done badly. **Slice 5 owns both halves**: the extension's catalogue, and
`MoveDestinations.rootTitle` in the app.

Two precisions, because the looser phrasings were both wrong. The rule is **"at least one attachment
is audio"**, not "every attachment" — a mixed selection activates it, and slice 2 must therefore
filter attachments at copy time. And it matches `public.mpeg-4` as well as `public.audio`, so a
**video `.mp4` also offers Sonic Player** and is refused later at playback. That is a knowing trade,
inherited from `ImportFilter`, which accepts `.mp4` because audiobooks ship as `.m4b` and `.mp4`;
excluding it would hide the app from the long-form audio this feature exists for. It does sit against
the argument used to reject the dictionary activation rule above, and the difference is scale: the
dictionary rule offers Sonic Player for a share of PDFs with no audio in it at all.

**The localisation exception has ENDED, and this paragraph replaces the one that granted it.** It
read, in the present tense, that the stub's two English strings were an accepted deviation and that
*"the condition that ends the exception"* was the `SHARE-EXTENSION-STUB` marker leaving
`ShareViewController.swift`. Slice 2 deleted both the strings and the marker. The exception is over,
and leaving its text standing would have described a live exemption that no longer applies — the
failure CLAUDE.md names about intentions written in the present tense.

**The extension now ships no user-facing strings at all**, which is what makes that end-state
honest rather than merely declared. Three would-be strings were removed on the way here, each
caught only by review:

- `ShareError` conformed to `LocalizedError` with an English sentence the host app displays. It is a
  plain `Error` now; the host shows its own generic failure for a case that should not happen.
- Rejected attachments with no `suggestedName` were recorded as `"a shared file"` — an English
  literal written into the manifest and destined for slice 4's screen. The extension now records an
  empty marker and the app decides what to render, where the string catalogue is.
- The stub screen's label and button, deleted with the stub.

What remains is a spinner and `UIButton(type: .close)`: a system glyph whose accessibility label
Apple localises into every language the OS ships.

**One deviation from CLAUDE.md is live; the SwiftUI one closed at slice 3.**

The picker is `SharePickerView`, SwiftUI in a `UIHostingController`, as this paragraph said it
should be once the extension had a view worth writing that way. What remains UIKit is the shell —
`NSExtensionPrincipalClass` requires a `UIViewController` — plus a spinner for the copying phase.

**One boundary was learned the expensive way, and it is the useful part of this entry.** The close
button began in the UIKit shell, constrained against the shell's view, with the hosted list
constrained below it. On device it rendered halfway down the sheet and pushed the list off the
bottom. Three layout guides were tried before the guide was ruled out as the cause: the problem was
**two layout systems driving one screen** — UIKit constraints resolving against a hierarchy SwiftUI
was independently sizing. Nothing about the guides was wrong.

So the rule for this target: **once a phase is SwiftUI, everything in that phase is SwiftUI.** The
close button is a `safeAreaInset` inside `SharePickerView`, which lets SwiftUI place the bar, inset
the list beneath it, and honour the sheet's real safe area — none of which the shell could see. It
wraps `UIButton(type: .close)` in a `UIViewRepresentable` only because `Button(role: .close)` is
iOS 26+ and this app targets 18.0, so that is the only route to Apple's glyph and its nine
translations without writing a string.

**A third string question was settled at slice 3 and is worth writing down.** The picker shows no
title, no labels and no prose: a title would be a user-facing string, this target has no string
catalogue until slice 5, and anything written here ships as English in all nine locales. The one
word it does display is `MoveDestinations.rootTitle` — `"Library"` — which the app already shows
untranslated on its own Move screen. That is a **pre-existing gap the picker inherits rather than
creates**, and slice 5 owns both halves of it.

`nonClashing` restates `UniqueNameResolver`'s `" 2"`, `" 3"` scheme, because the extension cannot
see the app's sources. Unlike the queue constants, **this duplicate is not covered by
`ShareInboxLayoutAgreementTests`** — it polices the layout literals and the accepted extensions and
nothing about naming. The scheme has drifted before (`UniqueNameResolver` absorbed seven copies of
it), so this is a known, unguarded risk rather than an oversight; the two names never meet, since
one resolves within a batch and the other within the library, which is why it is tolerated for now.

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
