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

        /// Whether the top-right corner offers Settings.
        ///
        /// It replaced the `20:34 ▸ playing` label that used to sit there. That label was doing two
        /// jobs badly: saying what was playing, in a space too small to name it, and being the only
        /// way to reach Now Playing. Both moved to a row in the library, which has room for a title
        /// — and the corner went to the one thing that had nowhere to live at all.
        var showsSettings: Bool = false

        /// Whether there is a level to pop to.
        ///
        /// Back lives in the top bar rather than the action row because it is *navigation*, not one
        /// of the things this screen does. Mixing "go up a level" in with "delete this file" made
        /// them look like peers, and it cost the action row a slot on every screen below the root.
        var canGoBack: Bool = false
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
            /// The right-hand value — a duration (`"12:07"`), a count (`"12"`), or nothing.
            var trailing: String?
            /// The second line, e.g. `"Today 14:02 · 2 markers"`. Only some rows have one.
            var subtitle: String?
            /// Whether pressing this row goes somewhere, as opposed to doing something in place.
            ///
            /// **This used to be a `▸` glued onto the end of `trailing`**, which made the count and
            /// the affordance one string: a row could not have a count without also claiming to
            /// navigate, and the view could not draw a real chevron without printing two. Once the
            /// card style drew an actual glyph they appeared together — `3 ▸ ›` — which is the
            /// stringly-typed version showing through.
            var opensSomewhere: Bool = false
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
        /// Whether the rows are the large cards of a top-level menu rather than the compact rows of
        /// a list you scan.
        ///
        /// **This used to be `rows.count <= 2`, inferred in the view, and that was a latent style
        /// flip.** The library home has two rows when nothing is loaded and three the moment
        /// something is, so a count-derived rule made the whole screen change shape as playback
        /// started — the cards it was designed as, collapsing into a plain list because a fourth
        /// thing had happened elsewhere. It is a property of *which screen this is*, so the
        /// navigator states it and the view obeys.
        var isProminent: Bool = false
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

    /// Which trim handle the wheel is currently nudging.
    ///
    /// **The screen could not say this before.** `DialEditView` drew the start handle active
    /// unconditionally, with a comment admitting it: the selection lived in the action row's
    /// `.selected` chip and never reached the contract. So selecting `End` moved the end handle
    /// while the picture went on highlighting the start one. With the chips gone and selection now
    /// made by tapping a handle, the screen has to be able to answer this.
    enum Handle: Equatable {
        case start
        case end
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
        var activeHandle: Handle = .start
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
        /// Bringing a file in from outside the app. The mirror of `export`, and not `add` — `add`
        /// is a bare plus, which says "one more of these" rather than "from somewhere else".
        case importFile
        /// A collection of recordings, as a place rather than as the act of recording. Distinct
        /// from `recording`, which is the microphone.
        case library
        // Roles the gear stick's directions need. Named for what they do, not for the symbol, so
        // the view still owns every glyph choice.
        case volumeUp
        case volumeDown
        case previous
        case next
        case pause
        case play
        case edit
        case more
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

        /// What the gear stick's four nudges do **on this screen**. `nil` leaves the hub press-only.
        ///
        /// Contextual for the same reason `hub` is: one control, and what it means comes from where
        /// you are. Now Playing puts volume on the vertical axis and track on the horizontal; the
        /// recorder puts a marker up and pause left; a list puts Edit and its menu on the sides.
        ///
        /// **This is what let the chip row go.** Those chips were a second control surface sitting
        /// above the only one that mattered, and every screen paid for them in height. Folding them
        /// into the stick keeps the promise the dial makes — there is one thing to touch.
        var directions: Directions?

        /// Whether the dial's border is alive: it cycles while something is playing or recording,
        /// and holds still when nothing is. The only motion on the screen, and it means one thing.
        var isLive: Bool = false
    }

    /// The gear stick's four ways out. Any of them may be absent, and an absent one does nothing —
    /// a screen with only `up` is a perfectly good screen.
    struct Directions: Equatable {
        var up: Direction?
        var down: Direction?
        var left: Direction?
        var right: Direction?
    }

    /// One nudge: what it is called, what it looks like, and what it sends.
    ///
    /// It carries an action `id` rather than a command, so the navigator handles a nudge and a tap
    /// on the same chip through one path — which is what stops the two drifting apart the way
    /// press and double-press did.
    struct Direction: Equatable {
        var id: String
        var icon: Icon
        /// What VoiceOver says. The glyph is a legend; this is the name.
        var label: String
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
