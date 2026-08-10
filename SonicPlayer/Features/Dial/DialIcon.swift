import SwiftUI

/// The one place a `DialScreen.Icon` role becomes an SF Symbol.
///
/// The contract names roles rather than symbols so the navigator cannot pin a glyph that does not
/// exist — which makes this mapping the UI's half of that bargain, and the only file to edit when a
/// symbol changes. Reached from list rows and from the empty state, which is the second consumer
/// that keeps it out of either.
enum DialIcon {

    /// `nil` for `.none`, which means the row has no leading column at all rather than a blank one.
    static func systemImage(for icon: DialScreen.Icon) -> String? {
        switch icon {
        case .playlist: "square.grid.2x2.fill"
        case .recording: "mic.fill"
        case .session: "waveform"
        case .podcast: "dot.radiowaves.left.and.right"
        case .stats: "chart.bar.fill"
        case .marker: "bookmark.fill"
        case .importFile: "square.and.arrow.down"
        case .library: "square.stack.fill"
        case .volumeUp: "speaker.plus.fill"
        case .volumeDown: "speaker.minus.fill"
        case .previous: "backward.end.fill"
        case .next: "forward.end.fill"
        case .pause: "pause.fill"
        case .play: "play.fill"
        // **Scissors, not a slider.** `slider.horizontal.below.rectangle` is what an editor
        // *is*, and this nudge is one specific thing an editor does — keep the selection and cut
        // everything outside it. On a four-way stick beside a bin, the glyph has to say which cut.
        case .trim: "scissors"
        case .more: "ellipsis"
        case .share: "square.and.arrow.up"
        case .export: "arrow.down.doc"
        case .rename: "pencil"
        case .delete: "trash"
        case .add: "plus"
        case .repeatOff, .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        case .shuffle: "shuffle"
        // **A list, not a chevron.** A chevron says only "backwards", which on a stack of eight
        // screens is a direction and not a destination. Every level below the root pops to a list —
        // the library, or home — so the glyph can name where it goes instead of which way.
        case .back: "list.bullet"
        case .settings: "gearshape.fill"
        // **The same glyph in all three orders.** Three arrow variants would be three things to
        // learn for a control whose result is the list directly underneath it — the order is read
        // off the rows, not off the button. Which order is current is in the accessibility label,
        // and the fill says it is not the default.
        case .sort: "arrow.up.arrow.down"
        case .newFolder: "folder.badge.plus"
        case .move: "folder"
        case .none: nil
        }
    }

    /// Whether a row carrying this icon is destructive.
    ///
    /// `DialScreen.Action` has an `Emphasis` and a row does not, so the icon is the only signal the
    /// contract offers for "this one deletes something". Reading it here rather than at the call
    /// site keeps that inference in one place, where it is easy to replace if the contract grows a
    /// proper flag.
    static func isDestructive(_ icon: DialScreen.Icon) -> Bool {
        icon == .delete
    }
}
