import ComposableArchitecture
import XCTest

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
final class ExtractionScaffoldTests: XCTestCase {

    private func file(_ name: String) -> AudioFile {
        AudioFile(
            url: URL(fileURLWithPath: "/Docs/\(name).mp3"),
            title: name, duration: 100, fileSize: 1, format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0)
        )
    }

    @MainActor
    private func playerStore(
        _ mutate: (inout PlayerFeature.State) -> Void
    ) -> TestStore<PlayerFeature.State, PlayerFeature.Action> {
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
    func test_timeUpdate_whilePaused_doesNotStopPlayback() async {
        let a = file("A")
        let store = playerStore {
            $0.currentTrack = a; $0.queue = [a]; $0.currentIndex = 0
            $0.duration = 100; $0.isPlaying = false
        }

        await store.send(.timeUpdate(99.9))

        XCTAssertFalse(store.state.isPlaying)
        XCTAssertEqual(store.state.currentTime, 99.9, "position must still be recorded")
    }

    @MainActor
    func test_timeUpdate_midTrack_justRecordsPosition() async {
        let a = file("A"), b = file("B")
        let store = playerStore {
            $0.currentTrack = a; $0.queue = [a, b]; $0.currentIndex = 0
            $0.duration = 100; $0.isPlaying = true
        }

        await store.send(.timeUpdate(40))

        XCTAssertEqual(store.state.currentTime, 40)
        XCTAssertTrue(store.state.isPlaying)
    }

    @MainActor
    func test_timeUpdate_atEndOfQueue_stopsAndParksAtTheEnd() async {
        let a = file("A")
        let store = playerStore {
            $0.currentTrack = a; $0.queue = [a]; $0.currentIndex = 0
            $0.duration = 100; $0.isPlaying = true; $0.repeatMode = .off
        }

        await store.send(.timeUpdate(99.9))

        XCTAssertFalse(store.state.isPlaying)
        XCTAssertEqual(store.state.currentTime, 100, "parks at duration, not at the tick time")
    }

    @MainActor
    func test_timeUpdate_repeatOne_seeksBackToZeroAndKeepsPlaying() async {
        let a = file("A")
        let store = playerStore {
            $0.currentTrack = a; $0.queue = [a]; $0.currentIndex = 0
            $0.duration = 100; $0.isPlaying = true; $0.repeatMode = .one
        }

        await store.send(.timeUpdate(99.9))

        XCTAssertEqual(store.state.currentTime, 0)
        XCTAssertTrue(store.state.isPlaying, "repeat-one must not pause")
    }

    // MARK: - QueueMath.decideOnPrevious, through PlayerFeature.previousTrack

    @MainActor
    func test_previousTrack_pastThreeSeconds_restartsWithoutChangingIndex() async {
        let a = file("A"), b = file("B")
        let store = playerStore {
            $0.currentTrack = b; $0.queue = [a, b]; $0.currentIndex = 1
            $0.duration = 100; $0.currentTime = 10
        }

        await store.send(.previousTrack)
        // `.restart` is delivered as Effect.send(.seekToPosition(0)); on a TestStore that is a
        // received action, so the state does not reflect it until it is taken off the queue.
        await store.receive(\.seekToPosition)

        XCTAssertEqual(store.state.currentIndex, 1, "must not step back")
        XCTAssertEqual(store.state.currentTime, 0)
    }

    @MainActor
    func test_previousTrack_earlyInTheTrack_stepsBack() async {
        let a = file("A"), b = file("B")
        let store = playerStore {
            $0.currentTrack = b; $0.queue = [a, b]; $0.currentIndex = 1
            $0.duration = 100; $0.currentTime = 1
        }

        await store.send(.previousTrack)

        XCTAssertEqual(store.state.currentIndex, 0)
    }

    @MainActor
    func test_previousTrack_onFirstTrack_restartsRatherThanUnderflowing() async {
        let a = file("A")
        let store = playerStore {
            $0.currentTrack = a; $0.queue = [a]; $0.currentIndex = 0
            $0.duration = 100; $0.currentTime = 1
        }

        await store.send(.previousTrack)

        XCTAssertEqual(store.state.currentIndex, 0)
    }

    // MARK: - QueueMath.nextRepeatMode, through PlayerFeature.toggleRepeatMode

    @MainActor
    func test_toggleRepeatMode_cyclesOffAllOneOff() async {
        let store = playerStore { $0.repeatMode = .off }

        await store.send(.toggleRepeatMode)
        XCTAssertEqual(store.state.repeatMode, .all)
        await store.send(.toggleRepeatMode)
        XCTAssertEqual(store.state.repeatMode, .one)
        await store.send(.toggleRepeatMode)
        XCTAssertEqual(store.state.repeatMode, .off)
    }

    // MARK: - PathMatching, through AppFeature's delete

    /// # Pins a BUG, not the intended behaviour — see #22.
    ///
    /// Deleting the folder the playing track lives in is *supposed* to clear the session. It
    /// does not. `CollectionsFeature` handles the same action first and calls
    /// `state.selectedItems.removeAll()` (`CollectionsFeature.swift:531`), and in TCA a `Scope`
    /// child runs before the parent's `Reduce` — so `AppFeature` evaluates `PathMatching`
    /// against an empty set and never sends `.clearSession`.
    ///
    /// This asserts what the app currently does, because #11 is behaviour-preserving by
    /// contract and a characterization test that asserted the *intended* behaviour would fail
    /// for the right reason at the wrong time. **When #22 is fixed, invert this test.**
    ///
    /// Note the `Domain` tests for `PathMatching` all pass: the predicate is correct, it is
    /// simply never given the data. Only driving the reducer exposes that.
    @MainActor
    func test_deletingTheFolderContainingTheTrack_doesNotClearTheSession_bug22() async {
        let track = AudioFile(
            url: URL(fileURLWithPath: "/Docs/Podcasts/Ep1.mp3"),
            title: "Ep1", duration: 100, fileSize: 1, format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0)
        )
        let folderURL = URL(fileURLWithPath: "/Docs/Podcasts")
        let folder = CollectionItem(
            id: folderURL, url: folderURL, name: "Podcasts",
            creationDate: Date(timeIntervalSince1970: 0)
        )

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
        await store.finish()

        XCTAssertNotNil(
            store.state.player.currentTrack,
            """
            Currently the session survives the delete (#22). If this now fails, the bug has been \
            fixed — invert the assertion to XCTAssertNil and close this out.
            """
        )
        XCTAssertTrue(
            store.state.filesRoot.selectedItems.isEmpty,
            "The child clearing selectedItems is what starves the parent's check."
        )
    }
}
