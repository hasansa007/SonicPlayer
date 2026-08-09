import Foundation

/// One level of the dial's navigation stack (#6).
///
/// **The breadcrumb is derived from a stack of these, never stored on a screen.** `DialScreen` has a
/// `breadcrumb` field and it would have been easy to fill it in per screen; then `LIBRARY ▸
/// RECORDINGS` is written down in one place and `LIBRARY` in another, and the day a level is
/// inserted between them both are wrong. Here there is one array and the header is `map`.
///
/// The empty state (1g) is deliberately **not** a case. "No recordings" is a fact about the data,
/// not a place you navigated to — making it a route would mean something had to decide to push it,
/// and that decision would be wrong for exactly as long as it took to record something.
enum DialRoute: Equatable {
    /// 1h — listen or record, the fork before anything else.
    case chooseMode
    /// 1a — library home.
    case library
    /// 1b, or 1g when there are none.
    case recordings
    /// 1c.
    case nowPlaying
    /// 1d.
    case recording
    /// 1e.
    case edit(itemID: String)
    /// 1f.
    case actions(itemID: String)

    /// The header segment, uppercased. `nil` contributes nothing — the mode chooser is a fork
    /// rather than a place, and `DialScreen.Chrome` says an empty breadcrumb is valid.
    ///
    /// `.actions` is named after the item rather than "ACTIONS" because the list it heads contains
    /// `Delete`, and the one thing worth knowing before pressing that is *what*.
    func crumb(in content: DialContent) -> String? {
        switch self {
        case .chooseMode: nil
        case .library: "LIBRARY"
        case .recordings: "RECORDINGS"
        case .nowPlaying: "NOW PLAYING"
        case .recording: "RECORDING"
        case .edit: "EDIT"
        case .actions(let id): (content.item(id)?.title).map { $0.uppercased() } ?? "ACTIONS"
        }
    }

    /// The modes this screen offers, in chip order. Empty for a screen where the wheel only ever
    /// does one thing.
    ///
    /// **Adding a mode is adding an element here**, not a new screen type — which is the whole
    /// reason the selected mode is an index into data rather than a case in an enum of screens.
    var modes: [DialMode] {
        switch self {
        // **Now Playing has no modes.** Volume moved to its own small wheel and Browse to a
        // spring-return tri-state, which leaves the big wheel doing exactly one thing — seek. A
        // one-entry mode row is noise, and "what does the wheel do right now" stops being a
        // question the user has to hold.
        case .nowPlaying:
            []
        case .edit:
            [
                DialMode(id: "trimStart", label: "Start handle", axis: .trimStart),
                DialMode(id: "trimEnd", label: "End handle", axis: .trimEnd)
            ]
        default:
            []
        }
    }

    /// What a tick does when there are no modes to choose between.
    var defaultAxis: DialAxis {
        switch self {
        case .recording: .gain
        case .nowPlaying: .seek
        default: .highlight
        }
    }

    /// Whether `1 of 12` is worth drawing. It is a property of the screen rather than of the row
    /// count: the library has five rows and does not want it, the actions list has five and does —
    /// a menu is a place, a list is a position within one.
    var countsRows: Bool {
        switch self {
        case .recordings, .actions: true
        default: false
        }
    }
}

/// What a tick of the wheel changes.
///
/// A screen picks one, either fixed or through the selected `DialMode`. It is an enum rather than a
/// closure so the choice stays `Equatable`, printable in a failure message, and exhaustive — the
/// compiler is what guarantees a new axis is handled everywhere it can appear.
enum DialAxis: Equatable {
    case highlight
    case seek
    case volume
    /// Steps through the queue on Now Playing. See `DialNavigator` for why this moves the track
    /// immediately rather than a cursor.
    case queue
    case gain
    case trimStart
    case trimEnd
}

/// One selectable answer to "what is the wheel doing right now".
///
/// Rendered as a chip with `.selected` emphasis; chosen by `.action(id)` like any other chip, so
/// the wheel needs no vocabulary for mode switching and neither does the view.
struct DialMode: Equatable, Identifiable {
    var id: String
    var label: String
    var axis: DialAxis
}

/// The five rows of 1f.
///
/// `CaseIterable` in this order *is* the screen's row order, so there is one list rather than an
/// enum and a parallel array that can disagree about where `Delete` sits.
enum DialItemAction: String, Equatable, CaseIterable {
    case share
    case addToPlaylist
    case export
    case rename
    case delete

    var label: String {
        switch self {
        case .share: "Share file…"
        case .addToPlaylist: "Add to playlist"
        case .export: "Export as MP3"
        case .rename: "Rename"
        case .delete: "Delete"
        }
    }

    /// `.export` is its own role rather than a second use of `.share`, which would put one glyph on
    /// two rows of a five-row list and read as a bug. Handing a file to another app and writing a
    /// copy out are different promises.
    var icon: DialScreen.Icon {
        switch self {
        case .share: .share
        case .addToPlaylist: .playlist
        case .export: .export
        case .rename: .rename
        case .delete: .delete
        }
    }
}
