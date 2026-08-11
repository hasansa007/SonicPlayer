import Foundation

/// Whether a file being imported is one the destination already holds (#6).
///
/// **Every import was guaranteed to duplicate.** `importFile` sent each one through
/// `UniqueNameResolver`, which exists to avoid collisions by appending ` 2`, ` 3`, … — so picking
/// the same file from Files twice produced `Lecture.m4a` and `Lecture 2.m4a`, and the resolver was
/// doing exactly its job. Nothing anywhere asked the prior question: is this already here?
///
/// **Name and size, not content.** Hashing would also catch a copy that had been renamed, and it
/// would read the whole file to do it — on hour-long recordings that is real time and battery on
/// every import, to answer a question that is only ever asked about the file you just picked. Name
/// plus exact byte count is free, since both are already in the directory listing. Two genuinely
/// different recordings sharing a name *and* a byte count is possible; it is not a thing that
/// happens to a person importing audio.
///
/// Deliberately no filesystem access, so the rule is testable without one — the caller supplies
/// what is already there.
enum ImportDedupe {

    /// One file already in the destination, reduced to the two things that decide this.
    struct Existing: Equatable, Sendable {
        var name: String
        var size: Int64

        init(name: String, size: Int64) {
            self.name = name
            self.size = size
        }
    }

    /// True when `name`/`size` is already present, and the copy should not be made.
    ///
    /// Compares the **full** filename, extension included: `Lecture.m4a` and `Lecture.mp3` are two
    /// encodings of the same recording, and which one you keep is a choice this has no business
    /// making silently.
    static func isAlreadyPresent(
        name: String, size: Int64, in existing: [Existing]
    ) -> Bool {
        existing.contains { $0.name == name && $0.size == size }
    }
}
