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
        root: DialRoute = .library,
        recordingCount: Int = 12,
        playback: DialContent.Playback? = DialSample.playback,
        capture: DialContent.Capture? = nil
    ) -> DialNavigator {
        DialNavigator(
            content: content(recordingCount: recordingCount, playback: playback, capture: capture),
            root: root
        )
    }

    /// Drills home → library in **Listen** mode, landing on the first file.
    ///
    /// **Both ticks that used to be here are gone, for two different reasons.** The first stepped
    /// across home's old five-section fixture to reach `Recordings`; home is now exactly two rows —
    /// Listen and Record — so a detent there chooses the *other mode*, and every test built on this
    /// would have been editing where it meant to play. The second stepped off the Import row, which
    /// is a bar button now.
    ///
    /// Row 0 of home is Listen and row 0 of the library is the first file, so the helper is two
    /// presses and no turning.
    static func inRecordings(recordingCount: Int = 12) -> DialNavigator {
        var navigator = navigator(recordingCount: recordingCount)
        _ = navigator.receive(.press)       // home → Listen
        return navigator
    }

    /// The same library with Record's verbs over it: press opens the editor, and the stick renames,
    /// deletes and shares.
    static func inRecordMode(recordingCount: Int = 12) -> DialNavigator {
        var navigator = navigator(recordingCount: recordingCount)
        _ = navigator.receive(.tick(1))     // home → Record
        _ = navigator.receive(.press)
        return navigator
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
        var navigator = DialNavigator(content: content, root: .library)
        _ = navigator.receive(.tick(1))             // home → Record
        _ = navigator.receive(.press)               // → the library, Record's verbs
        _ = navigator.receive(.action("record"))    // the bar's Record button → the recorder
        return navigator
    }

    /// Home → Record → the trim editor.
    ///
    /// **A press, not a double press.** Editing was a second press on the library; it is what the
    /// hub does in Record mode now, which is why the deferral could go.
    static func whileEditing() -> DialNavigator {
        var navigator = inRecordMode()
        _ = navigator.receive(.press)
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

        #expect(navigator.screen.chrome.breadcrumb == ["HOME"])
    }

    @Test func drillingInPushesACrumb() {
        let navigator = DialSample.inRecordings()

        #expect(navigator.screen.chrome.breadcrumb == ["HOME", "LIBRARY"])
    }

    /// The point of deriving it: three levels deep, nothing had to store its own header.
    @Test func theBreadcrumbGrowsWithTheStack() {
        var navigator = DialSample.inRecordMode()

        _ = navigator.receive(.action("delete"))

        #expect(navigator.screen.chrome.breadcrumb == ["HOME", "LIBRARY", "DELETE"])
    }

    @Test func backPopsALevel() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.action("back"))

        #expect(navigator.screen.chrome.breadcrumb == ["HOME"])
        #expect(effects.contains(.feedback(.commit)))
    }

    /// There is nothing above the root, and turning against that must be felt.
    @Test func backAtTheRootIsALimit() {
        var navigator = DialSample.navigator()

        let effects = navigator.receive(.action("back"))

        #expect(navigator.screen.chrome.breadcrumb == ["HOME"])
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

    /// **There is no section with nowhere to go any more.** Home was a menu of five destinations,
    /// three of which led nowhere and answered with a limit. It is two jobs now, and both lead to
    /// the same place — so the state this guarded cannot be constructed.
    @Test func bothCardsLeadSomewhere() {
        for row in 0..<2 {
            var navigator = DialSample.navigator()
            if row > 0 { _ = navigator.receive(.tick(row)) }

            _ = navigator.receive(.press)

            #expect(navigator.screen.chrome.breadcrumb == ["HOME", "LIBRARY"])
        }
    }

    // MARK: - Hold

    @Test func holdingJumpsToNowPlayingFromAnywhere() {
        var navigator = DialSample.inRecordings()

        _ = navigator.receive(.hold)

        #expect(navigator.screen.chrome.breadcrumb == ["HOME", "LIBRARY", "NOW PLAYING"])
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

        #expect(navigator.screen.chrome.breadcrumb == ["HOME", "NOW PLAYING"])
    }

    // MARK: - Touch and wheel are equals

    /// The contract's rule: every double-press must also be reachable as a chip, and both must
    /// arrive at the same code.
    /// **Editing has one route now.** It was a chip and a double press, kept in agreement by this
    /// test; both are gone, and the hub in Record mode is the only way in.
    @Test func theEditorIsReachedByPressingInRecordMode() {
        var navigator = DialSample.inRecordMode()

        _ = navigator.receive(.press)

        #expect(navigator.screen.chrome.breadcrumb == ["HOME", "LIBRARY", "EDIT"])

        // `#expect` captures its expression in a closure, so a `mutating` call inside one fails to
        // compile against an immutable copy — the note at the top of this suite, in practice.
        var listening = DialSample.inRecordings()
        let doublePress = listening.receive(.doublePress)
        #expect(doublePress.isEmpty, "and nothing else reaches the editor")
    }

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
        #expect(!DialSample.inRecordMode().screen.ring.defersPress, "Record — the press *is* edit")
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
