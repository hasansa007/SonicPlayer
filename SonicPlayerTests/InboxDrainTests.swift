import Foundation
import Testing

@testable import SonicPlayer

@Suite("Draining the share queue")
struct InboxDrainTests {

    // MARK: - Scaffolding

    private func makeTree() throws -> (container: URL, documents: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InboxDrain-\(UUID().uuidString)")
        let container = root.appendingPathComponent("group")
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return (container, documents)
    }

    @discardableResult
    private func writeBatch(
        _ name: String, in container: URL, files: [String: String], destination: String? = nil,
        includeManifest: Bool = true
    ) throws -> URL {
        let batch = ShareInbox.inbox(inContainer: container).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        for (file, contents) in files {
            try Data(contents.utf8).write(to: batch.appendingPathComponent(file))
        }
        if includeManifest {
            let data = try InboxManifestCodec.encode(InboxManifest(destination: destination))
            try data.write(to: batch.appendingPathComponent(ShareInbox.manifestFileName))
        }
        return batch
    }

    private func names(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    // MARK: - The happy path

    @Test func aCommittedBatchLandsInTheLibraryAndLeavesTheQueueEmpty() throws {
        let (container, documents) = try makeTree()
        try writeBatch("batch-1", in: container, files: ["Lecture 04.m4a": "one"])

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.imported.count == 1)
        #expect(names(in: documents) == ["Lecture 04.m4a"])
        #expect(names(in: ShareInbox.inbox(inContainer: container)).isEmpty, "the batch is consumed")
    }

    /// **The property the whole atomic-rename design exists for.** A batch the extension is still
    /// writing must be invisible, because the user can share into a foregrounded app that is
    /// draining at that moment.
    @Test func aPartialBatchIsNotTouched() throws {
        let (container, documents) = try makeTree()
        let partial = ShareInbox.partialBatchName(id: "abc")
        try writeBatch(partial, in: container, files: ["Half Written.m4a": "x"])

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.isEmpty)
        #expect(names(in: documents).isEmpty)
        #expect(names(in: ShareInbox.inbox(inContainer: container)) == [partial], "left alone")
    }

    /// The drain runs on two scene phases and the app can die mid-batch, so running it twice must
    /// be indistinguishable from running it once.
    @Test func drainingTwiceImportsOnceAndLosesNothing() throws {
        let (container, documents) = try makeTree()
        try writeBatch("batch-1", in: container, files: ["A.m4a": "a", "B.m4a": "b"])

        let first = InboxDrain.run(container: container, into: documents)
        let second = InboxDrain.run(container: container, into: documents)

        #expect(first.imported.count == 2)
        #expect(second.isEmpty, "nothing left to do")
        #expect(names(in: documents) == ["A.m4a", "B.m4a"], "no duplicates")
    }

    /// Half a batch already moved is exactly what a kill mid-drain leaves behind.
    @Test func aHalfDrainedBatchIsFinishedByTheNextRun() throws {
        let (container, documents) = try makeTree()
        try writeBatch("batch-1", in: container, files: ["A.m4a": "a", "B.m4a": "b"])
        // Simulate the first run having moved A and then the app being killed.
        let batch = ShareInbox.inbox(inContainer: container).appendingPathComponent("batch-1")
        try FileManager.default.moveItem(
            at: batch.appendingPathComponent("A.m4a"),
            to: documents.appendingPathComponent("A.m4a")
        )

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.imported.count == 1, "only the survivor")
        #expect(names(in: documents) == ["A.m4a", "B.m4a"])
        #expect(names(in: ShareInbox.inbox(inContainer: container)).isEmpty)
    }

    // MARK: - What must never be silently destroyed

    @Test func aNonAudioFileIsSkippedAndLeftInTheQueue() throws {
        let (container, documents) = try makeTree()
        try writeBatch("batch-1", in: container, files: ["notes.pdf": "pdf", "A.m4a": "a"])

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.imported.count == 1)
        #expect(result.pending == [.notAudio(fileName: "notes.pdf")])
        #expect(names(in: documents) == ["A.m4a"])
        #expect(
            names(in: ShareInbox.inbox(inContainer: container)) == ["batch-1"],
            "a file we do not understand is not a file we destroy"
        )
    }

    @Test func aBatchWithNoManifestStillImportsToTheRoot() throws {
        let (container, documents) = try makeTree()
        try writeBatch("batch-1", in: container, files: ["A.m4a": "a"], includeManifest: false)

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.imported.count == 1)
        #expect(names(in: documents) == ["A.m4a"])
    }

    @Test func aCorruptManifestStillImportsToTheRoot() throws {
        let (container, documents) = try makeTree()
        let batch = try writeBatch("batch-1", in: container, files: ["A.m4a": "a"])
        try Data("{{{".utf8).write(to: batch.appendingPathComponent(ShareInbox.manifestFileName))

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.imported.count == 1)
        #expect(names(in: documents) == ["A.m4a"])
    }

    /// Slice 2 always writes a nil destination, but the drain already honours one — which is what
    /// makes slice 3 a manifest change rather than a code change.
    @Test func aDestinationIsHonouredAndCreated() throws {
        let (container, documents) = try makeTree()
        try writeBatch("batch-1", in: container, files: ["A.m4a": "a"], destination: "Lectures")

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.imported.count == 1)
        #expect(names(in: documents) == ["Lectures"])
        #expect(names(in: documents.appendingPathComponent("Lectures")) == ["A.m4a"])
    }

    @Test func twoBatchesBothLand() throws {
        let (container, documents) = try makeTree()
        try writeBatch("batch-1", in: container, files: ["A.m4a": "a"])
        try writeBatch("batch-2", in: container, files: ["B.m4a": "b"])

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.imported.count == 2)
        #expect(names(in: documents) == ["A.m4a", "B.m4a"])
    }

    /// The normal state on almost every scene change, and it must not be an error.
    @Test func noInboxAtAllIsSilent() throws {
        let (container, documents) = try makeTree()
        #expect(InboxDrain.run(container: container, into: documents).isEmpty)
    }

    /// A file whose name is taken lands beside the existing one rather than overwriting it —
    /// `OpenInImport`'s rule, reached through the drain (#41).
    @Test func aNameCollisionWithDifferentBytesLandsBeside() throws {
        let (container, documents) = try makeTree()
        try Data("original".utf8).write(to: documents.appendingPathComponent("A.m4a"))
        try writeBatch("batch-1", in: container, files: ["A.m4a": "different"])

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.imported.count == 1)
        #expect(names(in: documents) == ["A 2.m4a", "A.m4a"], "neither file is destroyed")
    }

    /// Identical bytes are already imported, so the queued copy is consumed rather than duplicated.
    @Test func anIdenticalFileIsConsumedNotDuplicated() throws {
        let (container, documents) = try makeTree()
        try Data("same".utf8).write(to: documents.appendingPathComponent("A.m4a"))
        try writeBatch("batch-1", in: container, files: ["A.m4a": "same"])

        InboxDrain.run(container: container, into: documents)

        #expect(names(in: documents) == ["A.m4a"], "no 'A 2.m4a'")
        #expect(names(in: ShareInbox.inbox(inContainer: container)).isEmpty)
    }
}
