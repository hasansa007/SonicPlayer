import Foundation
import Testing

@testable import SonicPlayer

/// Characterization tests for the file browser's search filter and selection rules, previously
/// inlined at four sites in `CollectionsFeature`. No TCA, no filesystem — these must survive the
/// migration of Files and Collections (#18) unchanged.
@Suite
struct SelectionSetTests {

    // MARK: - Fixtures

    /// Deterministic IDs: `AudioFile.id` defaults to a fresh `UUID`, and these items go into a
    /// `Set`, so two fixtures built from the same name have to be the same value.
    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private static func file(_ n: Int, _ title: String) -> FileSystemItem {
        .file(
            AudioFile(
                id: id(n),
                url: URL(fileURLWithPath: "/Docs/\(title).m4a"),
                title: title,
                duration: 0,
                fileSize: 0,
                format: .m4a,
                creationDate: Date(timeIntervalSince1970: 0)
            )
        )
    }

    private static func folder(_ name: String) -> FileSystemItem {
        .folder(
            CollectionItem(
                id: URL(fileURLWithPath: "/Docs/\(name)"),
                url: URL(fileURLWithPath: "/Docs/\(name)"),
                name: name,
                creationDate: Date(timeIntervalSince1970: 0)
            )
        )
    }

    private let jazz = SelectionSetTests.file(1, "Jazz Night")
    private let rock = SelectionSetTests.file(2, "Rock Ballad")
    private let talk = SelectionSetTests.file(3, "jazz talk")
    private let podcasts = SelectionSetTests.folder("Podcasts")

    private var all: [FileSystemItem] { [jazz, rock, talk, podcasts] }

    // MARK: - Filtering

    @Test func test_anEmptyQuery_returnsEverything() {
        #expect(SelectionSet.matching(all, searchText: "") == all)
    }

    @Test func test_matching_isCaseInsensitive() {
        #expect(SelectionSet.matching(all, searchText: "JAZZ") == [jazz, talk])
    }

    @Test func test_matching_isASubstringNotAPrefix() {
        #expect(SelectionSet.matching(all, searchText: "Ballad") == [rock])
    }

    @Test func test_matching_searchesFoldersByNameToo() {
        #expect(SelectionSet.matching(all, searchText: "podcast") == [podcasts])
    }

    /// Results follow the order of the input, not the alphabet — the browser's own sort is
    /// applied upstream and the filter must not disturb it.
    @Test func test_matching_preservesInputOrder() {
        #expect(SelectionSet.matching([talk, jazz], searchText: "jazz") == [talk, jazz])
    }

    @Test func test_matching_withNoResults_isEmpty() {
        #expect(SelectionSet.matching(all, searchText: "zzzz").isEmpty)
    }

    /// `localizedCaseInsensitiveContains` folds case but not accents. Pinned as pre-existing
    /// behaviour — a user searching "cafe" does not find "Café".
    @Test func test_matching_isNotDiacriticInsensitive() {
        let cafe = Self.file(4, "Café Session")
        #expect(SelectionSet.matching([cafe], searchText: "cafe").isEmpty)
    }

    // MARK: - Toggling

    @Test func test_toggling_anUnselectedItem_selectsIt() {
        #expect(SelectionSet.toggling(jazz, in: []) == [jazz])
    }

    @Test func test_toggling_aSelectedItem_deselectsIt() {
        #expect(SelectionSet.toggling(jazz, in: [jazz]).isEmpty)
    }

    @Test func test_toggling_leavesTheRestOfTheSelectionAlone() {
        #expect(SelectionSet.toggling(jazz, in: [jazz, rock]) == [rock])
    }

    @Test func test_toggling_twice_returnsToTheStartingSelection() {
        let once = SelectionSet.toggling(jazz, in: [rock])
        #expect(SelectionSet.toggling(jazz, in: once) == [rock])
    }

    // MARK: - Select all

    @Test func test_selectAll_withNoQuery_selectsEverything() {
        #expect(SelectionSet.selectingAll(all, searchText: "") == Set(all))
    }

    /// The rule worth having a test for: select-all selects what is **visible**, not everything
    /// loaded.
    @Test func test_selectAll_withAQuery_selectsOnlyTheMatches() {
        #expect(SelectionSet.selectingAll(all, searchText: "jazz") == [jazz, talk])
    }

    /// And it replaces rather than adds, so a selection made before the query was typed is
    /// silently dropped if it falls outside the matches.
    @Test func test_selectAll_replacesRatherThanExtends() {
        let selected = SelectionSet.selectingAll(all, searchText: "jazz")
        #expect(!selected.contains(rock))
    }

    @Test func test_selectAll_withNoMatches_selectsNothing() {
        #expect(SelectionSet.selectingAll(all, searchText: "zzzz").isEmpty)
    }
}
