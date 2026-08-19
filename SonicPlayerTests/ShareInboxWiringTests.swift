import Foundation
import SwiftUI  // ScenePhase
import Testing

@testable import SonicPlayer

/// The share queue's wiring into the app's scene phases (#112 slice 2, ADR 0004).
///
/// The drain itself is covered by `InboxDrainTests`; what is asserted here is *when* it runs — the
/// part that differs deliberately from ADR 0003's rule for iOS's staging directory, and so the part
/// most likely to be "corrected" back by someone who has read only that ADR.
@Suite(.serialized)
struct ShareInboxWiringTests {

    private func makeQueue(withFile name: String = "Shared.m4a") throws -> (container: URL, documents: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareWiring-\(UUID().uuidString)")
        let container = root.appendingPathComponent("group")
        let documents = root.appendingPathComponent("Documents")
        let batch = ShareInbox.inbox(inContainer: container).appendingPathComponent("batch-1")
        try FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: batch.appendingPathComponent(name))
        try InboxManifestCodec.encode(InboxManifest())
            .write(to: batch.appendingPathComponent(ShareInbox.manifestFileName))
        return (container, documents)
    }

    private func names(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    @MainActor
    private func makeApp(documents: URL, container: URL?) -> AppViewModel {
        var audioPlayer = AudioPlayerClient.test
        audioPlayer.stop = {}
        audioPlayer.setRate = { _ in }

        var fileManager = FileManagerClient.test
        fileManager.documentsDirectory = { documents }
        fileManager.shareInboxContainer = { container }

        let app = AppViewModel(
            player: PlayerViewModel(
                audioPlayer: audioPlayer,
                fileManager: .test,
                artworkClient: .test,
                sessionStore: .inMemory()
            ),
            recording: RecordingViewModel(audioRecorder: .test, audioPlayer: audioPlayer, fileManager: .test),
            settings: SettingsViewModel(),
            filesRoot: CollectionsViewModel(currentDirectory: nil, fileManager: .test),
            onboarding: nil,
            fileManager: fileManager
        )
        return app
    }

    /// **The behaviour ADR 0004 chose and ADR 0003 forbids for the other queue.** Draining only on
    /// `.background` would mean a shared file does not appear until you have opened the app *and
    /// then left it* — missing at exactly the moment you went looking for it.
    @MainActor
    @Test func becomingActiveDrainsTheShareQueue() throws {
        let (container, documents) = try makeQueue()
        let app = makeApp(documents: documents, container: container)

        app.scenePhaseChanged(.active)

        #expect(names(in: documents) == ["Shared.m4a"])
        #expect(names(in: ShareInbox.inbox(inContainer: container)).isEmpty)
    }

    @MainActor
    @Test func backgroundingAlsoDrainsTheShareQueue() throws {
        let (container, documents) = try makeQueue()
        let app = makeApp(documents: documents, container: container)

        app.scenePhaseChanged(.background)

        #expect(names(in: documents) == ["Shared.m4a"])
    }

    /// Inherited from ADR 0003 and it still applies: `openFromFiles` runs detached and can be
    /// moving a file when the phase changes. The share drain does not touch that file, but it does
    /// write into the same `Documents/`, and an import that is mid-flight is not a moment to add
    /// concurrent writes to.
    @MainActor
    @Test func anInFlightImportOutranksTheShareDrain() throws {
        let (container, documents) = try makeQueue()
        let app = makeApp(documents: documents, container: container)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareWiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        app.player.openFromFiles(scratch.appendingPathComponent("Never Resolves.mp3"))
        app.scenePhaseChanged(.active)

        #expect(names(in: documents).isEmpty, "the queue waits for the next phase change")
        #expect(names(in: ShareInbox.inbox(inContainer: container)) == ["batch-1"])
    }

    /// The normal case on nearly every phase change, and it must cost nothing and say nothing.
    @MainActor
    @Test func anEmptyQueueRecordsNoFailures() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareWiring-\(UUID().uuidString)")
        let container = root.appendingPathComponent("group")
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let app = makeApp(documents: documents, container: container)

        app.scenePhaseChanged(.active)

        #expect(app.shareImportPending.isEmpty)
    }

    /// A build without the App Group entitlement has no queue at all, and must behave exactly as
    /// the app did before #112 rather than failing.
    @MainActor
    @Test func noContainerIsNotAnError() throws {
        let documents = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareWiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let app = makeApp(documents: documents, container: nil)

        app.scenePhaseChanged(.active)

        #expect(app.shareImportPending.isEmpty)
    }

    // MARK: - Publishing the folder list (slice 3)

    /// Nothing covered the writer at all: not that `folders.json` is produced, not that iOS's
    /// staging directory is kept out of it. Deleting the `isStagingDirectory` guard would offer the
    /// user a destination the app empties on `.background` (#41, ADR 0003) with the suite green.
    @MainActor
    @Test func becomingActivePublishesTheFolderList() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Publish-\(UUID().uuidString)")
        let container = root.appendingPathComponent("group")
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        for folder in ["Lectures", "Lectures/Week 1", "Inbox"] {
            try FileManager.default.createDirectory(
                at: documents.appendingPathComponent(folder), withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let app = makeApp(documents: documents, container: container)
        // The list now comes from the in-memory tree, so the tree is what the test supplies.
        app.home.libraryTree = [
            DialContent.Item(
                id: documents.appendingPathComponent("Lectures").absoluteString,
                title: "Lectures", duration: 0,
                children: [
                    DialContent.Item(
                        id: documents.appendingPathComponent("Lectures/Week 1").absoluteString,
                        title: "Week 1", duration: 0, children: []
                    )
                ]
            )
        ]

        app.scenePhaseChanged(.active)

        let data = try Data(
            contentsOf: container.appendingPathComponent(ShareFolderList.fileName)
        )
        let published = try JSONDecoder().decode([ShareFolder].self, from: data)

        #expect(published.map(\.relativePath) == ["", "Lectures", "Lectures/Week 1"])
    }

    /// The list changes maybe once a week and this runs on every scene phase, so an unchanged tree
    /// must not keep rewriting the shared container.
    ///
    /// **Asserts the writer's own answer, not the file's timestamp.** The first version compared
    /// modification dates, which cannot tell "skipped the write" from "never wrote at all" — and
    /// when it failed, `attributesOfItem` was throwing on a missing file, reported identically to a
    /// failed expectation. Two hypotheses, one signal, and I spent three runs on the wrong one.
    @Test func anUnchangedTreeIsNotRepublished() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Publish-\(UUID().uuidString)")
        let container = root.appendingPathComponent("group")
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: root) }

        #expect(
            ShareFolderListWriter.publish(
                documentsDirectory: documents, container: container, items: []
            ) == .wrote
        )
        #expect(
            ShareFolderListWriter.publish(
                documentsDirectory: documents, container: container, items: []
            ) == .unchanged,
            "an identical list must not be rewritten — and .unchanged is distinguishable from .failed"
        )
    }

    /// A new folder must reach the picker on the next scene phase.
    @Test func aChangedTreeIsRepublished() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Publish-\(UUID().uuidString)")
        let container = root.appendingPathComponent("group")
        let documents = root.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: root) }
        let lectures = documents.appendingPathComponent("Lectures")

        ShareFolderListWriter.publish(documentsDirectory: documents, container: container, items: [])

        #expect(
            ShareFolderListWriter.publish(
                documentsDirectory: documents, container: container,
                items: [DialContent.Item(id: lectures.absoluteString, title: "Lectures", duration: 0, children: [])]
            ) == .wrote
        )
    }
}
