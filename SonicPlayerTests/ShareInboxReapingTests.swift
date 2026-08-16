import Foundation
import Testing

@testable import SonicPlayer

/// Reclaiming batches the extension never finished writing (#112).
///
/// **Nothing else in the system would.** `isCommittedBatch` refuses dot-prefixed names by design, so
/// a batch abandoned when the extension was killed is invisible to the drain and keeps its audio
/// until the app is deleted. Share a 400 MB audiobook, get jetsammed twice, and 800 MB is gone.
@Suite("Abandoned partial batches")
struct ShareInboxReapingTests {

    // MARK: - The rule, without a clock

    @Test func aFreshPartialIsInFlightAndMustBeLeftAlone() {
        let name = ShareInbox.partialBatchName(id: "abc")
        #expect(!ShareInbox.isAbandonedPartial(name, age: 0))
        #expect(!ShareInbox.isAbandonedPartial(name, age: 60))
        #expect(
            !ShareInbox.isAbandonedPartial(name, age: ShareInbox.partialBatchLifetime),
            "exactly at the threshold is still in flight — the boundary favours the user's files"
        )
    }

    @Test func anOldPartialIsAbandoned() {
        let name = ShareInbox.partialBatchName(id: "abc")
        #expect(ShareInbox.isAbandonedPartial(name, age: ShareInbox.partialBatchLifetime + 1))
    }

    /// A committed batch is never reaped by age — it is drained, however long it has waited.
    @Test func aCommittedBatchIsNeverAbandoned() {
        #expect(!ShareInbox.isAbandonedPartial("batch-1", age: 999_999))
        #expect(!ShareInbox.isAbandonedPartial(".DS_Store", age: 999_999))
    }

    // MARK: - The reaping itself

    private func makeTree() throws -> (container: URL, documents: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Reaping-\(UUID().uuidString)")
        let container = root.appendingPathComponent("group")
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return (container, documents)
    }

    /// **Ages the entries as well as the directory, and that distinction is the whole point.**
    /// The reaper takes the newest timestamp anywhere in the batch, because a directory's own mtime
    /// advances only when an entry is *added* — so a batch receiving one large file looks untouched
    /// for as long as that copy takes. An earlier version of this helper aged only the directory and
    /// these tests passed against a reaper that would have deleted live batches.
    ///
    /// Entries are aged before the directory, since writing into a directory updates its mtime.
    private func writePartial(
        _ name: String, in container: URL, files: [String], agedBy age: TimeInterval
    ) throws -> URL {
        let batch = ShareInbox.inbox(inContainer: container).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        let aged = Date().addingTimeInterval(-age)
        for file in files {
            let url = batch.appendingPathComponent(file)
            try Data("audio".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: aged], ofItemAtPath: url.path)
        }
        try FileManager.default.setAttributes([.modificationDate: aged], ofItemAtPath: batch.path)
        return batch
    }

    /// The case the directory-only signal was blind to: entries written recently inside a batch
    /// whose own timestamp is old. That is a copy in progress, and reaping it destroys a live share.
    @Test func aBatchWithAnOldDirectoryButFreshContentsIsInFlight() throws {
        let (container, documents) = try makeTree()
        let name = ShareInbox.partialBatchName(id: "copying")
        let batch = ShareInbox.inbox(inContainer: container).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-ShareInbox.partialBatchLifetime - 60)],
            ofItemAtPath: batch.path
        )
        // Written now — the extension is mid-copy.
        try Data("audio".utf8).write(to: batch.appendingPathComponent("Arriving.m4a"))

        let result = InboxDrain.run(container: container, into: documents)

        #expect(FileManager.default.fileExists(atPath: batch.path), "a live copy must survive")
        #expect(result.isEmpty)
    }

    @Test func aStalePartialIsRemovedAndItsLossReported() throws {
        let (container, documents) = try makeTree()
        let name = ShareInbox.partialBatchName(id: "dead")
        let batch = try writePartial(
            name, in: container, files: ["Lost Lecture.m4a"],
            agedBy: ShareInbox.partialBatchLifetime + 60
        )

        let result = InboxDrain.run(container: container, into: documents)

        #expect(!FileManager.default.fileExists(atPath: batch.path), "the leak is reclaimed")
        #expect(
            result.pending == [.abandoned(fileName: "Lost Lecture.m4a")],
            "the user shared it and got nothing — saying so is the only honest option left"
        )
    }

    /// **The risk that runs the other way.** The app cannot ask whether the extension is still
    /// alive, so a partial being written right now must survive. Getting this wrong destroys a
    /// share in flight, which is why the threshold is an hour rather than a minute.
    @Test func aPartialBeingWrittenRightNowSurvives() throws {
        let (container, documents) = try makeTree()
        let name = ShareInbox.partialBatchName(id: "live")
        let batch = try writePartial(name, in: container, files: ["In Flight.m4a"], agedBy: 5)

        let result = InboxDrain.run(container: container, into: documents)

        #expect(FileManager.default.fileExists(atPath: batch.path))
        #expect(result.isEmpty)
    }

    @Test func reapingDoesNotDisturbACommittedBatchInTheSamePass() throws {
        let (container, documents) = try makeTree()
        _ = try writePartial(
            ShareInbox.partialBatchName(id: "dead"), in: container, files: ["Lost.m4a"],
            agedBy: ShareInbox.partialBatchLifetime + 60
        )
        let committed = ShareInbox.inbox(inContainer: container).appendingPathComponent("batch-1")
        try FileManager.default.createDirectory(at: committed, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: committed.appendingPathComponent("Good.m4a"))

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.imported.count == 1)
        #expect(result.pending == [.abandoned(fileName: "Lost.m4a")])
        #expect(
            ((try? FileManager.default.contentsOfDirectory(
                atPath: ShareInbox.inbox(inContainer: container).path)) ?? []).isEmpty,
            "both are gone: one drained, one reclaimed"
        )
    }
}

/// What the extension could not take at all, carried in the manifest (#112).
///
/// The activation rule fires when *any* attachment is audio, so a mixed share hands the extension
/// everything. Anything it drops is invisible to both processes unless it is written down: the
/// extension has no UI to report it and `completeRequest` tells the host the share succeeded.
@Suite("Attachments the extension refused")
struct RejectedAttachmentTests {

    @Test func rejectedNamesSurviveTheManifestRoundTrip() throws {
        let manifest = InboxManifest(destination: nil, rejected: ["slides.pdf", "photo.heic"])
        let decoded = InboxManifestCodec.decode(try InboxManifestCodec.encode(manifest))
        #expect(decoded.rejected == ["slides.pdf", "photo.heic"])
    }

    @Test func aManifestWithoutRejectionsDecodesToNil() {
        #expect(InboxManifestCodec.decode(Data(#"{"destination":null}"#.utf8)).rejected == nil)
    }

    /// An attachment with no `suggestedName` is recorded as an empty marker, not as an invented
    /// English placeholder — naming the unnamed belongs to the screen that renders it.
    @Test func anUnnamedRejectionArrivesAsNilRatherThanAPlaceholder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rejected-\(UUID().uuidString)")
        let container = root.appendingPathComponent("group")
        let documents = root.appendingPathComponent("Documents")
        let batch = ShareInbox.inbox(inContainer: container).appendingPathComponent("batch-1")
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try InboxManifestCodec.encode(InboxManifest(destination: nil, rejected: [""]))
            .write(to: batch.appendingPathComponent(ShareInbox.manifestFileName))

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.pending == [.notAccepted(fileName: nil)])
    }

    @Test func theDrainReportsThemAsNotAccepted() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rejected-\(UUID().uuidString)")
        let container = root.appendingPathComponent("group")
        let documents = root.appendingPathComponent("Documents")
        let batch = ShareInbox.inbox(inContainer: container).appendingPathComponent("batch-1")
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: batch.appendingPathComponent("Good.m4a"))
        try InboxManifestCodec.encode(InboxManifest(destination: nil, rejected: ["slides.pdf"]))
            .write(to: batch.appendingPathComponent(ShareInbox.manifestFileName))

        let result = InboxDrain.run(container: container, into: documents)

        #expect(result.imported.count == 1)
        #expect(result.pending == [.notAccepted(fileName: "slides.pdf")])
    }
}
