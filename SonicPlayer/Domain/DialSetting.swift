import Foundation

/// One row of the Settings screen, and what pressing it does (#6).
///
/// **Settings was the last screen that was not the dial.** It was a `navigationDestination` with a
/// real navigation bar over a `Form` — reached by a wheel, left by a chevron, and operated by
/// tapping controls the wheel could not touch. Every other decision in this app is made by turning
/// to a row and pressing it, including the irreversible one; this was the last place that handed
/// over to UIKit chrome mid-flow.
///
/// **Every setting here cycles.** A press advances to the next value and wraps, which is the only
/// interaction a one-button control can offer without inventing a second screen per preference —
/// and the values are few enough that cycling is faster than picking. The two that are not values
/// at all (About, Help) push what they always pushed.
enum DialSetting: String, CaseIterable, Sendable {
    case playbackSpeed
    case skipDuration
    case appearance
    case language
    case about
    case help

    var title: String {
        switch self {
        case .playbackSpeed: "Playback speed"
        case .skipDuration: "Skip by"
        case .appearance: "Appearance"
        case .language: "Language"
        case .about: "About"
        case .help: "How it works"
        }
    }

    /// A second line for the rows whose effect is not obvious from the value alone.
    var subtitle: String? {
        switch self {
        case .playbackSpeed: "Used when a track opens"
        case .skipDuration: "The wheel's coarse jump"
        case .appearance: nil
        case .language: "Opens iOS Settings"
        case .about, .help: nil
        }
    }

    var icon: DialScreen.Icon {
        switch self {
        case .playbackSpeed: .play
        case .skipDuration: .next
        case .appearance: .stats
        case .language: .library
        case .about: .session
        case .help: .marker
        }
    }

    /// Whether pressing this cycles a value in place rather than leaving the screen. Cycling rows
    /// stay put — the value is on the row you are looking at, so going anywhere would hide the
    /// thing that just changed.
    var cycles: Bool {
        switch self {
        case .playbackSpeed, .skipDuration, .appearance: true
        case .language, .about, .help: false
        }
    }
}

extension Array where Element: Equatable {

    /// The next element after `current`, wrapping — the whole of what a cycling settings row needs.
    ///
    /// Wraps rather than stopping for the same reason the library's wheel does: a list of three
    /// values has no meaningful "end", and a wall you can reach in two presses is a wall you hit
    /// constantly. An element that is not in the array yields the first, which is the safe answer
    /// when a stored preference no longer exists.
    func next(after current: Element) -> Element {
        guard let index = firstIndex(of: current) else { return self[0] }
        return self[(index + 1) % count]
    }
}
