# Architecture

How SonicPlayer is layered, **and what it deliberately is not**. `CLAUDE.md` carries the
day-to-day conventions and points here for the reasoning; this file is the reasoning.

---

## The shape

```
View (SwiftUI)  ->  ViewModel (@Observable)  ->  Client (struct of closures)  ->  AVFoundation / FileManager

App/AppViewModel   composition root — owns every view model, wires every cross-feature edge
Domain/            pure decision logic, Foundation only, no framework
Models/            plain data types
```

Six features, all `@Observable` view models. No reducers, no `Store` — the TCA→MVVM migration
(epic #5) finished at slice 10. **The codebase is async/await throughout, not Combine.**

---

## What is absent, and why

There is **no DataSource, no UseCase and no DTO layer**, and exactly one Repository. That is a
decision, not an omission — those layers solve problems this app does not have:

| Layer | Why it is absent |
|---|---|
| Repository / DataSource | They hide *which source answered* — cache vs network. This app has one source: the filesystem. The clients already are that abstraction, substitutable by plain assignment. **One exception, taken deliberately: `PlaybackRepository` — see below.** |
| DTO | Wire formats drift from domain models. There is no wire. The only serialised type is `PlaybackSession`, whose JSON shape is pinned by test because it *is* the on-disk contract with existing installs. |
| UseCase | They hold orchestration reusable across UIs. There is one UI, and the business rules are pure functions in `Domain/` — wrapping each in a protocol and a class to call one function is ceremony. |

### Mapped against a textbook clean-architecture stack

The layers a Swift clean-architecture template usually prescribes, and where each one actually is:

| Textbook layer | Here |
|---|---|
| Entity / Domain models | **present** — `Models/` (`AudioFile`, `FileSystemItem`, `PlaybackSpeed`) and `Domain/` (`QueueMath`, `PathMatching`, `SessionCodec`, `ScrubClamp`, `SelectionSet`, `ImportFilter`, `QuickAction`, …) |
| Repository protocol | **one** — `PlaybackRepository`, in Player only (#44). Absent everywhere else; see the trigger table below |
| DataSources (remote / local) | **`Clients/` occupies this slot.** Mostly without a protocol; `FileManagerClient` also conforms to `FileManaging` so the repository can be built on a substitute |
| Repository implementation | **one** — `LivePlaybackRepository` |
| UseCase / Interactor | absent |
| ViewModel | **present** — all six features |
| View | **present** |
| DI container | **present** — `AppViewModel`, by constructor injection |
| DTO + mapping | absent |

**The DataSource slot is filled, just not with a protocol.** A client is a struct of closures with
a `.live` and a `.test`:

```swift
struct FileManagerClient {
    var listItems: @Sendable (URL?) async throws -> [FileSystemItem]
    var importFile: @Sendable (URL, URL?) async throws -> Void
    …
}
```

That buys exactly what `protocol RemoteUserDataSource` + `RemoteUserDataSourceImpl` + a mock class
buys — substitutability at the boundary — in one file instead of three, swapped by plain assignment
(`fileManager.getMetadata = { … }`) rather than by constructor wiring. Every test in the repo does
that.

**`AppViewModel` is a composition root, not a service locator.** It takes its children as
initialiser parameters; `SonicPlayerApp.app` is `static` for exactly one reason — `AppDelegate`
receives UIKit quick actions outside any view and `@State` cannot be static — and nothing else in
the app reads it. A `DIContainer.shared` with `lazy var` dependencies would make dependencies
invisible at the call site and make it impossible to build the graph twice with different
collaborators, which is what `AppViewModelTests` does on every test.

---

## When to add a layer

**Depth is decided per feature, not for the app.** A layer is added when a specific condition makes
it necessary, never because a feature feels important:

| Layer | Add it when |
|---|---|
| `Domain/` type | there is a decision statable without UI or I/O — almost always |
| Client | it touches a system framework or the filesystem |
| Repository | **two sources answer the same question** and something must choose between them |
| DTO | an external format exists **that you do not control** |
| UseCase | orchestration spans 2+ clients **and** is called from 2+ places, or must be tested without a view model |

By that test, every feature today is ViewModel + clients + `Domain/`: one source, no wire format.

### The one Repository, and why it does not meet that trigger

`PlaybackRepository` (#44) exists in Player, and **session restore has one source: the filesystem.**
The trigger above is not met. This is the exception, taken knowingly, and it is recorded here so
the next reader does not apply the table and conclude the code is wrong.

What it bought is not indirection, it is a test seam. `restoreSession` used to resolve the saved
session inline, calling `FileManager.default` twice while the view model held an injected
`FileManagerClient` — so the branch deciding whether a user resumes where they left off could not
be driven from a test. Behind the repository it can: `PlayerRestoreTests` leaves `fileManager` as
`.test`, and any filesystem call during a restore now fails the test rather than silently reaching
disk.

What it cost: `LivePlaybackRepository` is the only conformer to its protocol, and it will stay that
way until #7 or #9 introduces a second source. If those epics change shape and never do, this is
the layer to reconsider first — a Repository with one implementation forever is a wrapper.

**The StudyHub epics are where the full stack becomes correct**, and each for a different reason:

| Epic | Layer it earns | Why |
|---|---|---|
| #7 auth | Repository | Keychain and remote both answer "who is signed in" — something must choose |
| #8 upload | DTO | StudyHub's API JSON is not ours and will drift from our models |
| #9 listening | Repository | a remote course list with a local cache is the repository case exactly |

Do not retrofit those layers onto the offline features to make the codebase look uniform.
Uniformity is not the goal; each layer paying for itself is.

---

## Known costs

**Orchestration lives in view models.** `PlayerViewModel.openFromFiles` is real business logic in
the presentation layer. If a view model keeps growing, extract the orchestration into `Domain/`
rather than reaching for the full layered stack.

`restoreSession` used to be the other example and is now the worked one: its decision went to
`SessionRestorePlan` in `Domain/`, its I/O went to `PlaybackRepository`, and what stayed is the
part that genuinely coordinates two things — claiming priority over a concurrent open, and the
retry that follows (#44). Note what this did **not** buy: `PlayerViewModel` is 613 lines, down
from 615. Splitting one method out of a six-concern type makes it testable, not smaller. The size
is a separate problem and needs a separate cut — time observation and artwork are the next
candidates.

**`Domain/` is for logic you can state without I/O, not for everything that is not a view.**
`openFromFiles` shows the limit: its I/O half went to `OpenInImport` in `Features/Files/`, for the
same reason `FolderImport` does not live in `Domain/` — it is security-scoped access and a copy,
with no decision left over once those are removed. What stayed on the view model is the part that
genuinely coordinates two things: the import, and the session restore it has to outrank (#33).

**Nothing enforces the layering.** There is no module boundary, no build-time check — a view could
import `AVFoundation` tomorrow and nothing would fail. The discipline is the review, and this file.

---

## Cross-feature communication

Through a **closure wired at the composition root**, never by reading another feature's state.
`CollectionsViewModel.onWillRemoveItems` is the canonical shape, and it is that shape for a reason:
the items **travel in the call** rather than being read back, because the selection is cleared
before the removal runs (#22).

All of it is in `AppViewModel.wire()`, run once at construction. It used to be
`AppView.wireViewModels()` in `.onAppear`, which re-ran on every appearance.

The one thing not in `wire()`: `.onOpenURL` calls `app.openedFromFiles(url)` directly, because the
URL only exists at the call site.

---

## History

The app was built on **The Composable Architecture** and migrated off it feature by feature under
epic #5, finishing at slice 11 (#20). Removing it took **14 packages** with it and the project now
has none.

The clients kept their shape through all of it — a struct of closures was always substitutable by
assignment, and `@DependencyClient` was only ever generating the memberwise init and the
unimplemented test defaults. The unimplemented behaviour was worth keeping, so it is hand-written
in `SonicPlayerTests/TestClients.swift`, which is also where `.test` now lives: TCA's `DependencyKey`
had required a `testValue` visible to the app target, and nothing else did.

Two things that migration proved, worth keeping:

- **Extract `Domain/` first.** Its tests were written against reducers and survived the move to view
  models unchanged (#11). Logic with no framework in it is the part that outlives the framework.
- **A value-typed store forces mirrors.** `HomeFeature` held three copies of player state,
  resynced on four separate action taps, because scoped stores could not share a reference. Home
  holds the same `PlayerViewModel` instance now and the mirror is gone (#16).
