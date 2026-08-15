import UIKit

/// The share extension's entry point — **slice 1 of #112: it appears, and does nothing else.**
///
/// This target exists before it does any work on purpose. Everything else in the epic is ordinary
/// app code that can be written, tested and reverted freely; a new target changes what CI archives,
/// signs and uploads, and that is the one cost here that cannot be undone. A rejected upload burns
/// a build number permanently — `3.0.0 (23)` is the standing proof, refused for ITMS-90111 after
/// archiving and signing cleanly. So the target ships empty and gets proven by a dry run first.
///
/// **`UIViewController`, in a SwiftUI-only codebase.** `NSExtensionPrincipalClass` is a UIKit
/// contract; the system instantiates this class and there is no SwiftUI equivalent to hand it.
/// When slice 3 adds the folder picker, the picker itself is SwiftUI inside a `UIHostingController`
/// — this class stays a shell. That keeps the exception to one file rather than one target.
///
/// What this deliberately does NOT do, and why it matters that it never starts:
///
/// - **It does not read the library.** The extension is given a list of folder names by the app,
///   through the shared group container, and nothing more. It cannot see `Documents/` and so it
///   cannot damage it — which is what makes it safe for a process the system kills without notice.
/// - **It does not decide anything.** No naming, no de-duplication, no filtering. Those live in
///   `Domain/`, where they are testable without a host app.
/// - **It never loads a file into memory.** Copies go through `loadFileRepresentation` and
///   `FileManager`. Reading an hour-long lecture into `Data` inside an extension is a kill, not an
///   error.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // Deliberately not localised. Slice 1 is proven by a dry-run archive and by watching this
        // appear in the share sheet on a simulator — neither of which a user ever reaches. The
        // strings that ship are the picker's, and they arrive with it in slice 5 so the nine
        // languages are translated once against final copy rather than twice against a stub.
        let label = UILabel()
        label.text = "Sonic Player import is not wired up yet."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel

        let done = UIButton(type: .system)
        done.setTitle("Close", for: .normal)
        done.addTarget(self, action: #selector(close), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, done])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    /// Cancel rather than complete, because nothing was accepted.
    ///
    /// `completeRequest` tells the host app the share succeeded, and a host that believes a file
    /// was taken may offer to delete its own copy. Reporting success for work not done is the
    /// failure #33 was about, in a place where the cost is somebody else's file.
    @objc private func close() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}
