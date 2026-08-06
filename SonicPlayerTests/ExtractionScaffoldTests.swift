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
/// restructured — and `.timeUpdate` and `.previousTrack` were both restructured in #11.
///
/// They are TCA-coupled on purpose. Being disposable is what makes that acceptable:
///
///   .timeUpdate / .previousTrack / .toggleRepeatMode   die with PlayerFeature   -> #15
///   the delete/move session clearing                   dies with AppFeature     -> #19
///
/// Delete each block when its reducer goes, rather than porting it.
@Suite(.serialized)
struct ExtractionScaffoldTests {

    private func file(_ name: String) -> AudioFile {
        AudioFile(url: URL(fileURLWithPath: "/Docs/\(name).mp3"),
            title: name, duration: 100, fileSize: 1, format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0))
    }

    @MainActor
    private func playerStore(_ mutate: (inout PlayerFeature.State) -> Void) -> TestStore<PlayerFeature.State, PlayerFeature.Action> {
        var state = PlayerFeature.State()
        mutate(&state)
        let store = TestStore(initialState: state) {
            PlayerFeature()
        } withDependencies: {
            $0.defaultFileStorage = .inMemory
            // Stepping back loads a track, which reaches prepare/play and the artwork fetch.
            // The whole surface has to be stubbed or the unimplemented client fails the test.
            $0.audioPlayer.prepare = { _ in }
            $0.audioPlayer.play = { _ in }
            $0.audioPlayer.seek = { _ in }
            $0.audioPlayer.resume = {}
            $0.audioPlayer.pause = {}
            $0.audioPlayer.stop = {}
            $0.audioPlayer.setRate = { _ in }
            $0.audioPlayer.duration = { 100 }
            $0.audioPlayer.isPlaying = { false }
            $0.audioPlayer.updateNowPlaying = {}
            $0.audioPlayer.setRemoteHandlers = { _, _ in }
            $0.audioPlayer.timeUpdates = { .finished }
            $0.artworkClient.getArtwork = { _ in nil }
            $0.artworkClient.getColors = { _, _, _ in [] }
        }
        store.exhaustivity = .off
        return store
    }

    // MARK: - QueueMath.decideOnTrackEnd, through PlayerFeature.timeUpdate

    /// The branch is only entered while playing. This is the guard that keeps the periodic
    /// now-playing work running instead of being swallowed by the end-of-track path.
    @MainActor
    @Test func test_timeUpdate_whilePaused_doesNotStopPlayback() async {
        let a = file("A")
        let store = playerStore {
            $0.currentTrack = a; $0.queue = [a]; $0.currentIndex = 0
            $0.duration = 100; $0.isPlaying = false
        }

        await store.send(.timeUpdate(99.9))

        #expect(!(store.state.isPlaying))
        #expect(store.state.currentTime == 99.9, "position must still be recorded")
    }

    @MainActor
    @Test func test_timeUpdate_midTrack_justRecordsPosition() async {
        let a = file("A"), b = file("B")
        let store = playerStore {
            $0.currentTrack = a; $0.queue = [a, b]; $0.currentIndex = 0
            $0.duration = 100; $0.isPlaying = true
        }

        await store.send(.timeUpdate(40))

        #expect(store.state.currentTime == 40)
        #expect(store.state.isPlaying)
    }

    @MainActor
    @Test func test_timeUpdate_atEndOfQueue_stopsAndParksAtTheEnd() async {
        let a = file("A")
        let store = playerStore {
            $0.currentTrack = a; $0.queue = [a]; $0.currentIndex = 0
            $0.duration = 100; $0.isPlaying = true; $0.repeatMode = .off
        }

        await store.send(.timeUpdate(99.9))

        #expect(!(store.state.isPlaying))
        #expect(store.state.currentTime == 100, "parks at duration, not at the tick time")
    }

    @MainActor
    @Test func test_timeUpdate_repeatOne_seeksBackToZeroAndKeepsPlaying() async {
        let a = file("A")
        let store = playerStore {
            $0.currentTrack = a; $0.queue = [a]; $0.currentIndex = 0
            $0.duration = 100; $0.isPlaying = true; $0.repeatMode = .one
        }

        await store.send(.timeUpdate(99.9))

        #expect(store.state.currentTime == 0)
        #expect(store.state.isPlaying, "repeat-one must not pause")
    }

    // MARK: - QueueMath.decideOnPrevious, through PlayerFeature.previousTrack

    @MainActor
    @Test func test_previousTrack_pastThreeSeconds_restartsWithoutChangingIndex() async {
        let a = file("A"), b = file("B")
        let store = playerStore {
            $0.currentTrack = b; $0.queue = [a, b]; $0.currentIndex = 1
            $0.duration = 100; $0.currentTime = 10
        }

        await store.send(.previousTrack)
        // `.restart` is delivered as Effect.send(.seekToPosition(0)); on a TestStore that is a
        // received action, so the state does not reflect it until it is taken off the queue.
        await store.receive(\.seekToPosition)

        #expect(store.state.currentIndex == 1, "must not step back")
        #expect(store.state.currentTime == 0)
    }

    @MainActor
    @Test func test_previousTrack_earlyInTheTrack_stepsBack() async {
        let a = file("A"), b = file("B")
        let store = playerStore {
            $0.currentTrack = b; $0.queue = [a, b]; $0.currentIndex = 1
            $0.duration = 100; $0.currentTime = 1
        }

        await store.send(.previousTrack)

        #expect(store.state.currentIndex == 0)
    }

    @MainActor
    @Test func test_previousTrack_onFirstTrack_restartsRatherThanUnderflowing() async {
        let a = file("A")
        let store = playerStore {
            $0.currentTrack = a; $0.queue = [a]; $0.currentIndex = 0
            $0.duration = 100; $0.currentTime = 1
        }

        await store.send(.previousTrack)

        #expect(store.state.currentIndex == 0)
    }

    // MARK: - QueueMath.nextRepeatMode, through PlayerFeature.toggleRepeatMode

    @MainActor
    @Test func test_toggleRepeatMode_cyclesOffAllOneOff() async {
        let store = playerStore { $0.repeatMode = .off }

        await store.send(.toggleRepeatMode)
        #expect(store.state.repeatMode == .all)
        await store.send(.toggleRepeatMode)
        #expect(store.state.repeatMode == .one)
        await store.send(.toggleRepeatMode)
        #expect(store.state.repeatMode == .off)
    }

    // MARK: - PathMatching, through AppFeature's delete

    /// Regression test for #22.
    ///
    /// Deleting the folder the playing track lives in must clear the session. It did not,
    /// because `CollectionsFeature` runs first (a `Scope` child precedes the parent's `Reduce`)
    /// and clears `selectedItems` as it starts, so `AppFeature` evaluated `PathMatching` against
    /// an empty set. The items now travel in `.willRemoveItems` instead of being read back out
    /// of state.
    @MainActor
    @Test func test_deletingTheFolderContainingTheTrack_clearsTheSession() async {
        let track = AudioFile(url: URL(fileURLWithPath: "/Docs/Podcasts/Ep1.mp3"),
            title: "Ep1", duration: 100, fileSize: 1, format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0))
        let folderURL = URL(fileURLWithPath: "/Docs/Podcasts")
        let folder = CollectionItem(id: folderURL, url: folderURL, name: "Podcasts",
            creationDate: Date(timeIntervalSince1970: 0))

        var state = AppFeature.State()
        state.player.currentTrack = track
        state.filesRoot.selectedItems = [.folder(folder)]
        // The alert must actually be presented: TCA rejects a presentation action when the
        // destination state is absent, so setting selectedItems alone is not enough.
        state.filesRoot.alert = AlertState {
            TextState("Delete?")
        } actions: {
            ButtonState(role: .destructive, action: .confirmDelete) { TextState("Delete") }
        }

        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.defaultFileStorage = .inMemory
            $0.fileManager.listItems = { _ in [] }
            $0.fileManager.deleteItem = { _ in }
            $0.audioPlayer.stop = {}
        }
        store.exhaustivity = .off

        await store.send(.filesRoot(.alert(.presented(.confirmDelete))))
        await store.receive(\.filesRoot.willRemoveItems)
        await store.receive(\.player.clearSession)

        #expect(store.state.player.currentTrack == nil, "Deleting the folder the playing track lives in must clear the session (#22).")
        #expect(store.state.filesRoot.selectedItems.isEmpty, "The child still clears its selection — the parent just no longer depends on it.")
    }

    /// #22 covered the move path too, and nothing tested it before.
    @MainActor
    @Test func test_movingTheTrackAwayClearsTheSession() async {
        let track = AudioFile(url: URL(fileURLWithPath: "/Docs/Podcasts/Ep1.mp3"),
            title: "Ep1", duration: 100, fileSize: 1, format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0))

        var state = AppFeature.State()
        state.player.currentTrack = track
        state.filesRoot.itemsToMove = [.file(track)]

        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.defaultFileStorage = .inMemory
            $0.fileManager.listItems = { _ in [] }
            $0.audioPlayer.stop = {}
        }
        store.exhaustivity = .off

        await store.send(.filesRoot(.moveToDestination(URL(fileURLWithPath: "/Docs/Archive"))))
        await store.receive(\.filesRoot.willRemoveItems)
        await store.receive(\.player.clearSession)

        #expect(store.state.player.currentTrack == nil)
    }

    /// The predicate must still discriminate — moving an unrelated file must not stop playback.
    @MainActor
    @Test func test_movingAnUnrelatedFileLeavesThePlayerAlone() async {
        let playing = AudioFile(url: URL(fileURLWithPath: "/Docs/Podcasts/Ep1.mp3"),
            title: "Ep1", duration: 100, fileSize: 1, format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0))
        let other = AudioFile(url: URL(fileURLWithPath: "/Docs/Music/Song.mp3"),
            title: "Song", duration: 100, fileSize: 1, format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0))

        var state = AppFeature.State()
        state.player.currentTrack = playing
        state.filesRoot.itemsToMove = [.file(other)]

        let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
            $0.defaultFileStorage = .inMemory
            $0.fileManager.listItems = { _ in [] }
            $0.audioPlayer.stop = {}
        }
        store.exhaustivity = .off

        await store.send(.filesRoot(.moveToDestination(URL(fileURLWithPath: "/Docs/Archive"))))
        await store.receive(\.filesRoot.willRemoveItems)

        #expect(store.state.player.currentTrack != nil, "Moving an unrelated file must not stop playback.")
    }
}
