import Foundation

/// Which of the app's two jobs you are doing (#6).
///
/// **Not `DialMode`** — that name was already taken by the *wheel's* mode, the axis a turn drives
/// on a screen that offers more than one (trim start versus trim end). Two unrelated senses of
/// "mode" in one namespace is how a type ends up meaning whichever one the reader assumed.
///
/// **The same library, two sets of verbs.** Listening and editing are different activities over
/// identical material: a recording you made is also a recording you play, and a folder holds both
/// kinds. So the mode does not change *what* is listed — it changes what a press does to the thing
/// under the highlight, and which nudges exist.
///
/// **The reason it is a mode and not a screen** is the trim editor. Rewriting a file the player has
/// loaded leaves the player holding a stale duration, a stale position and a session that will
/// restore both — the file changed underneath it and nothing said so. Entering `.record` releases
/// the player, which is what makes that impossible rather than merely discouraged. A guard would
/// have forbidden the path; this removes it.
///
/// Note what the split costs, because it is not free and was chosen anyway: **destruction lives in
/// `.record` only.** An imported podcast can be added to a playlist and played, and can never be
/// deleted or trimmed from the dial — only from the Files sheet. That is the price of Listen being
/// a mode where nothing can be lost.
enum DialActivity: Equatable, Sendable {
    /// Play from the library. Import, make folders, add to playlists. Nothing here destroys.
    case listen
    /// Capture, and change what you captured — trim, delete, rename.
    case record

    /// What the hub does to a file in this mode.
    var opensEditor: Bool { self == .record }

    /// The fork's rows, in the order they are drawn. Listening leads because it is the commoner
    /// arrival and the one that cannot lose anything.
    static let all: [DialActivity] = [.listen, .record]

    static func at(_ row: Int) -> DialActivity? {
        all.indices.contains(row) ? all[row] : nil
    }

    // MARK: - How the fork presents itself

    var id: String {
        switch self {
        case .listen: "listen"
        case .record: "record"
        }
    }

    var title: String {
        switch self {
        case .listen: "Listen"
        case .record: "Record"
        }
    }

    /// Says what the mode lets you do, because there is no other indicator of which one you are in.
    var subtitle: String {
        switch self {
        case .listen: "Play, import, make playlists"
        case .record: "Capture, trim, rename, delete"
        }
    }

    var icon: DialScreen.Icon {
        switch self {
        case .listen: .playlist
        case .record: .recording
        }
    }
}
