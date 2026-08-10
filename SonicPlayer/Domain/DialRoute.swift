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
    /// The guard in front of `Delete`.
    ///
    /// **A screen rather than a system alert.** Every other decision in this app is made by turning
    /// to a row and pressing it, and the one place that handed over to UIKit chrome mid-flow was the
    /// only irreversible one — so the gesture you had just been using stopped working exactly where
    /// care mattered most.
    case confirmDelete(itemID: String)

    /// The header segment, uppercased. `nil` contributes nothing — the mode chooser is a fork
    /// rather than a place, and `DialScreen.Chrome` says an empty breadcrumb is valid.
    ///
    /// `.actions` is named after the item rather than "ACTIONS" because the list it heads contains
    /// `Delete`, and the one thing worth knowing before pressing that is *what*.
    func crumb(in content: DialContent) -> String? {
        switch self {
        case .chooseMode: nil
        // **`HOME` and `LIBRARY`, not `LIBRARY` and `RECORDINGS`.** The card that opens the second
        // screen has always been labelled *Library*, while the screen itself said *Recordings* and
        // listed every audio file the app can see — podcasts and imports included. Two names for
        // one place, and the one on the header was the wrong one.
        //
        // Renaming only the second would have read `LIBRARY ▸ LIBRARY`, so the root took the name
        // it actually has: it is a menu you start from, not a library.
        case .library: "HOME"
        case .recordings: "LIBRARY"
        case .nowPlaying: "NOW PLAYING"
        case .recording: "RECORDING"
        case .edit: "EDIT"
        case .actions(let id): (content.item(id)?.title).map { $0.uppercased() } ?? "ACTIONS"
        case .confirmDelete: "DELETE"
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
    /// count: a menu is a place, a list is a position within one.
    ///
    /// **The recordings list dropped it.** The ring's lit tick already shows where you are in the
    /// list, so the line was a second answer to a question already on screen — and it took a row's
    /// worth of height at the bottom of the card to give it.
    var countsRows: Bool {
        switch self {
        case .actions: true
        default: false
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
    var showsProminentRows: Bool {
        switch self {
        case .chooseMode, .library: true
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

/// The rows of 1f.
///
/// `CaseIterable` in this order *is* the screen's row order, so there is one list rather than an
/// enum and a parallel array that can disagree about where `Delete` sits.
enum DialItemAction: String, Equatable, CaseIterable {
    /// Rename first, Edit second — the two that change the recording itself, ahead of the three
    /// that move it somewhere. The highlight rests on row 0, so the cheapest thing to reach is the
    /// one most often wanted.
    case rename
    /// **Second, having come off the stick's right nudge.** It is also the one case here the host
    /// never sees — `DialNavigator` turns it into a push of `.edit`, because the editor is a
    /// *place* and the rest of these are things done to a file.
    case edit
    case share
    case addToPlaylist
    /// **`export` is gone.** Sharing already hands the file to another app, and the row below it
    /// offering a second, format-converting way to do nearly the same thing was a choice nobody
    /// wanted to have to make.
    case delete

    var label: String {
        switch self {
        case .rename: "Rename"
        case .edit: "Edit"
        case .share: "Share file…"
        case .addToPlaylist: "Add to playlist"
        case .delete: "Delete"
        }
    }

    /// One glyph per row, still — which used to be worth saying because `.export` and `.share`
    /// were two rows making nearly the same promise. Removing `export` settled that argument by
    /// deleting one side of it.
    var icon: DialScreen.Icon {
        switch self {
        case .rename: .rename
        case .edit: .edit
        case .share: .share
        case .addToPlaylist: .playlist
        case .delete: .delete
        }
    }
}
