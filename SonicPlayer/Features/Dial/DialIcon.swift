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
        case .edit: "slider.horizontal.below.rectangle"
        case .more: "ellipsis"
        case .share: "square.and.arrow.up"
        case .export: "arrow.down.doc"
        case .rename: "pencil"
        case .delete: "trash"
        case .add: "plus"
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
