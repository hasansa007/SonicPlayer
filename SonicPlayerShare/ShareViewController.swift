import OSLog
import UIKit
import UniformTypeIdentifiers

/// The share extension's entry point — **slice 2 of #112: it copies, and decides nothing.**
///
/// Audio shared from any app is copied into the queue inside the shared App Group container, and
/// the app files it into the library the next time it runs.
///
/// **It shows a spinner and a close button, and ships no strings.** An earlier version of this slice
/// drew nothing at all, reasoning that a screen needs strings and localisation is slice 5. The
/// reasoning was right and the conclusion was not: a share of thirty lectures that iCloud must
/// download first left a blank sheet for tens of seconds with no progress and no way out. The answer
/// is a `UIActivityIndicatorView` and `UIButton(type: .close)` — a system glyph with a
/// system-localised accessibility label — which gives the user an exit without a word of ours in any
/// of the nine languages. Anything worth *saying* is still the app's job, once it has actually filed
/// the files. Slice 3's picker brings the first strings, and slice 5 translates them.
///
/// **`UIViewController`, in a SwiftUI-only codebase.** `NSExtensionPrincipalClass` is a UIKit
/// contract — the system instantiates this class through plain `init()`, and `UIHostingController`
/// declares its own designated initializers, which suppresses that. What little chrome there is here
/// is two system controls, so hosting SwiftUI to draw them would be the tail wagging the dog.
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

    /// Set when the user taps Close. Checked between attachments so a long copy can be abandoned.
    private var isCancelled = false
    /// The batch being written, so cancelling can take it back out.
    private var partialBatch: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // **A spinner and a system close button, and neither ships a string.**
        //
        // The first version of slice 2 drew nothing at all, on the grounds that a screen needs
        // strings and localisation is slice 5. That reasoning was right about strings and wrong
        // about the consequence: sharing thirty lectures that iCloud must download first left a
        // blank sheet for tens of seconds with no progress, no cancel, and no way out short of
        // force-quitting the host app. The slice-1 stub at least had a Close button.
        //
        // `UIButton(type: .close)` is the way to have both: a system glyph with a system-localised
        // accessibility label, no text of ours in any of the nine languages. The spinner says work
        // is happening without claiming what.
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        let close = UIButton(type: .close)
        close.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        Task { [weak self] in
            await self?.consumeAttachments()
        }
    }

    /// Abandons the share, taking the half-written batch with it.
    ///
    /// The batch is still dot-prefixed at this point, so the app would never have seen it — but
    /// leaving it would rely on the reaper an hour later. Removing it here is immediate and exact.
    @objc private func cancel() {
        isCancelled = true

        // **Deliberately does NOT delete the partial batch, and an earlier version did.**
        // `copy()`'s continuation body runs on `loadFileRepresentation`'s own queue, so a Close tap
        // mid-copy tore the directory down underneath a live `copyItem`. The batch is dot-prefixed
        // and therefore invisible to the app either way; leaving it costs nothing but disk until
        // `InboxDrain.reapAbandonedPartials` collects it, and that reaper exists precisely because
        // this process can vanish without cleaning up after itself.

        // **Not optional-chained, and I deleted this guard once already.** Round 2 replaced
        // `extensionContext?.cancelRequest(...)` with exactly this, on the grounds that optional
        // chaining turns the only control on the screen into a silent no-op when the context is
        // gone — no exit, no log, nothing to debug. Round 3's rewrite reintroduced the optional
        // chain and removed the argument with it.
        guard let extensionContext else {
            log.error("Close tapped with no extensionContext; the request cannot be cancelled.")
            assertionFailure("Share extension has no extensionContext to cancel.")
            return
        }
        extensionContext.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
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
            // **`cancel()` has already answered the context, so this must not answer it again.**
            // Tapping Close calls `cancelRequest`, and the in-flight `stage()` then throws
            // `userCancelled` and lands here — a second complete-or-cancel on the same
            // `NSExtensionContext`, which Apple permits exactly one of. The user-cancelled path is
            // the only one that arrives already answered, so it is the only one to skip.
            guard !isCancelled else { return }

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

        partialBatch = partial

        var staged = 0
        var rejected: [String] = []
        for provider in providers {
            if isCancelled { throw CocoaError(.userCancelled) }

            // **Recorded, not just skipped.** `completeRequest` below tells the host the share
            // succeeded, and a host that believes a file was taken may offer to delete its copy.
            // The extension has no way to tell the user itself, so the names travel in the manifest
            // and the app surfaces them.
            //
            // **An empty string when there is no name, never a placeholder.** This read
            // `?? "a shared file"` — an English literal, written into the manifest, destined for
            // slice 4's screen, in a target that had just declared it ships no strings. Naming an
            // unnamed file is the app's job, where `Localizable.xcstrings` is.
            guard let identifier = audioTypeIdentifier(of: provider) else {
                rejected.append(provider.suggestedName ?? "")
                continue
            }
            do {
                if try await copy(
                    provider, as: identifier, preferredName: provider.suggestedName, into: partial
                ) {
                    staged += 1
                } else {
                    rejected.append(provider.suggestedName ?? "")
                }
            } catch {
                log.error("Skipping one attachment: \(error.localizedDescription, privacy: .public)")
                rejected.append(provider.suggestedName ?? "")
            }
        }

        if isCancelled { throw CocoaError(.userCancelled) }

        // The manifest is written before the commit so a committed batch always has one. Slice 2
        // has no picker, so the destination is always the library root.
        let manifest = try JSONEncoder().encode(
            ShareManifest(destination: nil, rejected: rejected.isEmpty ? nil : rejected)
        )
        try manifest.write(to: partial.appendingPathComponent(ShareInboxLayout.manifestFileName))

        // **The rename IS the commit.** Until this line the batch is dot-prefixed and the app's
        // drain refuses to look at it; after it, the batch is wholly visible. A rename within one
        // filesystem is atomic, so there is no half-committed state — which is what lets the user
        // share into the app while it is foregrounded and draining.
        try FileManager.default.moveItem(at: partial, to: inbox.appendingPathComponent(id))
        partialBatch = nil
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

    /// - Parameter preferredName: what the user calls this file, from `NSItemProvider.suggestedName`.
    ///
    /// **The name decides two things, and an earlier version took it from the wrong place.** It
    /// filtered and named from `loadFileRepresentation`'s *temp* URL — a filename the system chose.
    /// Both halves were wrong. Filtering on it meant an attachment whose UTI already conformed to
    /// `public.audio` could still be refused, because the materialised file happened to carry an
    /// extension outside our list (an Opus voice note arriving as `.oga`, a data-backed provider
    /// given a UUID-ish name) — and the refusal was silent, since `completeRequest` still told the
    /// host the share succeeded. Naming from it meant a system temp name could end up in the user's
    /// library, while the *rejected* list beside it used `suggestedName`: two notions of the file's
    /// name in one loop.
    private func copy(
        _ provider: NSItemProvider, as identifier: String, preferredName: String?, into directory: URL
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
                guard let url else {
                    continuation.resume(returning: false)
                    return
                }

                // The user's name wins; the temp URL is the fallback and supplies the extension
                // when `suggestedName` carries none.
                let name = Self.filename(preferring: preferredName, fallingBackTo: url)

                // `audioTypeIdentifier` has already established this attachment conforms to
                // `public.audio` or `public.mpeg-4`. This is the app's accept-list applied early so
                // the queue does not fill with things the drain will only refuse — a narrowing, and
                // deliberately checked against the name the LIBRARY will see.
                guard ShareInboxLayout.isAudio(URL(fileURLWithPath: name)) else {
                    continuation.resume(returning: false)
                    return
                }
                do {
                    let destination = Self.nonClashing(name: name, in: directory)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// The name to file an attachment under: the user's, with the temp URL's extension when the
    /// user's carries none.
    private static func filename(preferring suggested: String?, fallingBackTo url: URL) -> String {
        guard let suggested, !suggested.isEmpty else { return url.lastPathComponent }
        guard (suggested as NSString).pathExtension.isEmpty else { return suggested }
        let ext = url.pathExtension
        return ext.isEmpty ? suggested : "\(suggested).\(ext)"
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

    /// **Deliberately carries no `errorDescription`.** It conformed to `LocalizedError` with an
    /// English sentence, which the host app surfaces — a user-facing string outside
    /// `Localizable.xcstrings`, in a build that ships. ADR 0004's localisation exception ended when
    /// the stub marker was deleted, so the honest options were to translate it into nine languages
    /// for a case that should never happen, or to ship no string at all and let the host show its
    /// own generic failure. This is the second.
    private enum ShareError: Error {
        case noAppGroupContainer
    }
}

/// The extension's copy of the manifest shape — see `ShareInboxLayout` for why it is duplicated.
/// Encoding only; the app owns decoding and its policy for a corrupt one.
private struct ShareManifest: Encodable {
    var destination: String?
    var rejected: [String]?
}
