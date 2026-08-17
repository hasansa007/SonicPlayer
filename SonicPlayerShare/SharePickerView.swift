import SwiftUI

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

    var body: some View {
        // Plain system list styling: legible at every Dynamic Type size without this target owning
        // a type scale. The app's `DesignSystem` tokens are not visible from here, and importing
        // them to style one list would be the tail wagging the dog.
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
    }
}
