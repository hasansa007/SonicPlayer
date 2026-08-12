import Foundation
import Testing

@testable import SonicPlayer

/// What the user is told when something fails (#65).
///
/// **The reported bug was an alert containing two ~200-character container paths.** Every client
/// threw an `NSError` whose message was an interpolated English sentence, and every path from a
/// client to the screen ends in an assignment to `operationError` or `openError` — so the sentence
/// *was* the alert.
///
/// These assert the property rather than the wording: a message may change, but it may never carry
/// a filesystem path.
@Suite
struct ClientErrorTests {

    private static let root = URL(fileURLWithPath: "/Users/someone/Library/Developer/CoreSimulator/Devices/ABC/data/Containers/Data/Application/DEF/Documents")
    private static let outside = URL(fileURLWithPath: "/Users/someone/Library/Developer/CoreSimulator/Devices/ABC/data/Containers/Data/Application/DEF")

    /// Every error a client can throw, so a new case cannot skip the check by being forgotten here.
    private static let all: [any LoggableError] = [
        FileError.outsideLibrary(attempted: outside, root: root),
        FileError.unreadableSource(root.appendingPathComponent("Lecture.m4a")),
        FileError.importFailed(name: "Lecture.m4a", underlying: FileError.corruptImport(name: "x")),
        FileError.corruptImport(name: "Lecture.m4a"),
        PlaybackError.cannotLoad(root.appendingPathComponent("Lecture.m4a")),
        RecordingError.cannotStart
    ]

    @Test func noUserFacingMessageContainsAPath() {
        for error in Self.all {
            let shown = error.localizedDescription
            #expect(!shown.contains("/"), "\(type(of: error)) shows a path: \(shown)")
            #expect(!shown.contains("Containers"), "\(type(of: error)) shows a container: \(shown)")
            #expect(!shown.contains("Documents"), "\(type(of: error)) names the container directory")
        }
    }

    @Test func everyErrorSaysSomething() {
        for error in Self.all {
            #expect(!error.localizedDescription.isEmpty)
            #expect(error.errorDescription != nil, "\(type(of: error)) falls back to a type name")
        }
    }

    /// **The detail is kept, not discarded.** Hiding the paths from the user is only half of it; a
    /// refusal nobody can diagnose is the other failure.
    @Test func theDetailSurvivesForTheLog() {
        let error = FileError.outsideLibrary(attempted: Self.outside, root: Self.root)

        #expect(error.logDescription.contains(Self.outside.path))
        #expect(error.logDescription.contains(Self.root.path))
        #expect(!error.localizedDescription.contains(Self.outside.path))
    }

    /// The reported alert, as a regression: this exact string must never come back.
    @Test func theReportedAlertCannotRecur() {
        let error = FileError.outsideLibrary(attempted: Self.outside, root: Self.root)

        #expect(!error.localizedDescription.hasPrefix("Access Denied:"))
        #expect(error.localizedDescription.count < 120, "an alert is a sentence, not a stack trace")
    }
}
