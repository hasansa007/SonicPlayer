# 3. Consume iOS's staging directory rather than de-duplicating its renames

Date: 2026-08-08
Status: Accepted
Issue: #41

## Context

`OpenInImport.run` guarded against re-importing a file by asking whether a file of the same name
was already in `Documents`:

```swift
let destination = documentsDirectory.appendingPathComponent(url.lastPathComponent)
guard !FileManager.default.fileExists(atPath: destination.path) else { return destination }
```

That guard never fired on a device. Despite `LSSupportsOpeningDocumentsInPlace = true`, a file
opened from outside a file provider is copied by iOS into `Documents/Inbox/` before `.onOpenURL`
fires — and **iOS dedupes that name itself** against whatever is already queued there. The app
copied the staged file out and left it in place, so the *next* open of the same file was staged as
`Track-1.mp3`. `Documents/Track-1.mp3` did not exist, the guard passed, and a second copy landed.
One copy per open, forever.

Two copies accumulated per open, not one: iOS's in `Inbox/`, and ours in the root. `Documents/Inbox`
was also listed by `FileManagerClient.listItems` like any other directory — it is not hidden, so
`.skipsHiddenFiles` does not exclude it — and appeared on Home as a collection the user never made.

## Decision

**Consume what iOS staged; copy everything else.** When the handed-over URL is inside our own
`Documents/Inbox`, move it to its destination — or, when the destination already exists, delete it.
When the URL is anywhere else, copy as before.

Draining the queue removes the **cause** of the rename instead of trying to reverse it. With the
staging directory empty, iOS has nothing to dedupe against, so the next hand-off arrives under its
own name and the existing guard works as it always claimed to. No suffix arithmetic exists anywhere
in the fix.

The two predicates — *is this the staging directory* and *is this file inside it* — are pure path
arithmetic and live in `Domain/ImportFilter`, next to the other import decisions. `isStaged`
delegates its prefix test to `PathMatching.isAffected`, whose trailing-separator subtlety
(`/Music/Rock` must not match `/Music/Rocks`) is load-bearing here too. Both resolve symlinks on
both sides, because `documentsDirectory()` and a handed-over URL routinely disagree on `/var` vs
`/private/var`, and a comparison across that difference answers "no" to every question without ever
failing.

`listItems` filters the staging directory out of its listing.

### Why the move is conditional

`LSSupportsOpeningDocumentsInPlace` means the handed-over URL is **sometimes the user's own file**,
in iCloud Drive or on a USB drive. Moving that would take it out of their storage. Consuming is only
ever correct for what iOS staged inside our own container. `test_import_neverMovesAFileTheUserOwns`
exists to hold that line; it passes both before and after this change, because it guards against a
regression this fix could have introduced rather than reproducing the bug.

### Why `removeItem` is not fatal

The already-imported path tidies the queue with `try?`. Failing to clean our own staging directory
must not stop a file the user can already play from opening. The cost of that swallow is one
duplicate on the next open, not a lost file — and it is the only `try?` in the type, whose whole
history (#33) is about not swallowing.

## Rejected alternatives

**Content identity — hash the file and compare.** Robust to any rename, and wrong for this app. It
re-hashes audiobook-sized files on every open, and it silently dedupes two genuinely different files
whose bytes match. `FileManagerClient.live`'s `stableAudioID` is a SHA256 of the *path*, not the
contents, so it offers nothing here and would have to be joined by a real content hash.

**Strip iOS's `-N` suffix before the guard.** One line, and it corrupts the common case: a user with
a genuine `Track-1.mp3` would have it treated as a duplicate of `Track.mp3` and silently not
imported. The suffix is not a marker iOS owns — it is an ordinary filename. This alternative was
briefly encoded in the first version of the reproduction test, which hard-coded `Track-1.mp3` as the
second hand-off and therefore asserted that a distinct file must be swallowed. The test was wrong,
not the code; it now models iOS's staging rule instead of the old bug's output.

## Clearing what is already on disk

The above keeps the staging directory empty from here, but installs that predate it still hold
copies iOS left there — and the browser now filters that directory, so those files are **invisible
as well as orphaned**. That is a worse position than the bug for an existing install, so the drain
is not optional.

`AppViewModel.scenePhaseChanged` empties the directory on `scenePhase == .background`, through a new
`FileManagerClient.drainStagingDirectory`.

**Why `.background` and not launch.** A launch-time drain races `.onOpenURL`. Launching the app *by
opening a file* is precisely when a staged file is sitting in `Inbox` waiting to be imported, and
the ordering of `.onOpenURL` against the launch path is not guaranteed — the same non-determinism
`restoreSession` already has to defend against (#33). Backgrounding cannot collide with a hand-off,
because iOS stages the file when the user shares it, which is after the drain has run.

**Why synchronous.** The first version dispatched into a `Task`, and it was wrong for a reason only
running it revealed. Measured on the simulator 2026-08-08: backgrounding the app left
`Inbox/probe.m4a` in place, and the file disappeared only when the app was **re-foregrounded**. The
app suspends before the continuation is scheduled, so the drain landed on the next foreground —
which is exactly the `.onOpenURL` that follows a user sharing a file, reintroducing the race the
`.background` placement exists to avoid. A synchronous delete is guaranteed to finish inside the
background window, and costs less than the `session.json` write happening beside it on the same
line. It is the only member of `FileManagerClient` that does I/O without being `async`, for this
reason.

The unit test asserts the flag with no `await`, because "drained by the time the handler returns" is
the actual requirement — a test that polled for it passed against the broken version too.

**An in-flight import outranks the drain.** `openFromFiles` runs `OpenInImport.run` inside a
detached task, so it can still be moving a file out of `Inbox` when the app backgrounds — a large
file plus a user who switches away is the whole scenario. A drain firing then deletes the file
mid-import: the import is lost, and `openFromFiles`'s `catch` raises "Action Failed" for an open iOS
had already accepted, which is exactly the failure #33 was about. `PlayerViewModel.isImporting` is
set synchronously before the task is created, so `.onOpenURL` returning already means an import is
in flight, and `scenePhaseChanged` skips the drain while it is. Skipping costs nothing — the
leftovers are old, and the next backgrounding clears them.

### Identity is the bytes, not the name

`OpenInImport`'s contract had always been *"a name already present is treated as already imported"*,
and that heuristic is wrong in **both** directions:

| | Old behaviour | Why it is wrong |
|---|---|---|
| Same file, re-opened | not recognised | iOS renamed it in the staging directory first, so the name never matched — this is #41 itself |
| Different file, same name | treated as a duplicate | the user opens one thing and hears another; and once this branch began deleting the staged copy, the newer file was destroyed outright |

So the test is now `FileManager.contentsEqual` against the same-named candidate, and it is the only
test for "already imported". It costs nothing when the slot is free — `contentsEqual` returns false
without reading if the destination does not exist — and it runs off the main actor either way.

A file that shares a name but not its contents lands beside the existing one as `Track 2.m4a`, via
the same `UniqueNameResolver` the rest of the app names files with, so the `probe 2.m4a` shape is
already familiar on disk.

**This changes #33's stated behaviour and that is deliberate.** #33 preserved "a name already
present means already imported" as pre-existing behaviour it was not scoped to revisit. #41 is
scoped to exactly that heuristic, because the heuristic is the bug.

The destructive half was caught in review, after being introduced by this branch: beforehand that
path was a no-op that merely left the staged file behind. Turning a filename heuristic into a delete
is what made the imprecision destructive, and is what made it worth fixing properly rather than
guarding.

## Consequences

Opening the same file twice leaves one copy. The staging directory is drained on every open,
including the no-op one, so it cannot re-arm the rename, and emptied wholesale the next time the app
is backgrounded. Home no longer shows an `Inbox` collection.

`AppViewModel` now holds a `FileManagerClient`. It is the first client that type has taken, and it
is held for this alone — the drain is housekeeping for the app, which no feature owns. `AppView`'s
`.onChange(of: scenePhase)` now calls the coordinator instead of the player directly; the player
still receives the phase, forwarded.
