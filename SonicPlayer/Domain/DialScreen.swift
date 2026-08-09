import Foundation

/// **The contract between the dial's logic and its pixels.**
///
/// Every screen in the dial navigator is one of these values. The UI renders a `DialScreen` and
/// knows nothing about playback, files or recording; the navigator produces a `DialScreen` and
/// knows nothing about SwiftUI. Neither half needs the other to exist, which is what lets them be
/// built in parallel and tested apart.
///
/// The shape is taken from the design, where all eight screens share one vertical stack:
///
///     chrome     breadcrumb + status          LIBRARY ▸ RECORDINGS
///     content    the part that differs        a list, a player, a meter, a waveform
///     actions    a row of chips above the ring   ‹ Back · Play · •••
///     ring       ticks + hub                  the only input surface
///     hint       one line of plain language   "rotate to scroll · press to open"
///
/// **`actions` is a row, not labels on the ring.** The earlier prototype hung four labels off the
/// ring's cardinal points, which capped it at four and made them tiny. Here the ring is pure input
/// and the actions are touch targets above it — so a screen can have two or five, with real words.
struct DialScreen: Equatable {

    var chrome: Chrome
    var content: Content
    var actions: [Action]
    var ring: Ring
    /// The caption under the wheel. Plain language, lowercase, separated by `·` — it is the only
    /// thing teaching rotate/press/hold, so it is content rather than decoration.
    var hint: String

    // MARK: - Chrome

    struct Chrome: Equatable {
        /// `["LIBRARY", "RECORDINGS"]` renders as `LIBRARY ▸ RECORDINGS`. Empty is a valid header.
        var breadcrumb: [String]
        /// The right-hand status, e.g. `"20:34 ▸ playing"`. Absent on screens that own the transport.
        var status: String?
        /// Drives the pulsing dot. Separate from `status` because it animates.
        var isRecording: Bool = false
    }

    // MARK: - Content

    enum Content: Equatable {
        case list(List)
        case nowPlaying(NowPlaying)
        case recording(Recording)
        case edit(Edit)
        /// The empty state — an icon, a title and a sentence telling you what the wheel will do.
        case message(Message)
    }

    /// Screens 1a, 1b, 1f and 1h are all this, which is why they share one type: a highlighted row
    /// in a vertical list is the dial's fundamental gesture.
    struct List: Equatable {
        struct Row: Equatable, Identifiable {
            var id: String
            var icon: Icon
            var title: String
            /// The right-hand value — a duration (`"12:07"`), a count (`"12 ▸"`), or nothing.
            var trailing: String?
            /// The second line, e.g. `"Today 14:02 · 2 markers"`. Only some rows have one.
            var subtitle: String?
        }

        /// What the list is *about*, shown above the rows.
        ///
        /// The actions screen needs this — its rows act on one recording, and without naming that
        /// recording the screen is five verbs with no object. A plain menu has no subject and
        /// leaves this nil.
        struct Subject: Equatable {
            var icon: Icon
            var title: String
            /// A second line, e.g. `"12:07 · Today 14:02"`.
            var detail: String?
        }

        var rows: [Row]
        /// Index into `rows`. **Always valid when `rows` is non-empty** — the navigator clamps it,
        /// so the UI never has to decide what an out-of-range highlight looks like.
        var highlighted: Int
        /// `"1 of 12"`. Nil when the list is short enough that counting is noise.
        var position: String?
        var subject: Subject?
    }

    struct NowPlaying: Equatable {
        var title: String
        var subtitle: String?
        /// Preformatted, because the navigator owns the clock and the UI owns none of it.
        var elapsed: String
        /// Signed and preformatted, e.g. `"−25:11"`.
        var remaining: String
        var progress: Double
        var isPlaying: Bool
    }

    struct Recording: Equatable {
        struct Marker: Equatable, Identifiable {
            var id: String
            var label: String
            var time: String
        }

        var elapsed: String
        /// The tenths, drawn smaller — `"4"` renders as `12:07.4`.
        var fraction: String?
        /// The live scrolling waveform, newest last, each `0...1`.
        var levels: [Double]
        var markers: [Marker]
    }

    struct Edit: Equatable {
        var title: String
        /// How much survives the trim, e.g. `"08:12"`.
        var keeping: String
        var waveform: [Double]
        /// All `0...1` across the full duration.
        var inFraction: Double
        var outFraction: Double
        var playheadFraction: Double?
        /// The four labels under the waveform: start, IN, OUT, end.
        var scale: [String]
    }

    struct Message: Equatable {
        var icon: Icon
        var title: String
        var body: String
    }

    /// Named roles rather than SF Symbol strings, so the UI owns the symbol choice and the
    /// navigator cannot accidentally pin an icon that does not exist.
    enum Icon: Equatable {
        case playlist
        case recording
        case session
        case podcast
        case stats
        case marker
        case share
        /// Writing a copy out of the app. Distinct from `share`, which hands the existing file to
        /// another app — reusing `share` put the same glyph on two rows of one list, which reads
        /// as a bug rather than as a pair.
        case export
        case rename
        case delete
        case add
        case none
    }

    // MARK: - Actions

    /// One chip in the row above the ring. These are **touch** targets; the ring is the wheel.
    struct Action: Equatable, Identifiable {
        enum Emphasis: Equatable {
            /// Ordinary chip.
            case plain
            /// Filled — the one thing this screen most expects you to do.
            case primary
            /// Currently active, e.g. the chosen wheel mode on Now Playing, or which trim handle
            /// the wheel is nudging.
            case selected
            /// Starts something, or destroys something, that the user cannot casually undo —
            /// beginning a recording, deleting a file. Rendered in the warning colour rather than
            /// the accent, so "the one thing this screen expects" and "the one thing you cannot
            /// take back" never look alike.
            case destructive
            /// Present but not available yet.
            case disabled
        }

        var id: String
        var label: String
        var emphasis: Emphasis = .plain
    }

    // MARK: - Ring

    struct Ring: Equatable {
        var ticks: Ticks
        var hub: Hub

        /// Whether this screen distinguishes a press from a double-press — and therefore whether
        /// the ring must wait `DialCommand.doublePressWindow` before reporting the first one.
        ///
        /// **This field exists because the two halves of the dial disagreed without it.** The view
        /// cannot know a second press is coming, so it either delays *every* press by 300ms to find
        /// out, or fires immediately and sends `.doublePress` afterwards as an escalation. The
        /// first puts lag on the most-used gesture in the app to serve the rarest; the second means
        /// the navigator receives `.doublePress` only *after* a `.press` has already navigated
        /// away, so the guard that recognises it no longer holds. That shipped as a silently dead
        /// gesture, and every test passed, because the suite fed `.doublePress` on its own.
        ///
        /// Naming it makes the cost land where the feature is: exactly one screen waits, and every
        /// other press is instant.
        var defersPress: Bool = false

        /// The current output level, `0...1`, when this screen offers a volume segment beside the
        /// wheel. `nil` means no segment.
        ///
        /// It lives on `Ring` rather than in `Content` because it is part of the *control cluster* —
        /// what you touch — and the content is what you read. The two segments and the wheel are one
        /// thing on screen and should be one thing here.
        var volume: Double?

        /// Whether the track-stepping segment sits above the wheel.
        var showsTrackStepper: Bool = false
    }

    /// What the ring's tick marks are showing. The design uses a different set per screen —
    /// `ticksBrowse`, `ticksSeek`, `ticksLevel` — and this is that choice as a value.
    enum Ticks: Equatable {
        /// Plain detent marks. The optional fraction lights one, following the thumb.
        case browse(thumb: Double?)
        /// Filled proportionally, `0...1` — the ring doubles as a progress readout while seeking.
        case position(Double)
        /// **The ring becomes a level meter.** `0...1` input level while recording, which is the
        /// idea that gives the wheel a job during the one activity it otherwise has none.
        case level(Double)
    }

    enum Hub: Equatable {
        /// A word: `OPEN`, `SELECT`, `DONE`.
        case label(String)
        /// An SF Symbol name, e.g. `"pause.fill"`.
        case glyph(String)
        /// The recording screen's centre, which pulses rather than reading anything.
        case recordDot
    }
}
