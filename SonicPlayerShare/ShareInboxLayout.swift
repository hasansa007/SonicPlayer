import Foundation

/// The extension's half of the queue contract (#112).
///
/// **These literals are duplicated from `SonicPlayer/Domain/ShareInbox.swift` on purpose, and the
/// duplication is checked.** The two targets cannot see each other's sources — a synchronized file
/// group excludes files, it does not share them — so the choice was between hand-maintained
/// multi-target membership in `project.pbxproj` and two declarations with a test asserting they
/// agree. `ShareInboxLayoutAgreementTests` reads this file as text, plus both `.entitlements`, and
/// fails on any drift.
///
/// If you are here because that test failed: the fix is to make both sides match, not to relax the
/// test. A silent disagreement means the extension writes into a container the app never reads, and
/// every shared file vanishes with no error anywhere.
enum ShareInboxLayout {
    static let appGroupIdentifier = "group.com.hasan.sonicplayer"
    static let inboxDirectoryName = "Inbox"
    static let manifestFileName = "manifest.json"
    static let partialPrefix = "."

    static func partialBatchName(id: String) -> String {
        "\(partialPrefix)partial-\(id)"
    }

    /// The extensions the library accepts, mirrored from `ImportFilter.audioExtensions`.
    ///
    /// **The extension filters at copy time, and the activation rule is why.** That rule fires when
    /// *at least one* attachment is audio, so a share of twenty photos and one lecture activates
    /// Sonic Player and hands over all twenty-one. Copying them all and letting the app discard
    /// twenty would mean twenty pointless file copies inside a process the system kills for using
    /// too much memory.
    ///
    /// A second list is a drift risk and is accepted here for the same reason as the constants
    /// above: the alternative is sharing code across targets. It is checked by the same agreement
    /// test, against `ImportFilter.audioExtensions`.
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aac", "flac", "aiff", "m4b", "mp4", "opus", "ogg"
    ]

    static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    /// The folder list the app publishes for the picker (#112 slice 3).
    ///
    /// Restated from `ShareFolderList.fileName`; covered by the agreement suite like the rest.
    static let folderListFileName = "folders.json"
}
