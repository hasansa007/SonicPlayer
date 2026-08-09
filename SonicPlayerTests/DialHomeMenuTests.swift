import Foundation
import Testing

@testable import SonicPlayer

/// The home menu's shape, and the two rules that decide it (#6).
///
/// Split from `DialScreenshotTests` because that suite pins the *design's* eight screens against the
/// spec, and these pin the rules that survive the design changing — where Import lives, and what
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

        #expect(list(navigator)?.rows.count == 2)
        #expect(list(navigator)?.isProminent == false, "two recordings are a list, not a menu")
    }

    @Test func theActionsMenuIsNotCards() {
        var navigator = DialSample.inRecordings()
        _ = navigator.receive(.action("more"))

        #expect(list(navigator)?.isProminent == false)
    }

    // MARK: - Import moved onto the library

    @Test func importIsAChipOnTheLibrary_notARowOnHome() {
        let home = DialSample.navigator()
        #expect(home.screen.actions.isEmpty, "home is a menu of destinations, not of file operations")

        let library = DialSample.inRecordings()
        #expect(library.screen.actions.map(\.id) == ["import"])
    }

    @Test func theImportChipAsksTheHostToImport() {
        var navigator = DialSample.inRecordings()

        let effects = navigator.receive(.action("import"))

        #expect(effects.contains(.importFiles))
    }

    /// Import must not navigate. The picker belongs to the host and the files land in the list you
    /// are looking at, so leaving it would be a round trip back to where you already were.
    @Test func importingStaysOnTheLibrary() {
        var navigator = DialSample.inRecordings()

        _ = navigator.receive(.action("import"))

        #expect(navigator.screen.chrome.breadcrumb == ["LIBRARY", "RECORDINGS"])
    }

    /// The empty library is the state where importing matters most, and the state a row could not
    /// have served — there is no list to be a row in.
    @Test func theEmptyLibraryCanStillImport() {
        var navigator = DialSample.navigator(recordingCount: 0)
        _ = navigator.receive(.tick(1))
        _ = navigator.receive(.press)

        #expect(navigator.screen.actions.map(\.id) == ["import", "record"])

        let effects = navigator.receive(.action("import"))
        #expect(effects.contains(.importFiles))
    }
}
