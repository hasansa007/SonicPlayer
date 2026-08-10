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
    /// 1a — library home.
    case library
    /// 1b, or 1g when there are none.
    case recordings
    /// Preferences, as rows you turn to and press.
    case settings
    /// A folder inside the library — which is also what a playlist is.
    ///
    /// **The stack is the path.** There is no stored folder URL and no parent pointer: the items
    /// visible at any depth are found by starting at the root list and descending once per
    /// `.folder` level below it. Popping is therefore all that going up requires, and a folder
    /// cannot be reached by a route that did not walk to it.
    case folder(itemID: String)
    /// 1c.
    case nowPlaying
    /// 1d.
    case recording
    /// 1e.
    case edit(itemID: String)
    /// The guard in front of `Delete`.
    ///
    /// **A screen rather than a system alert.** Every other decision in this app is made by turning
    /// to a row and pressing it, and the one place that handed over to UIKit chrome mid-flow was the
    /// only irreversible one — so the gesture you had just been using stopped working exactly where
    /// care mattered most.
    case confirmDelete(itemID: String)

    /// Choosing a folder to move a recording into.
    ///
    /// **A pushed screen rather than a modal picker**, because filing something is navigation and
    /// the dial navigates. The sheet it replaces was reached by a nudge and then operated by a
    /// finger, which put a second input model in the middle of a dial flow.
    ///
    /// **Flattened, not nested.** Descending to file something means walking a tree you are not
    /// browsing — every level a chance to lose the thing you were moving. One list of paths is one
    /// turn and one press however deep the destination is.
    case move(itemID: String)

    /// The header segment, uppercased. `nil` contributes nothing — the mode chooser is a fork
    /// rather than a place, and `DialScreen.Chrome` says an empty breadcrumb is valid.
    ///
    func crumb(in content: DialContent) -> String? {
        switch self {
        // **`HOME` and `LIBRARY`, not `LIBRARY` and `RECORDINGS`.** The card that opens the second
        // screen has always been labelled *Library*, while the screen itself said *Recordings* and
        // listed every audio file the app can see — podcasts and imports included. Two names for
        // one place, and the one on the header was the wrong one.
        //
        // Renaming only the second would have read `LIBRARY ▸ LIBRARY`, so the root took the name
        // it actually has: it is a menu you start from, not a library.
        case .library: "HOME"
        case .settings: "SETTINGS"
        case .recordings: "LIBRARY"
        // The folder's own name, so the header reads HOME ▸ LIBRARY ▸ LECTURES rather than
        // repeating LIBRARY at every depth.
        case .folder(let itemID): content.item(itemID)?.title.uppercased() ?? "FOLDER"
        case .nowPlaying: "NOW PLAYING"
        case .recording: "RECORDING"
        case .edit: "EDIT"
        case .confirmDelete: "DELETE"
        case .move: "MOVE"
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

    /// The rows of the delete guard, in order. `Cancel` is first so the highlight rests on it —
    /// the safe answer should be the one a press gives you when you arrived by accident.
    enum DeleteChoice: String, CaseIterable {
        case cancel
        case delete

        var label: String {
            switch self {
            case .cancel: "Cancel"
            case .delete: "Delete"
            }
        }

        var icon: DialScreen.Icon {
            switch self {
            case .cancel: .none
            case .delete: .delete
            }
        }
    }

    /// Whether the rows are large cards rather than compact list rows.
    ///
    /// **The top two menus, and nothing else.** These are the screens you *choose from* — two or
    /// three destinations, each worth a title, a second line and a real icon. Everything below is a
    /// list you *scan*, where the same treatment would fit four recordings on a screen that holds
    /// twelve.
    ///
    /// It reads off the route for the same reason `countsRows` does: the alternative is inferring
    /// it from the row count in the view, and the library home legitimately has two rows or three
    /// depending on whether anything is loaded (`DialScreen.List.isProminent` has the full story).
    /// **Nothing is prominent any more.**
    ///
    /// Home's two entries were 1:1 cards, which made the fork the biggest thing in the app and left
    /// a card whose height did not match any other screen's. As rows they sit in the same container
    /// as everything else, and the card is the same height wherever you are — which is what makes
    /// the dial below it stop moving between screens.
    var showsProminentRows: Bool { false }
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

/// What can be done to a recording.
///
/// **These are the stick's four nudges now, not a menu.** They were rows on a pushed screen —
/// reached by a nudge, scrolled to, pressed — which is three gestures to do one thing, and a whole
/// route to hold five verbs. Four of them fit the four directions the stick already has, so the
/// screen went and `Rename` went with it: renaming stays possible in Files and in the browser, and
/// four directions cannot hold five things.
enum DialItemAction: String, Equatable, CaseIterable {
    /// The one case the host never sees — `DialNavigator` turns it into a push of `.edit`, because
    /// the editor is a *place* and the rest of these are things done to a file.
    case edit
    case share
    case addToPlaylist
    case delete

    var label: String {
        switch self {
        case .edit: "Edit"
        case .share: "Share"
        case .addToPlaylist: "Add to playlist"
        case .delete: "Delete"
        }
    }

    /// One glyph each, and on the stick they are the *only* label — a nudge has no room for a word,
    /// so a symbol that reads wrong is a control that lies.
    var icon: DialScreen.Icon {
        switch self {
        case .edit: .trim
        case .share: .share
        case .addToPlaylist: .playlist
        case .delete: .delete
        }
    }
}
