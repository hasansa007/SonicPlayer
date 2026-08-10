import Foundation
import Synchronization  // Mutex — the client closures are @Sendable
import Testing

@testable import SonicPlayer

/// Importing a folder that is already there (#6).
///
/// **The library filled with numbered copies of one shelf.** `importFolder` resolved a *unique*
/// name, so importing `Recordings` beside an existing `Recordings` produced `Recordings 2` — every
/// time, for ever, and the recording you had just made was in whichever of them the app last wrote
/// to. Seen on the phone with three of them stacked up.
/// **A class around the `Mutex`, not a bare one.** `Mutex` is non-copyable, so it cannot be
/// captured by the `@Sendable` closure a client is made of; a reference holding it can be. The lock
/// is still doing the real work — `importFile` runs off the main actor.
private final class Landings: @unchecked Sendable {
    private let storage = Mutex<[URL]>([])
    func record(_ url: URL) { storage.withLock { $0.append(url) } }
    var all: [URL] { storage.withLock { $0 } }
}

@Suite(.serialized)
struct FolderImportMergeTests {

    /// A real directory, because this is the one piece of the import that is genuinely `FileManager`
    /// — `createDirectory` is what decides merge or throw, and stubbing it would test the stub.
    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderImportMergeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A source folder holding one audio file.
    private func makeSource(named name: String, in root: URL) throws -> URL {
        let source = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: source.appendingPathComponent("Lecture 1.m4a"))
        return source
    }

    /// Records where each file was asked to land, which is the whole question here.
    private func client(documents: URL, landings: Landings) -> FileManagerClient {
        var fileManager = FileManagerClient.test
        fileManager.documentsDirectory = { documents }
        fileManager.importFile = { _, destination in
            landings.record(destination ?? documents)
        }
        return fileManager
    }

    @Test func importingAFolderThatAlreadyExistsMergesIntoIt() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let library = root.appendingPathComponent("Library", isDirectory: true)
        let existing = library.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        let source = try makeSource(named: "Recordings", in: root)
        let landings = Landings()

        await FolderImport.run(
            urls: [source], into: library, fileManager: client(documents: library, landings: landings)
        )

        #expect(landings.all == [existing], "into the folder that is already there")
        #expect(
            !FileManager.default.fileExists(atPath: library.appendingPathComponent("Recordings 2").path),
            "and no numbered copy beside it"
        )
    }

    /// **Twice is still once**, which is what makes merging safe rather than merely tidier: the
    /// file-level dedupe one layer down refuses a name-and-size match, so a repeated import of an
    /// unchanged folder adds nothing at all.
    @Test func importingTheSameFolderTwiceCreatesOneFolder() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let library = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let source = try makeSource(named: "Lectures", in: root)
        let landings = Landings()
        let fileManager = client(documents: library, landings: landings)

        await FolderImport.run(urls: [source], into: library, fileManager: fileManager)
        await FolderImport.run(urls: [source], into: library, fileManager: fileManager)

        let folders = try FileManager.default
            .contentsOfDirectory(at: library, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
        #expect(folders == ["Lectures"])
        #expect(landings.all.count == 2, "both imports ran; they just ran into one place")
    }

    /// A folder whose name is genuinely new is still created — merging is not "always reuse".
    @Test func aFolderWithANewNameIsStillCreated() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let library = root.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let source = try makeSource(named: "Podcasts", in: root)
        let landings = Landings()

        await FolderImport.run(
            urls: [source], into: library, fileManager: client(documents: library, landings: landings)
        )

        let created = library.appendingPathComponent("Podcasts", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: created.path))
        #expect(landings.all == [created])
    }
}
