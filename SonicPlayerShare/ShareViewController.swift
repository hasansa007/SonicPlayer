import SwiftUI
import UIKit

/// The share extension's entry point — **slice 1 of #112: it appears, and does nothing else.**
///
/// This target exists before it does any work on purpose. Everything else in the epic is ordinary
/// app code that can be written, tested and reverted freely; a new target changes what CI archives,
/// signs and uploads, and that is the one cost here that cannot be undone. A rejected upload burns
/// a build number permanently — `3.0.0 (23)` is the standing proof, refused for ITMS-90111 after
/// archiving and signing cleanly. So the target ships empty and gets proven by a dry run first.
///
/// # DO NOT PROMOTE THIS TO `main` UNTIL SLICE 2 LANDS
///
/// This is a real, registered `com.apple.share-services` extension: the activation rule is live and
/// Sonic Player is offered in the share sheet for any audio file. On `feat` that reaches nobody. **A
/// merge to `main` uploads to TestFlight**, and from that moment a tester who shares a voice memo is
/// offered Sonic Player, taps it, and is told the feature does not work — in English, in all nine
/// locales. An earlier version of this comment claimed no user ever reaches this screen; that was
/// true only of the branch, not of the release, and it is the kind of claim that stops being true
/// without anyone editing it.
///
/// The string below is therefore deliberately **not** localised. Localising it would make a dead end
/// look like a finished feature, and the nine translations should be spent on the picker's real copy
/// in slice 5, against final wording, rather than on a placeholder that must be deleted.
///
/// # Why a `UIViewController` in a SwiftUI-only codebase
///
/// `NSExtensionPrincipalClass` is a UIKit contract — the system instantiates this class and there is
/// no SwiftUI equivalent to hand it. So this class is a **shell around a SwiftUI body**, which is
/// what keeps the exception to one file rather than one target, and is the same shape slice 3's
/// folder picker will use. It carries no layout of its own: an earlier version hand-rolled a
/// `UIStackView` with inline `16`/`24` constants, which broke both the SwiftUI-only rule and the
/// no-magic-numbers rule in a target the lint script could not even see.
///
/// What this deliberately does NOT do, and why it matters that it never starts:
///
/// - **It does not read the library.** From slice 3 the extension is handed a list of folder names
///   through the shared group container, and nothing more. It cannot see `Documents/`, so it cannot
///   damage it — which is what makes it safe for a process the system kills without notice.
/// - **It does not decide anything.** No naming, no de-duplication, no filtering. Those live in
///   `Domain/`, where they are testable without a host app.
/// - **It never loads a file into memory.** Copies go through `loadFileRepresentation` and
///   `FileManager`. Reading an hour-long lecture into `Data` inside an extension is a kill, not an
///   error.
final class ShareViewController: UIViewController {

    /// **Hosts SwiftUI as a child rather than subclassing `UIHostingController`, and that is not a
    /// style choice.** With `NSExtensionPrincipalClass` and no storyboard, the host instantiates
    /// this class through plain `init()`. `UIHostingController` declares its own designated
    /// initializers, which suppresses inheritance of `UIViewController.init()` — so the subclass
    /// version compiles, links, and can fail at the one moment that matters. A plain
    /// `UIViewController` keeps `init()` and loses nothing.
    override func viewDidLoad() {
        super.viewDidLoad()

        let hosting = UIHostingController(
            rootView: ShareStubView(onClose: { [weak self] in self?.close() })
        )
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    /// Cancel rather than complete, because nothing was accepted.
    ///
    /// `completeRequest` tells the host app the share succeeded, and a host that believes a file was
    /// taken may offer to delete its own copy. Reporting success for work not done is the failure
    /// #33 was about, in a place where the cost is somebody else's file.
    ///
    /// **Not optional-chained.** `extensionContext?.cancelRequest(...)` reads as tidy and turns the
    /// only control on a one-button screen into a silent no-op when the context is gone — no exit,
    /// no log, nothing to debug. If there is no context to answer, dismissing is the honest
    /// fallback, and the assertion fires in development where it can still be fixed.
    private func close() {
        guard let extensionContext else {
            assertionFailure("Share extension has no extensionContext; nothing to cancel.")
            dismiss(animated: true)
            return
        }
        extensionContext.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }
}

/// Deliberately literal-free: default `VStack` spacing and `.padding()` mean there are no numbers to
/// tokenise, which is the right answer for a placeholder in a target that cannot see
/// `DesignSystem/Tokens.swift` — the tokens live in the app target's synchronized group, and adding
/// cross-target membership to justify a stub would be the tail wagging the dog.
struct ShareStubView: View {
    var onClose: () -> Void = {}

    var body: some View {
        VStack {
            Text("Sonic Player import is not wired up yet.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Close", action: onClose)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
