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
    /// Home is exactly two rows now — the fork — so the count it once flipped at cannot be reached
    /// from data at all. Kept as an assertion that `isProminent` is a property of *which screen
    /// this is* rather than of how many rows it happens to have.
    ///
    /// **And it is `false` everywhere.** Home was two square tiles for a day and went back to rows,
    /// so that every screen's card is the same height and the wheel underneath never moves. The
    /// tiles are what `DialCardView` was for; nothing renders it now.
    @Test func theHomeMenuIsRowsLikeEveryOtherScreen() {
        let navigator = DialSample.navigator()

        #expect(list(navigator)?.rows.map(\.id) == ["listen", "record"])
        #expect(list(navigator)?.isProminent == false, "rows, whatever is in the library")
        #expect(list(DialSample.navigator(recordingCount: 0))?.isProminent == false)
    }

    /// The other half: a short list is still a list. Two recordings are not a menu, and under the
    /// old rule they rendered as one.
    @Test func aShortRecordingsListIsNotCards() {
        let navigator = DialSample.inRecordings(recordingCount: 2)

        #expect(list(navigator)?.rows.count == 2, "two files, and the list holds nothing else")
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
    /// **Import is pinned above the library, and absent from home.** It has been a home card, a
    /// library row, a pinned bottom row and a bar button; what has never changed is that it belongs
    /// to the screen it puts files into.
    @Test func importBelongsToTheLibrary_notToHome() {
        let home = DialSample.navigator()
        #expect(list(home)?.rows.contains { $0.id == "import" } == false)
        #expect(!home.screen.actions.contains { $0.id == "import" })
        #expect(home.screen.chrome.primaryAction == nil)

        #expect(DialSample.inRecordings().screen.chrome.primaryAction?.id == "import")
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

        var editing = DialSample.inRecordMode()
        _ = editing.receive(.press)
        #expect(editing.screen.chrome.status == nil)

        #expect(DialSample.whileRecording().screen.chrome.status == nil)
    }
}
