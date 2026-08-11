import Foundation
import Testing

@testable import SonicPlayer

/// Re-importing a file the library already holds (#6).
///
/// Every import used to duplicate, because the only question asked was `UniqueNameResolver`'s —
/// *what shall I call this so it does not collide* — which is the opposite of noticing that it
/// already exists.
@Suite
struct ImportDedupeTests {

    private static let existing = [
        ImportDedupe.Existing(name: "Lecture.m4a", size: 4_096),
        ImportDedupe.Existing(name: "Seminar.m4a", size: 8_192),
    ]

    @Test func theSameFileTwiceIsAlreadyPresent() {
        #expect(ImportDedupe.isAlreadyPresent(name: "Lecture.m4a", size: 4_096, in: Self.existing))
    }

    @Test func aNewFileIsNot() {
        #expect(!ImportDedupe.isAlreadyPresent(name: "Talk.m4a", size: 1_024, in: Self.existing))
    }

    /// The case the whole rule turns on: same name, different bytes. Someone re-recorded or
    /// re-exported it, and it is a different file that deserves its own place.
    @Test func sameNameDifferentSizeIsNotTheSameFile() {
        #expect(!ImportDedupe.isAlreadyPresent(name: "Lecture.m4a", size: 9_999, in: Self.existing))
    }

    @Test func sameSizeDifferentNameIsNotTheSameFile() {
        #expect(!ImportDedupe.isAlreadyPresent(name: "Other.m4a", size: 4_096, in: Self.existing))
    }

    /// **The extension counts.** Two encodings of one recording are two files, and choosing which
    /// to keep is not a decision to make silently on someone's behalf.
    @Test func adifferentExtensionIsADifferentFile() {
        #expect(!ImportDedupe.isAlreadyPresent(name: "Lecture.mp3", size: 4_096, in: Self.existing))
    }

    @Test func anEmptyDestinationHoldsNothing() {
        #expect(!ImportDedupe.isAlreadyPresent(name: "Lecture.m4a", size: 4_096, in: []))
    }
}
