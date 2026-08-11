import SwiftUI
import UniformTypeIdentifiers

/// The system document picker, as a SwiftUI view.
///
/// **Lifted out of `CollectionsView` when that screen was deleted**, which is the only reason it
/// was ever in there — it is not part of any browser, it is the door to the one iOS owns. The dial
/// raises it for Import; nothing else does.
///
/// `asCopy: false` and `contentTypes: [.item, .folder]` on purpose: the caller takes
/// security-scoped access itself and copies what it wants, and a *folder* has to be selectable for
/// `FolderImport` to have anything to walk.
struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = [.item, .folder]
    var asCopy: Bool = false
    var allowsMultipleSelection: Bool = true
    var directoryURL: URL? = nil
    let onPick: ([URL]) -> Void
    var onCancel: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: asCopy)
        picker.allowsMultipleSelection = allowsMultipleSelection
        if let directoryURL { picker.directoryURL = directoryURL }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: (() -> Void)?

        init(onPick: @escaping ([URL]) -> Void, onCancel: (() -> Void)?) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel?()
        }
    }
}
