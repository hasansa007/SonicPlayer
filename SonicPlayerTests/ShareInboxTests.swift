import Foundation
import Testing

@testable import SonicPlayer

@Suite("The share queue's rules, without a filesystem")
struct ShareInboxTests {

    @Test func aBatchStillBeingWrittenIsInvisible() {
        let id = UUID().uuidString
        #expect(!ShareInbox.isCommittedBatch(ShareInbox.partialBatchName(id: id)))
        #expect(ShareInbox.isCommittedBatch(id))
    }

    /// The dot-prefix rule earns its keep on debris nobody shared. A drain that imported
    /// `.DS_Store` would produce a failure row for a file the user never chose.
    @Test func dotFilesAreNotBatches() {
        #expect(!ShareInbox.isCommittedBatch(".DS_Store"))
        #expect(!ShareInbox.isCommittedBatch(".partial-anything"))
        #expect(!ShareInbox.isCommittedBatch(""))
    }

    @Test func committedBatchesAreFilteredAndOrdered() {
        let names = ["c-batch", ".partial-b", "a-batch", ".DS_Store", "b-batch"]
        #expect(ShareInbox.committedBatches(in: names) == ["a-batch", "b-batch", "c-batch"])
    }

    @Test func theInboxSitsInsideTheGroupContainer() {
        let container = URL(fileURLWithPath: "/tmp/group")
        #expect(ShareInbox.inbox(inContainer: container).lastPathComponent == "Inbox")
    }
}

@Suite("What a batch records about itself")
struct InboxManifestTests {

    @Test func aDestinationSurvivesARoundTrip() throws {
        let manifest = InboxManifest(destination: "Lectures")
        let decoded = InboxManifestCodec.decode(try InboxManifestCodec.encode(manifest))
        #expect(decoded == manifest)
    }

    /// **The rule that keeps a batch from being lost to a preference.** Missing, truncated and
    /// corrupt all mean "library root" — never "skip these files". A batch landing at the root is
    /// recoverable in three taps; a batch silently skipped is not recoverable at all, because
    /// nothing tells the user it happened.
    @Test func anUnreadableManifestMeansTheRootRatherThanARefusal() {
        #expect(InboxManifestCodec.decode(nil).destination == nil)
        #expect(InboxManifestCodec.decode(Data()).destination == nil)
        #expect(InboxManifestCodec.decode(Data("not json".utf8)).destination == nil)
        #expect(InboxManifestCodec.decode(Data(#"{"destination":}"#.utf8)).destination == nil)
    }

    @Test func aDestinationResolvesUnderDocuments() {
        let documents = URL(fileURLWithPath: "/tmp/docs")
        let resolved = InboxManifestCodec.resolvedDestination(
            InboxManifest(destination: "Lectures"), under: documents
        )
        #expect(resolved.lastPathComponent == "Lectures")
    }

    /// **A manifest is written by another process, so its contents are input, not fact.** The
    /// extension is ours today, and that is not a reason to hand its output to
    /// `appendingPathComponent` unchecked.
    @Test func aDestinationCannotEscapeDocuments() {
        let documents = URL(fileURLWithPath: "/tmp/docs")
        for escape in ["../../etc", "../..", "Lectures/../../../tmp"] {
            let resolved = InboxManifestCodec.resolvedDestination(
                InboxManifest(destination: escape), under: documents
            )
            #expect(
                resolved == documents,
                "\(escape) must fall back to the root, not be honoured"
            )
        }
    }

    /// **A leading slash is not an escape, and assuming it was is what this test corrects.**
    /// `appendingPathComponent("/etc")` treats the whole string as one relative component, so it
    /// resolves to `Documents/etc` — an oddly named folder inside the library, not `/etc`. The
    /// first version of the test above listed it as an escape and failed, because the guard was
    /// right and the expectation was not. Kept as its own case so the distinction stays written
    /// down rather than being rediscovered by whoever next hardens this.
    @Test func aLeadingSlashIsASubfolderNotAnEscape() {
        let documents = URL(fileURLWithPath: "/tmp/docs")
        let resolved = InboxManifestCodec.resolvedDestination(
            InboxManifest(destination: "/etc"), under: documents
        )
        #expect(resolved.path.hasPrefix(documents.path))
        #expect(resolved.lastPathComponent == "etc")
    }

    @Test func anEmptyDestinationIsTheRoot() {
        let documents = URL(fileURLWithPath: "/tmp/docs")
        #expect(
            InboxManifestCodec.resolvedDestination(InboxManifest(destination: ""), under: documents)
                == documents
        )
    }
}
