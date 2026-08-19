import SwiftUI
import UIKit

/// `UIButton(type: .close)` as a SwiftUI view.
///
/// **Why not a plain SwiftUI button:** the close glyph with Apple's own localised accessibility
/// label is a UIKit affordance. `Button(role: .close)` is the SwiftUI equivalent and is iOS 26+,
/// while this app targets 18.0 — so wrapping the UIKit control is the only way to get the system's
/// glyph and its nine translations without writing a string of our own.
private struct SystemCloseButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .close)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}

/// One row of the destination picker, as the extension knows it.
///
/// Restated from `ShareFolder` because the targets cannot see each other's sources — the same
/// duplication as `ShareInboxLayout`, policed the same way by `ShareInboxLayoutAgreementTests`. The
/// extension only ever *reads* this shape; the app owns producing it.
struct SharePickerFolder: Decodable, Equatable, Identifiable {
    var path: String
    var relativePath: String

    var id: String { relativePath }
}

/// Where the shared audio should go — the extension's only question (#112 slice 3).
///
/// **SwiftUI, hosted in a `UIHostingController`.** `NSExtensionPrincipalClass` forces the shell to
/// be a `UIViewController`, and slice 2 drew its spinner and close button in UIKit because two
/// system controls did not justify hosting SwiftUI. A list does. This closes one of the two
/// deviations ADR 0004 records against CLAUDE.md's SwiftUI-only rule; `nonClashing` is the other and
/// is still open.
///
/// **Flat, not browsable, and that is inherited rather than decided here.** `MoveDestinations`
/// settled it for the app's own Move screen: *"filing something means walking a tree you are not
/// reading, and every level you descend is a chance to lose track of what you were moving."* A
/// share sheet is a worse place to browse than the app — smaller, modal over someone else's app,
/// and the user is mid-task.
///
/// **This screen is also the confirmation, which is half of why it exists.** Slice 2 shipped a
/// silent extension, and the first person to use it shared a file, saw nothing, and had to open the
/// app to learn whether it had worked — the deferred-work problem ADR 0004 rejected the silent
/// options over, reintroduced by accident. Choosing a folder *is* the acknowledgement, so the fix
/// costs no extra screen.
///
/// **No title, no labels, no words at all — and that is a constraint, not a preference.** A title
/// here would be a user-facing string, and ADR 0004's localisation exception ended when slice 2
/// deleted the stub. This target has no string catalogue until slice 5, so anything written here
/// ships as English in all nine locales. The list is folder names the user chose themselves, under
/// a sheet the system already labels with the app; slice 5 is where it gains a title along with the
/// nine translations.
struct SharePickerView: View {
    let folders: [SharePickerFolder]
    let onChoose: (SharePickerFolder) -> Void
    let onCancel: () -> Void

    var body: some View {
        // **The close button lives HERE, inside the SwiftUI hierarchy, and that is the fix for a
        // bug three attempts failed to place.**
        //
        // It began as a `UIButton` in the UIKit shell, constrained against the shell's view, with
        // the hosted list constrained below it. On device the button rendered *halfway down the
        // sheet* and pushed the list off the bottom. Three configurations were tried —
        // `safeAreaLayoutGuide`, `layoutMarginsGuide`, and `safeAreaLayoutGuide` with an inset —
        // and swapping between them changed nothing, which is what finally ruled out the guide as
        // the cause. The problem was never which guide: it was two layout systems driving one
        // screen, with UIKit constraints resolving against a hierarchy SwiftUI was also sizing.
        //
        // A `safeAreaInset` keeps it in one system. SwiftUI places the bar, insets the list below
        // it so no row hides underneath, and honours the sheet's real safe area — none of which the
        // shell could see. `.padding()` with no argument is the system's own metric, so there is no
        // number here for the magic-number lint to catch or for anyone to tune by guesswork.
        List(folders) { folder in
            Button {
                onChoose(folder)
            } label: {
                Text(folder.path)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                SystemCloseButton(action: onCancel)
            }
            .padding()
            // **`.bar`, because an inset reserves space but does not occlude.** Without a
            // background the HStack is fully transparent, so rows scrolled *underneath* it and
            // folder names rendered through the close glyph. At rest it looked correct, which is
            // why the first version shipped: the defect only appears once the list is longer than
            // the sheet.
            .background(.bar)
        }
    }
}
