import Foundation
import Synchronization  // Mutex — the client closures are @Sendable
import Testing

@testable import SonicPlayer

/// Where an import puts things (#6).
///
/// **This suite exists because the behaviour it pins had none.** Importing loose files into the
/// root used to call `createCollectionForImport()`, which resolves a unique name from
/// "New Collection" and creates it — so a library imported into five times held `New Collection`
/// through `New Collection 5`, each holding whatever was selected that minute.
///
/// No test could see it: `FileManagerClient.test` returns the documents directory for that closure,
/// so the created folder and the destination were the same URL under test and different on a
/// phone. The only way to notice was to import twice and look at Files.
@Suite
struct FolderImportTests {

    /// A class, not a struct: `Mutex` is non-copyable, so it cannot be a stored property of one.
    private final class Recorder: Sendable {
        let imports = Mutex<[(source: URL, destination: URL?)]>([])
        let collectionsCreated = Mutex(0)

        func client() -> FileManagerClient {
            var client = FileManagerClient.test
            client.importFile = { [self] source, destination in
                imports.withLock { $0.append((source, destination)) }
            }
            client.createCollectionForImport = { [self] in
                collectionsCreated.withLock { $0 += 1 }
                return URL(fileURLWithPath: "/Docs/New Collection")
            }
            return client
        }
    }

    private func audio(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    @Test func looseFilesLandWhereTheyAreSentAndInventNoFolder() async {
        let recorder = Recorder()

        await FolderImport.run(
            urls: [audio("One.mp3"), audio("Two.m4a")],
            into: nil,
            fileManager: recorder.client()
        )

        #expect(recorder.collectionsCreated.withLock { $0 } == 0, "no folder may be minted per import")
        #expect(recorder.imports.withLock { $0 }.count == 2)
        #expect(
            recorder.imports.withLock { $0 }.allSatisfy { $0.destination == nil },
            "nil is the root — the caller decides where, not this type"
        )
    }

    /// The case that made the old behaviour visible: two imports, two folders.
    @Test func importingTwiceStillCreatesNothing() async {
        let recorder = Recorder()
        let client = recorder.client()

        await FolderImport.run(urls: [audio("One.mp3")], into: nil, fileManager: client)
        await FolderImport.run(urls: [audio("Two.mp3")], into: nil, fileManager: client)

        #expect(recorder.collectionsCreated.withLock { $0 } == 0)
    }

    @Test func anExplicitDestinationIsHonoured() async {
        let recorder = Recorder()
        let target = URL(fileURLWithPath: "/Docs/Lectures")

        await FolderImport.run(urls: [audio("One.mp3")], into: target, fileManager: recorder.client())

        #expect(recorder.imports.withLock { $0 }.first?.destination == target)
    }

    /// Unchanged, and worth keeping visible next to the change above: what is not audio never
    /// reaches the client at all.
    @Test func nonAudioIsSkippedRatherThanFailed() async {
        let recorder = Recorder()

        let result = await FolderImport.run(
            urls: [audio("Notes.txt"), audio("One.mp3")],
            into: nil,
            fileManager: recorder.client()
        )

        #expect(result == FolderImport.Result(succeeded: 1, failed: 0))
        #expect(recorder.imports.withLock { $0 }.count == 1)
    }
}
