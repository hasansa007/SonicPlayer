import Foundation
import Testing

@testable import SonicPlayer

/// The home menu's shape, and the two rules that decide it (#6).
///
/// Split from `DialScreenshotTests` because that suite pins the *design's* eight screens against the
/// spec, and these pin the rules that survive the design changing — where things live, and what
/// makes a row a card.
@Suite
struct DialHomeMenuTests {

    private func list(_ navigator: DialNavigator) -> DialScreen.List? {
        guard case .list(let list) = navigator.screen.content else {
            Issue.record("expected a list, got \(navigator.screen.content)")
            return nil
        }
        return list
    }

    // MARK: - Cards are a property of the screen, not of the row count

    /// The regression the old `rows.count <= 2` rule had, stated directly.
    ///
    /// The library home is two rows with nothing loaded and three with something playing, so a
    /// count-derived rule made the entire menu stop being cards the moment audio started — a style
    /// flip caused by state that has nothing to do with this screen.
    @Test func theHomeMenuIsCardsAtEveryRowCount() {
        // The real shapes: Library + Record with nothing loaded, and Now Playing ahead of them once
        // something is. Built here rather than via `DialSample.sections`, whose five rows would let
        // this pass without ever crossing the old rule's threshold.
        let library = DialContent.Section(id: "recordings", icon: .library, title: "Library", destination: .recordings)
        let record = DialContent.Section(id: "record", icon: .recording, title: "Record", destination: .recording)
        let nowPlaying = DialContent.Section(id: "nowPlaying", icon: .session, title: "Now Playing", destination: .nowPlaying)

        for sections in [[library, record], [nowPlaying, library, record]] {
            let navigator = DialNavigator(content: DialContent(sections: sections), root: .library)

            #expect(list(navigator)?.rows.count == sections.count)
            #expect(
                list(navigator)?.isProminent == true,
                "\(sections.count) rows: the home menu is cards regardless of how many"
            )
        }
    }

    /// The other half: a short list is still a list. Two recordings are not a menu, and under the
    /// old rule they rendered as one.
    @Test func aShortRecordingsListIsNotCards() {
        let navigator = DialSample.inRecordings(recordingCount: 2)

        #expect(list(navigator)?.rows.count == 3, "two files and the Import row")
        #expect(list(navigator)?.isProminent == false, "two recordings are a list, not a menu")
    }

    /// The delete guard is a list of two verbs, not a menu of destinations.
    @Test func theDeleteGuardIsNotCards() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.action("delete"))

        #expect(list(navigator)?.isProminent == false)
    }

    // MARK: - Import belongs to the library, not to home

    /// A library is the place you add to. Home is a menu of destinations, and Import is not one.
    @Test func importIsARowOnTheLibrary_notOnHome() {
        let home = DialSample.navigator()
        #expect(list(home)?.rows.contains { $0.id == "import" } == false)
        #expect(!home.screen.actions.contains { $0.id == "import" })

        let library = DialSample.inRecordings()
        #expect(list(library)?.rows.first?.id == "import")
    }

    /// **The corner label follows you down, which is why it outlived the row that replaced it.**
    /// The row could name the track and the corner cannot — but the row only existed on home, so
    /// two levels into the library there was no visible way back to what was playing.
    @Test func theCornerReportsPlaybackWhereverYouCanStillBeBrowsing() {
        #expect(DialSample.navigator().screen.chrome.status == "20:34 ▸ playing")
        #expect(DialSample.inRecordings().screen.chrome.status == "20:34 ▸ playing")

        var guarding = DialSample.inRecordings()
        _ = guarding.receive(.action("delete"))
        #expect(guarding.screen.chrome.status == "20:34 ▸ playing")
    }

    /// Absent where it would be the destination, or stale on arrival: Recording and Edit both pause
    /// playback as you enter, so a line calling it playing is wrong by the time it is drawn.
    @Test func theCornerIsSilentWhereItWouldLie() {
        var nowPlaying = DialSample.navigator()
        _ = nowPlaying.receive(.hold)
        #expect(nowPlaying.screen.chrome.status == nil)

        var editing = DialSample.inRecordings()
        _ = editing.receive(.doublePress)
        #expect(editing.screen.chrome.status == nil)

        #expect(DialSample.whileRecording().screen.chrome.status == nil)
    }
}
