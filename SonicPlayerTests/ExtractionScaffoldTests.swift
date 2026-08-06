import ComposableArchitecture
import Foundation
import Testing

@testable import SonicPlayer

/// # THROWAWAY — delete these alongside the reducers they exercise.
///
/// The `Domain/*Tests` files assert what the extracted types do. These assert something
/// different and only useful right now: that the **reducers still behave the same when routed
/// through them**. A `Domain` test passing proves the type is correct; it does not prove the
/// reducer calls it with the right arguments, or that the control flow around it survived being
/// restructured.
///
/// They are TCA-coupled on purpose. Being disposable is what makes that acceptable:
///
///   .timeUpdate / .previousTrack / .toggleRepeatMode   died with PlayerFeature  -> #15, done
///   the delete/move session clearing                   dies with AppFeature     -> #19
///
/// Delete each block when its reducer goes, rather than porting it.
///
/// ## What #15 removed, and what it did not
///
/// The eight player-routed tests are **gone, not ported** — `PlayerFeature` no longer exists, so
/// there is no reducer left to route through. Their subject matter did not go with them:
/// `QueueMathTests` already asserts every decision they covered, directly and without a
/// `TestStore`. That was the point of writing them as scaffold.
///
/// The three below are a different case and were **kept**. They pin #22, a shipped bug fix, and
/// their subject is `AppFeature`'s wiring rather than the player's. Their assertions moved from
/// *"the player cleared its session"* to *"the reducer emitted the command"*, because the
/// deciding half now lives on `PlayerViewModel` — see `PlayerViewModelTests` for that half.
@Suite(.serialized)
struct ExtractionScaffoldTests {

    // MARK: - PathMatching, through AppFeature's delete

    /// Regression test for #22.
    ///
    /// Deleting the folder the playing track lives in must clear the session. It did not,
    /// because `CollectionsFeature` runs first (a `Scope` child precedes the parent's `Reduce`)
    /// and clears `selectedItems` as it starts, so `AppFeature` evaluated `PathMatching` against
    /// an empty set. The items travel in `.willRemoveItems` instead of being read back out of
    /// state — which is the part this test exists to hold down, and the part #15 did not change.
    @MainActor
    @Test func test_deletingTheFolderContainingTheTrack_emitsTheClearCommand() async {
        let folderURL = URL(fileURLWithPath: "/Docs/Podcasts")
        let folder = CollectionItem(id: folderURL, url: folderURL, name: "Podcasts",
            creationDate: Date(timeIntervalSince1970: 0))

        var state = AppFeature.State()
        state.filesRoot.selectedItems = [.folder(folder)]
        // The alert must actually be presented: TCA rejects a presentation action when the
        // destination state is absent, so setting selectedItems alone is not enough.
        state.filesRoot.alert = AlertState {
            TextState("Delete?")
        } actions: {
            ButtonState(role: .destructive, action: .confirmDelete) { TextState("Delete") }
        }

        let store = makeStore(state)

        await store.send(.filesRoot(.alert(.presented(.confirmDelete))))
        await store.receive(\.filesRoot.willRemoveItems)

        #expect(
            store.state.commands.contains(.clearSessionIfAffected([folderURL])),
            "The removed folder must reach the player, or deleting it leaves the track playing (#22)."
        )
        #expect(
            store.state.filesRoot.selectedItems.isEmpty,
            "The child still clears its selection — the parent just no longer depends on it."
        )
    }

    /// #22 covered the move path too, and nothing tested it before.
    @MainActor
    @Test func test_movingTheTrackAway_emitsTheClearCommand() async {
        let track = file("/Docs/Podcasts/Ep1.mp3")

        var state = AppFeature.State()
        state.filesRoot.itemsToMove = [.file(track)]

        let store = makeStore(state)

        await store.send(.filesRoot(.moveToDestination(URL(fileURLWithPath: "/Docs/Archive"))))
        await store.receive(\.filesRoot.willRemoveItems)

        #expect(store.state.commands.contains(.clearSessionIfAffected([track.url])))
    }

    /// The reducer no longer discriminates — it forwards whatever is being removed and
    /// `PlayerViewModel` decides. What is still worth pinning here is that it forwards the URLs
    /// *unchanged*, since the decision downstream is only as good as its input.
    @MainActor
    @Test func test_theCommandCarriesTheRemovedURLsVerbatim() async {
        let other = file("/Docs/Music/Song.mp3")

        var state = AppFeature.State()
        state.filesRoot.itemsToMove = [.file(other)]

        let store = makeStore(state)

        await store.send(.filesRoot(.moveToDestination(URL(fileURLWithPath: "/Docs/Archive"))))
        await store.receive(\.filesRoot.willRemoveItems)

        #expect(store.state.commands == [.clearSessionIfAffected([other.url])])
    }

    // MARK: - The command channel (#15) — dies with it at #19

    /// Tapping a file plays it **with the rest of the directory as the queue**. That queue is the
    /// reason the channel exists at all: it is computed from `filesRoot.items`, which only the
    /// store has, so the view cannot call `player.loadTrack` itself.
    @MainActor
    @Test func test_tappingAFile_emitsPlayWithTheWholeDirectoryAsQueue() async {
        let a = file("/Docs/A.mp3"), b = file("/Docs/B.mp3")

        var state = AppFeature.State()
        state.filesRoot.items = [.file(a), .file(b)]

        let store = makeStore(state)

        await store.send(.filesRoot(.fileTapped(a)))

        #expect(store.state.commands == [.play(a, [a, b], .singleFile)])
    }

    /// Play All starts at the first file rather than wherever the selection was.
    @MainActor
    @Test func test_playAll_emitsPlayStartingAtTheFirstFile() async {
        let a = file("/Docs/A.mp3"), b = file("/Docs/B.mp3")

        var state = AppFeature.State()
        state.filesRoot.items = [.file(a), .file(b)]

        let store = makeStore(state)

        await store.send(.filesRoot(.playAllTapped))

        #expect(store.state.commands == [.play(a, [a, b], .singleFile)])
    }

    /// Recording takes over the shared `AVPlayer`, so opening the sheet must pause first. The
    /// reducer used to check `state.player.isPlaying` and only then send; it cannot see that any
    /// more, so it always asks and the view model no-ops when nothing is playing.
    @MainActor
    @Test func test_openingTheRecordingSheet_emitsPause() async {
        let store = makeStore(AppFeature.State())

        await store.send(.recordButtonTapped)

        #expect(store.state.commands.contains(.pauseIfPlaying))
        #expect(store.state.isRecordingSheetPresented)
    }

    /// `AppView` sends this after draining. Without it the array grows for the life of the app and
    /// every later `.onChange` replays commands that already ran.
    @MainActor
    @Test func test_commandsHandled_emptiesTheChannel() async {
        let store = makeStore(AppFeature.State())

        await store.send(.recordButtonTapped)
        #expect(!store.state.commands.isEmpty)

        await store.send(.commandsHandled)
        #expect(store.state.commands.isEmpty)
    }

    // MARK: -

    private func file(_ path: String) -> AudioFile {
        AudioFile(url: URL(fileURLWithPath: path),
            title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            duration: 100, fileSize: 1, format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0))
    }

    @MainActor
    private func makeStore(_ state: AppFeature.State) -> TestStore<AppFeature.State, AppFeature.Action> {
        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.fileManager.listItems = { _ in [] }
            $0.fileManager.deleteItem = { _ in }
        }
        store.exhaustivity = .off
        return store
    }
}
