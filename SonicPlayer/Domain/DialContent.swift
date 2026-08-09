import Foundation

/// Everything the dial has to show, handed in from outside (#6).
///
/// **`Domain/` is pure Foundation, so the navigator cannot go and get any of this.** It is given a
/// `DialContent` and produces a `DialScreen` from it; the host reads the filesystem, the player and
/// the recorder, and calls `DialNavigator.update(_:)` when any of that changes. That split is what
/// makes every screen in the design reachable in a test with no simulator, no audio session and no
/// files on disk.
///
/// The navigator also writes to its own copy — a tick moves `playback.position` immediately and
/// emits the matching effect, so the ring redraws on the same frame as the turn rather than after a
/// round trip. The host's later `update(_:)` is the correction, and the source of truth.
struct DialContent: Equatable {

    /// A row on the library home (1a). `destination` is what pressing it opens — nil for a section
    /// that counts something but has nowhere to go yet, which is most of them in this slice.
    struct Section: Equatable, Identifiable {
        var id: String
        var icon: DialScreen.Icon
        var title: String
        var count: Int?
        var destination: DialRoute?
        /// What pressing it *does*, for a section that is an action rather than a place. Import is
        /// the first of these: it opens a picker and stays where it is.
        var effect: DialEffect?
    }

    /// A recording (1b).
    struct Item: Equatable, Identifiable {
        var id: String
        var title: String
        var duration: TimeInterval
        var subtitle: String?
    }

    /// What the transport is doing (1c), and what the status line on every other screen reports.
    struct Playback: Equatable {
        var title: String
        var subtitle: String?
        var position: TimeInterval
        var duration: TimeInterval
        var isPlaying: Bool
        var volume: Double = 1
        /// The queue is here rather than in the host because `Browse` mode has to know where its
        /// ends are — without a count there is no limit to feel, and the wheel would spin past the
        /// last track for ever.
        var queueIndex: Int = 0
        var queueCount: Int = 1

        var progress: Double {
            guard duration > 0 else { return 0 }
            return min(max(0, position / duration), 1)
        }
    }

    /// A capture in progress (1d).
    struct Capture: Equatable {
        struct Marker: Equatable, Identifiable {
            var id: String
            var label: String
            var time: TimeInterval
        }

        var elapsed: TimeInterval
        /// The scrolling waveform, newest last. Its last sample is also what the ring meters, which
        /// is why there is no separate `level` — two fields for one number drift apart.
        var levels: [Double]
        var gain: Double
        var markers: [Marker]
        var isPaused: Bool = false
        /// Whether this hardware has an input gain at all. Defaults to **false**, which is what
        /// every built-in iPhone mic reports — so the wheel refuses the gain axis unless something
        /// has said otherwise, rather than turning freely against nothing (#75).
        var isGainSettable: Bool = false

        var level: Double { min(max(0, levels.last ?? 0), 1) }
    }

    /// The material the trim editor works on (1e). The handles are not here: they are interaction
    /// state, they live in the navigator's stack, and popping the editor is what discards them.
    struct Editable: Equatable {
        var id: String
        var title: String
        var waveform: [Double]
        var duration: TimeInterval
        /// The points both trim inputs snap to, dropped while this was being captured (#74).
        /// Sorted, because `MarkerSnap` breaks ties toward the earlier one and `RecordingMarkers`
        /// is what fills this in.
        var markers: [TimeInterval] = []
    }

    var sections: [Section] = []
    var recordings: [Item] = []
    var playback: Playback?
    var capture: Capture?
    var editing: Editable?

    func item(_ id: String) -> Item? { recordings.first { $0.id == id } }
}
