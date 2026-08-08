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

## Consequences

Opening the same file twice leaves one copy. The staging directory is drained on every open,
including the no-op one, so it cannot re-arm the rename. Home no longer shows an `Inbox` collection.

**Not addressed: staged files already on disk from before this change.** They are now filtered from
the browser, which means they consume space and the user can no longer see or delete them through
the app. A one-time drain at launch would clear them, and it is a delete, so it is deliberately not
done here. Recorded in `PROJECT_MAP.md` → ORPHANS & PENDING.
