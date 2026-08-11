import Foundation
import Testing

@testable import SonicPlayer

/// The data the eight screens in the design are drawn from, so every dial suite starts from the
/// same library rather than inventing its own.
///
/// A file-level type in the test target: visible to every `Dial*Tests` file, and not shipped.
enum DialSample {

    static func recordings(_ count: Int = 12) -> [DialContent.Item] {
        (0..<count).map { index in
            DialContent.Item(
                id: "rec-\(index)",
                title: "Recording \(index + 1)",
                duration: TimeInterval(60 * (index + 1)),
                subtitle: index == 0 ? "Today 14:02 · 2 markers" : nil
            )
        }
    }


    static let playback = DialContent.Playback(
        title: "Deep Work, Chapter 4",
        subtitle: "Cal Newport",
        position: 1234,
        duration: 2745,
        isPlaying: true,
        volume: 0.6,
        queueIndex: 2,
        queueCount: 9
    )

    /// `isGainSettable` is **true** here, which is not the default: the gain axis only exists on
    /// hardware that has one, so a sample meant to exercise it has to say so. `DialCaptureTests`
    /// covers the ordinary iPhone, where it is false and the wheel refuses.
    static let capture = DialContent.Capture(
        elapsed: 727.4,
        levels: [0.2, 0.5, 0.8, 0.42],
        gain: 0.5,
        markers: [.init(id: "m1", label: "Marker 1", time: 62)],
        isGainSettable: true
    )

    static let editable = DialContent.Editable(
        id: "rec-0",
        title: "Recording 1",
        waveform: [0.1, 0.9, 0.4, 0.7],
        duration: 600
    )

    static func content(
        recordingCount: Int = 12,
        playback: DialContent.Playback? = DialSample.playback,
        capture: DialContent.Capture? = nil,
        editing: DialContent.Editable? = DialSample.editable
    ) -> DialContent {
        DialContent(
            recordings: recordings(recordingCount),
            playback: playback,
            capture: capture,
            editing: editing
        )
    }

    /// **What a press asked to play, ignoring the queue it came with.**
    ///
    /// `.play` carries the whole ordered queue now — which is the fix for Next after a sort, and
    /// which makes `effects.contains(.play(itemID:))` impossible to write without restating the
    /// queue in every assertion. Most tests care which *track* opened; the ones that care about the
    /// queue read it explicitly.
    static func playedID(_ effects: [DialEffect]) -> String? {
        for case .play(let itemID, _) in effects { return itemID }
        return nil
    }

    static func playedQueue(_ effects: [DialEffect]) -> [String]? {
        for case .play(_, let queue) in effects { return queue }
        return nil
    }

    static func navigator(
        root: DialRoute = .recordings,
        recordingCount: Int = 12,
        playback: DialContent.Playback? = DialSample.playback,
        capture: DialContent.Capture? = nil
    ) -> DialNavigator {
        DialNavigator(
            content: content(recordingCount: recordingCount, playback: playback, capture: capture),
            root: root
        )
    }

    /// **The library, which is now the root.**
    ///
    /// This has been three things: two ticks across home's old five-section list, then one press
    /// through the Listen/Record fork, and now nothing at all. The fork is gone — one library, one
    /// meaning for the hub — so there is no navigation to do before the tests begin.
    static func inRecordings(recordingCount: Int = 12) -> DialNavigator {
        navigator(recordingCount: recordingCount)
    }

    /// Home → a capture in progress (1d), **through the Record card**, which is the only way in.
    ///
    /// It used to go home → library → the `Record` chip on the empty state. That chip is gone: the
    /// band it sat in is dead space on every other screen, so one red control appearing there only
    /// when the library was empty read as an alert rather than an offer. Recording is a card on
    /// home, like every other destination — and because the shared `sections` fixture has no such
    /// card, this builds its own.
    static func whileRecording() -> DialNavigator {
        let content = content(recordingCount: 0, capture: capture)
        var navigator = DialNavigator(content: content, root: .recordings)
        _ = navigator.receive(.action("record"))    // the Record chip → the recorder
        return navigator
    }

    /// The library → the trim editor, by the stick's up nudge.
    ///
    /// **It has been a double press, then the hub in Record mode, and is a nudge again.** The hub
    /// plays; editing is the one verb that rewrites a file, so it asks for a deliberate second
    /// gesture rather than the same press with a different history behind it.
    static func whileEditing() -> DialNavigator {
        var navigator = inRecordings()
        _ = navigator.receive(.action("edit"))
        return navigator
    }
}

/// The stack, and the breadcrumb derived from it (#6).
@Suite
struct DialNavigationTests {

    // `#expect` captures its expression in a closure, so a `mutating` call written inside one fails
    // to compile against an immutable copy. Every result below is bound to a local first.

    @Test func theRootIsTheLibrary() {
        let navigator = DialSample.navigator()

        #expect(navigator.screen.chrome.breadcrumb == ["LIBRARY"])
    }

    @Test func drillingInPushesACrumb() {
        let navigator = DialSample.inRecordings()

        #expect(navigator.screen.chrome.breadcrumb == ["LIBRARY"])
    }

    /// The point of deriving it: three levels deep, nothing had to store its own header.
    @Test func theBreadcrumbGrowsWithTheStack() {
        var navigator = DialSample.inRecordings()

        _ = navigator.receive(.action("delete"))

        #expect(navigator.screen.chrome.breadcrumb == ["LIBRARY", "DELETE"])
    }

    @Test func backPopsALevel() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.press)                   // into Now Playing

        let effects = navigator.receive(.action("back"))

        #expect(navigator.screen.chrome.breadcrumb == ["LIBRARY"])
        #expect(effects.contains(.feedback(.commit)))
    }

    /// There is nothing above the root, and turning against that must be felt.
    @Test func backAtTheRootIsALimit() {
        var navigator = DialSample.navigator()

        let effects = navigator.receive(.action("back"))

        #expect(navigator.screen.chrome.breadcrumb == ["LIBRARY"])
        #expect(effects == [.feedback(.limit)])
    }

    /// Coming back to a list you had scrolled and finding it at the top is the classic loss.
    @Test func poppingRestoresTheHighlightYouLeft() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.tick(4))
        _ = navigator.receive(.press)          // opens row 4 → now playing

        _ = navigator.receive(.action("back"))

        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected the recordings list back")
            return
        }
        #expect(list.highlighted == 4, "opened from row 4 — the helper starts on 0")
    }


    // MARK: - Hold

    @Test func holdingJumpsToNowPlayingFromAnywhere() {
        var navigator = DialSample.inRecordings()

        _ = navigator.receive(.hold)

        #expect(navigator.screen.chrome.breadcrumb == ["LIBRARY", "NOW PLAYING"])
    }

    @Test func holdingWithNothingPlayingIsALimit() {
        var navigator = DialSample.navigator(playback: nil)

        let effects = navigator.receive(.hold)

        #expect(effects == [.feedback(.limit)])
    }

    /// Holding twice must not stack two copies of the same screen.
    @Test func holdingWhileAlreadyThereDoesNotPushAgain() {
        var navigator = DialSample.navigator()
        _ = navigator.receive(.hold)

        _ = navigator.receive(.hold)

        #expect(navigator.screen.chrome.breadcrumb == ["LIBRARY", "NOW PLAYING"])
    }

    // MARK: - Touch and wheel are equals


    /// **The invariant that keeps `.doublePress` reachable at all.**
    ///
    /// The test above sends `.doublePress` on its own, and every screen test does — but a view
    /// cannot know a second press is coming. The first integration fired `.press` immediately and
    /// `.doublePress` afterwards as an escalation, which meant the navigator only ever saw the
    /// double *after* the single had already opened the recording. The guard recognising it no
    /// longer held, so the gesture did nothing on a device while all 331 tests passed.
    ///
    /// `defersPress` is the fix: the one screen with a second meaning waits to find out which press
    /// it got, and every other press fires instantly. This test is what stops that flag drifting
    /// away from the screens `doublePress()` actually handles — if they ever disagree again, the
    /// gesture dies silently a second time.
    /// **Nothing defers any more.** The wait existed for one ambiguity — a press played and a
    /// double press edited — and the mode took it: the press means one thing on each side of the
    /// fork. Every press is instant now, including the one that used to pay for the ambiguity.
    @Test func nothingDefersItsPress() {
        #expect(!DialSample.navigator().screen.ring.defersPress, "home")
        #expect(!DialSample.inRecordings().screen.ring.defersPress, "Listen")
        #expect(!DialSample.inRecordings().screen.ring.defersPress, "Record — the press *is* edit")
    }

    /// A gesture with no meaning here is silent rather than a limit: nothing was pushed against.
    @Test func aDoublePressWithNoMeaningIsSilent() {
        var navigator = DialSample.navigator()

        let effects = navigator.receive(.doublePress)

        #expect(effects.isEmpty)
    }

    @Test func anUnknownChipIsSilent() {
        var navigator = DialSample.navigator()

        let effects = navigator.receive(.action("nonsense"))

        #expect(effects.isEmpty)
    }
}
