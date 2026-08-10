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

    static let sections: [DialContent.Section] = [
        .init(id: "playlists", icon: .playlist, title: "Playlists", count: 6),
        .init(id: "recordings", icon: .recording, title: "Recordings", count: 12, destination: .recordings),
        .init(id: "sessions", icon: .session, title: "Focus Sessions", count: 24),
        .init(id: "podcasts", icon: .podcast, title: "Podcasts", count: 9),
        .init(id: "stats", icon: .stats, title: "Stats")
    ]

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
            sections: sections,
            recordings: recordings(recordingCount),
            playback: playback,
            capture: capture,
            editing: editing
        )
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

    /// Drills home → library, **landing on the first file rather than on Import.**
    ///
    /// Import is row 0 of that list, so the highlight arrives on it. Almost every test built on this
    /// helper means "I am on a file" — `press` plays, `doublePress` edits, the stick offers its menu
    /// — so the tick belongs here rather than being repeated, and forgotten, in twenty places.
    /// `DialImportRowTests` is where the Import row itself is exercised.
    static func inRecordings(recordingCount: Int = 12) -> DialNavigator {
        var navigator = navigator(recordingCount: recordingCount)
        _ = navigator.receive(.tick(1))     // Playlists → Recordings
        _ = navigator.receive(.press)
        _ = navigator.receive(.tick(1))     // Import → the first file
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
        var content = content(recordingCount: 0, capture: capture)
        content.sections = [
            .init(id: "record", icon: .recording, title: "Record", destination: .recording)
        ]
        var navigator = DialNavigator(content: content, root: .library)
        _ = navigator.receive(.press)
        return navigator
    }

    /// Library → recordings → the trim editor (1e).
    static func whileEditing() -> DialNavigator {
        var navigator = inRecordings()
        _ = navigator.receive(.doublePress)
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
        var navigator = DialSample.inRecordings()

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
        _ = navigator.receive(.press)          // opens row 5 → now playing

        _ = navigator.receive(.action("back"))

        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected the recordings list back")
            return
        }
        #expect(list.highlighted == 5, "opened from row 5 — the helper starts on 1, past Import")
    }

    @Test func aSectionWithNowhereToGoIsALimit() {
        var navigator = DialSample.navigator()
        _ = navigator.receive(.tick(4))        // Stats, which drills nowhere

        let effects = navigator.receive(.press)

        #expect(effects == [.feedback(.limit)])
        #expect(navigator.screen.chrome.breadcrumb == ["HOME"])
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
    @Test func theEditChipAndTheDoublePressAgree() {
        var byChip = DialSample.inRecordings()
        var byWheel = DialSample.inRecordings()

        let chipEffects = byChip.receive(.action("edit"))
        let wheelEffects = byWheel.receive(.doublePress)

        #expect(chipEffects == wheelEffects)
        #expect(byChip.screen == byWheel.screen)
        #expect(byChip.screen.chrome.breadcrumb == ["HOME", "LIBRARY", "EDIT"])
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
    @Test func onlyAScreenWithASecondMeaningDefersItsPress() {
        let library = DialSample.navigator()
        #expect(!library.screen.ring.defersPress, "the library has no double-press meaning")

        var recordings = DialSample.inRecordings()
        #expect(recordings.screen.ring.defersPress, "a highlighted recording can be edited")

        // Opening that recording lands somewhere with no second meaning, so presses go back to
        // being instant — the 300ms is paid on exactly one screen, not carried around.
        _ = recordings.receive(.press)
        #expect(!recordings.screen.ring.defersPress)
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
