# Share Import — audio from any app, filed where you want it

**Status:** IN PROGRESS — slice 1 merged (PR #113), slice 2 on `gh-112-share-queue`. Slices 3–5 outstanding.
**Date:** 2026-08-14
**Relates to:** [#112](https://github.com/hasansa007/SonicPlayer/issues/112) — share import epic (`P2`, `ops`)
**Adjacent:** [#7](https://github.com/hasansa007/SonicPlayer/issues/7) · [#8](https://github.com/hasansa007/SonicPlayer/issues/8) · [#9](https://github.com/hasansa007/SonicPlayer/issues/9) — StudyHub, which owns remote content

---

## 1. What this is

A **share extension**. Audio shared from any app — Voice Memos, a Telegram channel, Safari, Mail —
arrives in the SonicPlayer library, in a folder chosen at the moment of sharing, without the app
being opened at all.

The extension is a new target. It shows a folder list, copies the shared files into a queue it owns,
and exits. The app drains that queue into the chosen folder the next time it runs.

**The idea this design is built around:** the friction was never the import, it was the *detour*.
Save to Files, open SonicPlayer, import, move to the right folder — four steps to file one recording
is enough to not bother, and what does not get filed does not get listened to.

---

## 2. Why this shape, and not a per-source integration

The brainstorm started from three named sources — Voice Memos, Telegram channels, YouTube — and the
useful move was to stop treating them as three problems. Two axes: where the audio is, and how often
it arrives.

|                 | one-off      | a backlog    | ongoing               |
|-----------------|--------------|--------------|-----------------------|
| **Voice Memos** | share sheet  | share sheet  | impossible            |
| **Telegram**    | share sheet  | share sheet  | a separate product    |

**Four of the six cells are one piece of work**, and it is the same piece: audio living in another
iOS app, moved here. That is what a share extension is. Building it once serves every source that
can share a file, including ones not on this list and ones that do not exist yet.

The remaining two cells are §3.

---

## 3. What this deliberately is not

### Not a Telegram channel subscription

Reading a channel programmatically has three routes and all three are wrong in an audio player:

- **Bot API** — a bot only sees a channel it has been made *admin* of, which rules out any channel
  you merely follow, and `getFile` caps downloads at 20 MB, which rules out lectures.
- **MTProto / TDLib** — a full protocol client: a large C++ dependency into a codebase whose
  defining constraint is zero dependencies (#20 was an entire epic spent reaching that), plus asking
  for a phone number and an SMS code inside an audio player.
- **Scraping the public web preview** — public channels only, and fragile by construction.

If channel subscription is ever built, **the channel reading belongs on a server, not on the
device.** That is not a workaround, it is the correct place: it keeps the app dependency-free, keeps
credentials out of it, and reuses the sync apparatus #7–#9 already establish. SonicPlayer would see
"new audio from StudyHub", which is #9 as already written.

### Not a Voice Memos sync

There is no public API for the Voice Memos library and no background access to it; recordings live
in a private container. This is unavailable, not merely unbuilt. Recording it here so it is never
planned.

### Not YouTube extraction

App Store Guideline 5.2.3 names YouTube among the sources whose unauthorized download or extraction
gets an app rejected, and it breaks YouTube's terms independently. SonicPlayer went live on the App
Store on 2026-08-13, so this is **removal risk, not rejection risk** — the same category as the
5.2.5 constraints in `2026-08-09-rotary-shell-design.md` §3, and it is refused on the same grounds.

### Not an editing surface

No renaming, trimming or splitting during import. The library already has those verbs and they work
on files that are in it.

---

## 4. The decision that shaped everything: the extension picks the folder

Three options were drawn, differing in **where the destination is chosen**:

| | What happens on tapping SonicPlayer in the share sheet |
|---|---|
| Silent | Sheet closes, nothing visible. Files reviewed in the app later. |
| Confirm only | A one-line confirmation, then the sheet closes. Files reviewed in the app later. |
| **Chosen** | **The extension's own screen opens in the share sheet, listing real folders. Files go straight to the picked one. No review screen in the happy path.** |

The first two were recommended and that recommendation was wrong. Both leave the files in limbo
until you remember to open the app — **a review screen you must visit later is deferred work, not
removed work.** The stated problem was "annoying enough that I didn't"; rescheduling the annoyance
does not answer it. Picking a destination in the share sheet is also the conventional iOS pattern.

The argument against the chosen option was that the extension would have to write into the library,
where a kill mid-write leaves a half-imported mess. **That argument does not survive, because
choosing a folder and writing to it are independent.** The extension records the choice and still
writes only into its own queue; the app does the filing. The safety property is kept for free.

What the objection cost correctly: **a second folder picker to build, test and localise into nine
languages.** That is a real cost, accepted knowingly, and it is why §12 slices it separately.

---

## 5. The shape

```
   Voice Memos · Telegram · Safari · anything that shares a file
                          │
                          ▼  share sheet
   ┌──────────────────────────────────────────────┐
   │  SonicPlayerShare (new target)               │
   │    reads   group/folders.json  ← list only   │
   │    writes  group/Inbox/.partial-<UUID>/      │
   │              the files                       │
   │              manifest.json {destination}     │
   │    ⟶ atomic rename to <UUID>   ← the commit  │
   └──────────────────────────────────────────────┘
                          │
                          ▼  .active OR .background — whichever fires first
   InboxDrain  (Features/Files/ — the I/O half)
   ImportInbox (Domain/ — the decisions)
                          │
          ┌───────────────┴───────────────┐
          ▼                               ▼
   Documents/<destination>/        DialScreen — exception surface,
   the happy path, silent          shown ONLY when a row needs you
```

**The extension never touches `Documents`.** It reads one JSON listing of folder names, written by
the app whenever the tree changes, and writes only inside its own inbox. It cannot see the library
and therefore cannot damage it — which is the property §4's objection was really protecting, kept
without paying for it in UX.

**The atomic directory rename is the commit.** The extension writes files and the manifest into
`.partial-<UUID>/`, then renames the directory. The drain only ever looks at directories without the
dot prefix, so a batch is either wholly visible or wholly invisible. This removes the torn-write
class outright, including the case where a share happens while the app is foregrounded and draining.

**The inbox is a queue, and the queue is the recovery.** A kill partway through leaves the moved
files in the library and the rest still queued; the next activation resumes. This is the same
concept `Documents/Inbox` already is — iOS's hand-off queue that the app must *drain* rather than
copy out of, which is what #41 established and what `ImportFilter.isStaged` already tests for.

### When the drain fires — decided at Phase 5, 2026-08-15

**Both `.active` and `.background`, whichever comes first**, in the existing
`AppViewModel.scenePhaseChanged` (`App/AppViewModel.swift:242`), and skipping while
`player.isImporting` exactly as the staging drain already does.

This is deliberately *not* the same rule as ADR 0003's, and the difference is the point. That ADR
puts the **staging** drain on `.background` alone because a launch-time drain races `.onOpenURL` —
launching by opening a file is precisely when a staged file is waiting. **A group inbox has no such
hand-off**: nothing delivers its files through `.onOpenURL`, so there is no race to lose, and
`.background` alone would mean shared files do not appear until you have opened *and then
backgrounded* the app — missing at the exact moment you went looking for them.

Two entry points are affordable because the drain is idempotent by construction: the atomic
directory rename means a batch is wholly visible or not at all, and a batch already moved is simply
not there the second time. The cost is one more path to test, and the interrupted-drain test in §9
covers both.

**One inherited constraint does transfer.** ADR 0003 measured that a `Task` does not run before the
app suspends — the first `.background` drain landed on the *next* foreground instead. So the
`.background` entry point must not rely on async work completing. Either it does its enumeration
synchronously like `drainStagingDirectory`, or it accepts that `.background` is best-effort and
`.active` is the guaranteed one. **Resolve this by measuring, not by reasoning** — that is what the
ADR had to do.

---

## 6. The review screen, demoted

It survives, but it is no longer the happy path. It appears **only when something needs a decision**:

- a file already in the library (`ImportDedupe` — name and size, no I/O)
- a non-audio file that got past the activation rule
- a copy that failed — no space, or unreadable
- **a destination folder deleted between the share and the drain** — the case that makes this screen
  mandatory rather than optional

An empty exception list pushes no command and shows no screen. **You never see an import screen you
did not cause.**

Its form when it does appear is unchanged from the brainstorm: a `DialScreen.Content.list`, bulk by
default, per-item drop by nudging the row — the vocabulary rows already use for trim, move, delete
and share. Nothing is silently discarded; a skipped row keeps its place and states its reason,
because a file that vanishes without explanation is what #41 and #33 were both about.

Arrival is a `DialCommand` pushed by `DialViewModel` when the drain finds exceptions, so
`DialNavigator` stays a pure state machine reacting only to commands. It is navigation only:
**playback is untouched.**

---

## 7. Architecture

Layering follows `ARCHITECTURE.md` and the CLAUDE.md trigger table. Nothing here meets the bar for a
Repository, a DTO or a UseCase: one source (the filesystem), and a wire format we own.

### `Domain/` — pure Foundation, no I/O

| Type | Holds |
|---|---|
| `ImportInbox` | What is pending, arrival order, which rows are exceptions and why |
| `InboxManifest` | The `{destination}` record's shape, and its decode — including the absent/corrupt case |
| `InboxBatch` | Which directory names are committed vs `.partial`, as a predicate |

`ImportDedupe` and `ImportFilter` are reused unchanged. `ImportFilter.isAudio` is the non-audio test;
`ImportFilter.isStaged` already encodes "ours to consume, so move rather than copy".

### `Features/Files/` — the I/O half

`InboxDrain` — enumerate committed batches, resolve the destination, move each file via
`OpenInImport.run(url:into:)`. That function is already the drain: #41 taught it to consume a queue
it owns and to test identity by bytes rather than by name. **No second import path is introduced.**

`FolderManifestWriter` — writes `group/folders.json` when the tree changes. Small, and the only new
thing the app owes the extension.

### The new target

`SonicPlayerShare`, bundle ID `com.hasan.sonicplayer.share`, App Group
`group.com.hasan.sonicplayer` on both. `NSExtensionActivationRule` restricted to audio.

**It is deliberately thin.** It reads a JSON list, draws a picker, copies files, renames a directory.
No library access, no dedupe, no naming decisions. This is not minimalism for its own sake: share
extensions run under a hard memory cap and are killed without ceremony, and logic there is logic in
a process that cannot be debugged and whose tests would need a host app.

Copies go through `NSItemProvider.loadFileRepresentation` and `FileManager` — **never by loading
`Data`.** Reading an hour-long lecture into memory in an extension is a kill.

### Localization

The picker is new user-facing UI and needs all nine shipped languages, RTL verified. Extensions do
not inherit the app's `Localizable.xcstrings` automatically — the resource must be a member of the
extension target or shared deliberately. This is the largest single item that is not architecture.

---

## 8. Failure modes, designed rather than discovered

| Case | Behaviour |
|---|---|
| Storage full | The copy throws, the row states *no space*, the file stays queued. No `try?` swallowing it (#33). |
| Killed mid-drain | Moved files are in the library, the rest are still queued, next activation resumes. |
| Share while app is draining | Batch isolation plus the atomic rename; the drain cannot see a partial batch. |
| Destination folder deleted meanwhile | Exception row; the user re-picks. The only case that makes the review screen mandatory. |
| Manifest missing or corrupt | Treated as *no destination chosen* — falls back to the library root as an exception row, never discarded. |
| `folders.json` missing | Fresh install, or the app has not run since the group was created. The picker shows the library root alone and still works; it is a degraded list, never a blocked share. |
| Non-audio past the activation rule | Row states *not audio*, defaults to skipped, is not deleted silently. |
| Duplicate | `ImportDedupe` marks it, defaults to skipped, user can override — a shared name is not a shared file (#41). |
| Inbox never drained | Bounded by the user opening the app. Not solved here; the exception screen shows the count. |

---

## 9. Testing

Swift Testing, `.test` clients, no XCTest and no third-party anything (#27, #20).

- `ImportInbox`, `InboxManifest`, `InboxBatch` — pure, so the interesting rules are testable with no
  filesystem: ordering, exception classification, the `.partial` predicate, a corrupt manifest.
- `InboxDrain` — against a temp directory, including the interrupted case (drain half a batch, run
  again, assert no duplication and no loss).
- `DialNavigator` — the exception command produces the exception screen; an empty exception list
  produces no screen at all.
- **The extension itself is not unit-tested, and that is the argument for its thinness restated.**
  If it grows enough to need tests, the growth is the bug.

---

## 10. Risks

### The version now lives in two Info.plists

CLAUDE.md states the version lives in `SonicPlayer/Info.plist` **and nowhere else**, with a guard
step failing the run if `MARKETING_VERSION` reappears. An embedded extension has its own
`CFBundleShortVersionString` and `CFBundleVersion`, and App Store Connect **rejects an upload where
they disagree with the host app's**. So a second location is unavoidable.

Resolution in keeping with how this repo already handles it: the extension's plist carries literal
values, and **the existing guard step is extended to assert both keys equal the app's**. A guard, not
a convention — the same answer #20's cleanup reached.

### Signing and distribution

CI uses automatic signing with `-allowProvisioningUpdates` and an App Store Connect API key, so a new
target's profile should be created by the runner rather than managed by hand. The App Group
capability on both App IDs is the part most likely to need a one-time console action. The
entitlements file is empty today, so both App Group entries are new.

**This pipeline has been wrong twice, both times discovered after an upload** (`swift-tools-version`
resolution, then ITMS-90111 unsupported SDK against a build number that could never be reused).
Mitigation is already built: run the workflow manually with **dry_run** checked, which archives and
exports — where signing happens — and skips the upload. **Do this before the PR merges, not after.**

### The picker is a second UI

Accepted in §4. It is sliced on its own so it can be cut back to a flat folder list if it starts
growing a hierarchy browser.

---

## 11. Slicing

Order chosen so the riskiest thing is proven first and nothing is built on an unsigned foundation.

1. **The empty target, signed.** `SonicPlayerShare` doing nothing but appearing in the share sheet,
   plus the App Group on both, plus the extended version guard. Proven by a **dry-run workflow**.
   ← **done**, merged in PR #113. Chosen first because a signing failure is the only cost in this
   epic that cannot be undone, and it earned it: the App Group needed portal registration CI cannot
   do, the account had silently filled its 12-certificate cap, and the build number was stale.
2. **The queue.** Extension copies files to the inbox with a root-destination manifest; `InboxDrain`
   and the `Domain/` types file them. No picker yet — everything lands at the library root.
   ← **in progress on `gh-112-share-queue`.** The extension shows a spinner and a system close
   button, so no strings of ours ship ahead of slice 5. The queue contract is stated in both targets and policed by
   `ShareInboxLayoutAgreementTests`. Removing the `SHARE-EXTENSION-STUB` marker here is what
   unblocks TestFlight, which slice 1's guard had deliberately closed.
3. **The picker.** `folders.json`, the extension's folder screen, the destination honoured.
4. **The exception screen.** Duplicates, non-audio, failures, missing destination.
5. **Localization** across nine languages, RTL verified.

Slice 2 is shippable on its own and already beats today's buried *Copy to* entry.

---

## 12. Open questions for implementation

- **Does the picker need nested folders, or is a flat list of top-level folders enough?** Flat is
  proposed. The library is shallow in practice, and a tree in a share sheet is a browser.
- **Should the extension offer "New folder"?** Proposed: no, in v1 — it would be an intent the app
  fulfils later, and the failure case (name taken meanwhile) buys an exception row for a rare want.
- **Where does the last-used destination live**, and should it be the default next time? Almost
  certainly yes; the store is unclear, and `session.json` is a compatibility boundary that should not
  absorb it.
- **`nudge left to drop` on the exception screen is asserted, not tested.** It is consistent with
  rows elsewhere; whether it feels right is a device question.
