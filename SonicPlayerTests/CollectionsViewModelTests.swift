import Foundation
import Testing

@testable import SonicPlayer

/// The last resting place of `ExtractionScaffoldTests`.
///
/// That file was written in #11 to be thrown away, and it held two things routed through reducers
/// that no longer exist. Both claims survive here, at the seam that owns them after #18:
///
/// - **#22 — removing the playing file must stop playback.** The regression was that `AppFeature`
///   read the items out of state, and the child had already cleared them. The fix was to carry
///   them in the message. That is still the claim; the message is a closure now.
/// - **the queue a tap plays with.** The `AppCommand` channel existed because the queue lived in
///   reducer state that only the store could see. It does not any more — the depth that raised
///   the tap passes its own file list out — so the tests move onto the object that does it.
///
/// Deliberately no `import ComposableArchitecture`.
@Suite(.serialized)
struct CollectionsViewModelTests {

    // MARK: - #22, the part that regressed

    /// The selection is cleared *before* the removal is announced, which is exactly what broke the
    /// original: a parent reading `selectedItems` at this point sees nothing. The items have to
    /// travel with the announcement.
    @MainActor
    @Test func test_confirmingDelete_announcesTheItemsEvenThoughSelectionIsAlreadyCleared() async {
        let model = makeModel()
        let folder = Self.folder("/Docs/Podcasts")
        model.select(.folder(folder))

        var announced: Set<FileSystemItem>?
        var selectionAtAnnouncement: Set<FileSystemItem>?
        model.onWillRemoveItems = { items in
            announced = items
            selectionAtAnnouncement = model.selectedItems
        }

        model.deleteSelectedTapped()
        model.confirmDelete()

        #expect(announced == [.folder(folder)], "The removed items must reach the player (#22).")
        #expect(selectionAtAnnouncement?.isEmpty == true,
                "Selection is cleared first — which is why reading it back instead of carrying it failed.")
    }

    @MainActor
    @Test func test_movingItemsAway_announcesThem() async {
        let model = makeModel()
        let file = Self.file("/Docs/Podcasts/Ep1.mp3")
        model.moveItemTapped(.file(file))

        var announced: Set<FileSystemItem>?
        model.onWillRemoveItems = { announced = $0 }

        model.moveToDestination(URL(fileURLWithPath: "/Docs/Archive"))

        #expect(announced == [.file(file)])
    }

    // MARK: - The queue a tap plays with

    @MainActor
    @Test func test_tappingAFile_playsItWithTheWholeDirectoryAsQueue() async {
        let a = Self.file("/Docs/A.mp3"), b = Self.file("/Docs/B.mp3")
        let model = makeModel()
        model.seed(items: [.file(a), .file(b)])

        var played: (AudioFile, [AudioFile], PlaylistSource?)?
        model.onPlay = { played = ($0, $1, $2) }

        model.fileTapped(a)

        #expect(played?.0 == a)
        #expect(played?.1 == [a, b], "The queue is this directory's files, in display order.")
    }

    @MainActor
    @Test func test_playAll_startsAtTheFirstFile() async {
        let a = Self.file("/Docs/A.mp3"), b = Self.file("/Docs/B.mp3")
        let model = makeModel()
        model.seed(items: [.file(a), .file(b)])

        var played: AudioFile?
        model.onPlay = { file, _, _ in played = file }

        model.playAllTapped()

        #expect(played == a)
    }

    /// A folder browsed into plays as that folder; the root plays as a loose selection.
    @MainActor
    @Test func test_playlistSource_followsTheDepth() async {
        let root = makeModel(directory: nil)
        let nested = makeModel(directory: URL(fileURLWithPath: "/Docs/Podcasts"))

        #expect(root.playlistSource == nil)
        #expect(nested.playlistSource == .folder(URL(fileURLWithPath: "/Docs/Podcasts")))
    }

    /// In selection mode a tap selects instead of playing — the branch that used to live in the
    /// deleted row reducers.
    @MainActor
    @Test func test_inSelectionMode_tappingSelectsRatherThanPlays() async {
        let a = Self.file("/Docs/A.mp3")
        let model = makeModel()
        model.seed(items: [.file(a)])
        model.toggleSelectionMode()

        var played = false
        model.onPlay = { _, _, _ in played = true }

        model.fileTapped(a)

        #expect(!played)
        #expect(model.isSelected(.file(a)))
    }

    // MARK: -

    @MainActor
    private func makeModel(directory: URL? = nil) -> CollectionsViewModel {
        var client = FileManagerClient.test
        client.listItems = { _ in [] }
        client.deleteItem = { _ in }
        return CollectionsViewModel(currentDirectory: directory, fileManager: client)
    }

    private static func file(_ path: String) -> AudioFile {
        let url = URL(fileURLWithPath: path)
        return AudioFile(url: url, title: url.deletingPathExtension().lastPathComponent,
            duration: 100, fileSize: 1, format: .mp3,
            creationDate: Date(timeIntervalSince1970: 0))
    }

    private static func folder(_ path: String) -> CollectionItem {
        let url = URL(fileURLWithPath: path)
        return CollectionItem(id: url, url: url, name: url.lastPathComponent,
            creationDate: Date(timeIntervalSince1970: 0))
    }
}
