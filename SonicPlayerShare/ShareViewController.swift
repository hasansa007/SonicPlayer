import OSLog
import UIKit
import UniformTypeIdentifiers

/// The share extension's entry point — **slice 2 of #112: it copies, and decides nothing.**
///
/// Audio shared from any app is copied into the queue inside the shared App Group container, and
/// the app files it into the library the next time it runs. There is no UI: the sheet dismisses and
/// the work happens without a screen.
///
/// **Silence is a design choice, not an omission.** A screen here would need strings, and strings
/// need nine languages; localisation is slice 5, so any copy shipped now would either be English in
/// every locale or would hold the whole feature back. There is nothing to say that the app cannot
/// say better once it has actually filed the files. Slice 3 adds the folder picker, and its strings
/// arrive with it.
///
/// **`UIViewController`, in a SwiftUI-only codebase.** `NSExtensionPrincipalClass` is a UIKit
/// contract — the system instantiates this class through plain `init()`, and `UIHostingController`
/// declares its own designated initializers, which suppresses that. With no UI to draw there is now
/// nothing else to justify.
///
/// What this deliberately does NOT do:
///
/// - **It does not read the library.** It cannot see `Documents/`, so it cannot damage it — which is
///   what makes it safe for a process the system kills without notice. It writes only inside its own
///   queue.
/// - **It does not decide anything.** No naming, no de-duplication, no destination. Those live in
///   `Domain/`, where they are testable without a host app. Slice 3's picker records a *choice*; the
///   app still does the filing.
/// - **It never loads a file into memory.** Copies go through `loadFileRepresentation` and
///   `FileManager`. Reading an hour-long lecture into `Data` inside an extension is a kill, not an
///   error.
final class ShareViewController: UIViewController {

    private let log = Logger(subsystem: "com.hasan.sonicplayer.share", category: "share")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        Task { [weak self] in
            await self?.consumeAttachments()
        }
    }

    private func consumeAttachments() async {
        guard let context = extensionContext else {
            log.error("No extensionContext; nothing to consume.")
            return
        }

        let providers = (context.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }

        do {
            let copied = try await stage(providers)
            log.info("Queued \(copied) file(s) for import.")
            // Success even at zero: the user's share was accepted and nothing was lost. Reporting
            // failure would invite the host app to treat its own copy as still-pending.
            context.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            // **Cancel, not complete.** `completeRequest` tells the host the share succeeded, and a
            // host that believes a file was taken may offer to delete its own copy. Reporting
            // success for work not done is #33's failure in a place where the cost is someone
            // else's file.
            log.error("Staging failed, cancelling: \(error.localizedDescription, privacy: .public)")
            context.cancelRequest(withError: error)
        }
    }

    /// Copies every audio attachment into one batch directory, then commits it with a rename.
    ///
    /// Returns the number of files staged. Throws only when the batch cannot be created or
    /// committed — an individual attachment that fails to load is logged and skipped, because one
    /// unreadable file should not discard the nine beside it.
    private func stage(_ providers: [NSItemProvider]) async throws -> Int {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShareInboxLayout.appGroupIdentifier
        ) else {
            throw ShareError.noAppGroupContainer
        }

        let inbox = container.appendingPathComponent(ShareInboxLayout.inboxDirectoryName)
        let id = UUID().uuidString
        let partial = inbox.appendingPathComponent(ShareInboxLayout.partialBatchName(id: id))
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)

        var staged = 0
        for provider in providers {
            guard let identifier = audioTypeIdentifier(of: provider) else { continue }
            do {
                if try await copy(provider, as: identifier, into: partial) { staged += 1 }
            } catch {
                log.error("Skipping one attachment: \(error.localizedDescription, privacy: .public)")
            }
        }

        // The manifest is written before the commit so a committed batch always has one. Slice 2
        // has no picker, so the destination is always the library root.
        let manifest = try JSONEncoder().encode(ShareManifest(destination: nil))
        try manifest.write(to: partial.appendingPathComponent(ShareInboxLayout.manifestFileName))

        // **The rename IS the commit.** Until this line the batch is dot-prefixed and the app's
        // drain refuses to look at it; after it, the batch is wholly visible. A rename within one
        // filesystem is atomic, so there is no half-committed state — which is what lets the user
        // share into the app while it is foregrounded and draining.
        try FileManager.default.moveItem(at: partial, to: inbox.appendingPathComponent(id))
        return staged
    }

    /// The attachment's audio type, or nil if it is not audio.
    ///
    /// Mirrors the activation rule: `public.audio`, plus `public.mpeg-4` because `.mp4` conforms to
    /// `public.movie` and the library accepts it for audiobooks. The rule fires when *any*
    /// attachment matches, so this is where a mixed share gets narrowed — copying the twenty photos
    /// beside the one lecture would be twenty pointless copies in a memory-capped process.
    private func audioTypeIdentifier(of provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .audio) || type.conforms(to: .mpeg4Movie)
        }
    }

    private func copy(
        _ provider: NSItemProvider, as identifier: String, into directory: URL
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            // `loadFileRepresentation` hands over a URL on disk and deletes it when the closure
            // returns, so the copy has to happen inside. Deliberately not `loadDataRepresentation`:
            // an hour-long lecture would be read into memory in a process that is killed for it.
            _ = provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url, ShareInboxLayout.isAudio(url) else {
                    continuation.resume(returning: false)
                    return
                }
                do {
                    let destination = Self.nonClashing(
                        name: url.lastPathComponent, in: directory
                    )
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Resolves a collision *within the batch*, which is the only collision this side can see.
    ///
    /// Two attachments can arrive with the same filename. This is not `UniqueNameResolver` and must
    /// not try to be: that one resolves against the library, which this process cannot read. Naming
    /// against the library stays the app's job at drain time.
    private static func nonClashing(name: String, in directory: URL) -> URL {
        let candidate = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 2...999 {
            let next = directory.appendingPathComponent("\(base) \(index).\(ext)")
            if !FileManager.default.fileExists(atPath: next.path) { return next }
        }
        return directory.appendingPathComponent("\(base) \(UUID().uuidString).\(ext)")
    }

    private enum ShareError: LocalizedError {
        case noAppGroupContainer

        var errorDescription: String? {
            switch self {
            case .noAppGroupContainer:
                "The Sonic Player app group is unavailable, so the files could not be queued."
            }
        }
    }
}

/// The extension's copy of the manifest shape — see `ShareInboxLayout` for why it is duplicated.
/// Encoding only; the app owns decoding and its policy for a corrupt one.
private struct ShareManifest: Encodable {
    var destination: String?
}
