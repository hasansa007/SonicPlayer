#if DEBUG
import SwiftUI

/// One realistic `DialScreen` per screen in the design, and the previews that render them (#6).
///
/// **Hand-written, and that is the point.** The navigator is being built in parallel against the
/// same two files; fixtures let this half be finished, looked at and corrected before either half
/// has seen the other. Every value here is the design's own copy, so a preview that looks wrong is
/// a real disagreement rather than a placeholder.
///
/// Wrapped in `#if DEBUG` — including the previews, which is why they all live here rather than
/// beside each view. A `#Preview` outside the fence referring to fixtures inside it would break the
/// release build, and fixtures outside the fence would ship in the binary.
enum DialPreviewData {

    // MARK: - 1a · Library home

    static let libraryHome = DialScreen(
        chrome: .init(breadcrumb: ["LIBRARY"], showsSettings: true),
        content: .list(.init(
            rows: [
                .init(id: "playlists", icon: .playlist, title: "Playlists", trailing: "6"),
                .init(id: "recordings", icon: .recording, title: "Recordings", trailing: "12 ▸"),
                // Where the corner label went: the clock at the trailing edge, the track named on
                // the second line — the two things it could not do at once up there.
                .init(
                    id: "nowPlaying",
                    icon: .session,
                    title: "Now Playing",
                    trailing: "20:34 · playing",
                    subtitle: "Deep Work, Chapter 4"
                ),
                .init(id: "sessions", icon: .session, title: "Focus Sessions", trailing: "24"),
                .init(id: "podcasts", icon: .podcast, title: "Podcasts", trailing: "9"),
                .init(id: "stats", icon: .stats, title: "Stats", trailing: "▸")
            ],
            highlighted: 1
        )),
        actions: [
            .init(id: "back", label: "‹ Back"),
            .init(id: "play", label: "Play", emphasis: .primary),
            .init(id: "more", label: "•••")
        ],
        ring: .init(ticks: .browse(thumb: 0.3), hub: .label("OPEN")),
        hint: "rotate to browse · press to open · hold for now playing"
    )

    // MARK: - 1b · Recordings drill-in

    static let recordings = DialScreen(
        chrome: .init(breadcrumb: ["LIBRARY", "RECORDINGS"], canGoBack: true),
        content: .list(.init(
            rows: [
                .init(
                    id: "new-4",
                    icon: .recording,
                    title: "New Recording 4",
                    trailing: "12:07",
                    subtitle: "Today 14:02 · 2 markers"
                ),
                .init(id: "interview", icon: .recording, title: "Interview — Ep. 12", trailing: "26:40"),
                .init(id: "memo", icon: .recording, title: "Voice memo — ideas", trailing: "03:12"),
                .init(id: "standup", icon: .recording, title: "Standup notes", trailing: "08:55"),
                .init(id: "lecture", icon: .recording, title: "Lecture — acoustics", trailing: "51:20")
            ],
            highlighted: 0,
            position: "1 of 12"
        )),
        actions: [
            .init(id: "back", label: "‹ Back"),
            .init(id: "play", label: "Play", emphasis: .primary),
            .init(id: "edit", label: "Edit")
        ],
        ring: .init(ticks: .browse(thumb: 0.03), hub: .label("OPEN")),
        hint: "rotate to scroll · press to open · double-press to edit"
    )

    // MARK: - 1c · Now playing

    /// Nothing up top but the way back: this screen owns the transport, and the two time labels
    /// under the bar already say everything a status line could.
    static let nowPlaying = DialScreen(
        chrome: .init(breadcrumb: [], canGoBack: true),
        content: .nowPlaying(.init(
            title: "Deep Focus Session",
            subtitle: "Rainfall mix · Focus",
            elapsed: "20:34",
            remaining: "−25:11",
            progress: 0.45,
            isPlaying: true
        )),
        actions: [
            .init(id: "seek", label: "Seek", emphasis: .selected),
            .init(id: "volume", label: "Volume"),
            .init(id: "browse", label: "Browse")
        ],
        ring: .init(ticks: .position(0.45), hub: .glyph("pause.fill")),
        hint: "rotate to seek · press to pause · ticks show position"
    )

    // MARK: - 1d · Recording

    static let recording = DialScreen(
        chrome: .init(breadcrumb: [], isRecording: true, canGoBack: true),
        content: .recording(.init(
            elapsed: "12:07",
            fraction: "4",
            levels: levels(count: 28, seed: 1),
            markers: [
                .init(id: "m1", label: "Marker 1", time: "03:22"),
                .init(id: "m2", label: "Marker 2", time: "08:45")
            ]
        )),
        actions: [
            .init(id: "marker", label: "＋ Marker"),
            .init(id: "pause", label: "Pause")
        ],
        ring: .init(ticks: .level(0.62), hub: .recordDot),
        hint: "ring shows input level · rotate to set gain · press to stop"
    )

    // MARK: - 1e · Edit / trim

    /// **Five chips in the action row, and only three of them are the mode selector.** The design
    /// draws `Delete selection` and `Split at playhead` inside the card, but `DialScreen.Edit` has
    /// no field for them and the contract says a screen may carry five actions with real words.
    /// So they are actions. The row centres when it fits and scrolls when it does not.
    static let edit = DialScreen(
        chrome: .init(breadcrumb: [], canGoBack: true),
        content: .edit(.init(
            title: "New Recording 4",
            keeping: "08:12",
            waveform: levels(count: 48, seed: 5),
            inFraction: 0.2,
            outFraction: 0.7,
            playheadFraction: 0.42,
            scale: ["0:00", "IN 02:25", "OUT 10:37", "12:07"]
        )),
        actions: [
            .init(id: "start", label: "Start handle", emphasis: .selected),
            .init(id: "end", label: "End handle"),
            .init(id: "preview", label: "Preview"),
            .init(id: "delete", label: "Delete selection"),
            .init(id: "split", label: "Split at playhead")
        ],
        ring: .init(ticks: .browse(thumb: 0.2), hub: .label("DONE")),
        hint: "rotate to nudge the active handle · press when done"
    )

    // MARK: - 1f · Item actions

    static let itemActions = DialScreen(
        chrome: .init(breadcrumb: ["RECORDINGS", "ACTIONS"], canGoBack: true),
        content: .list(.init(
            rows: [
                .init(id: "share", icon: .share, title: "Share file…", trailing: "▸"),
                .init(id: "playlist", icon: .playlist, title: "Add to playlist", trailing: "3 ▸"),
                // `.none`, not `.add`: `DialScreen.Icon` has no export role and a plus beside
                // "Export as MP3" says the wrong thing. The row holds the icon column open rather
                // than closing it, so the titles stay on one margin. See the report's contract notes.
                .init(id: "export", icon: .none, title: "Export as MP3"),
                .init(id: "rename", icon: .rename, title: "Rename"),
                .init(id: "delete", icon: .delete, title: "Delete")
            ],
            highlighted: 0,
            position: "1 of 5"
        )),
        actions: [
            .init(id: "back", label: "‹ Back"),
            .init(id: "select", label: "Select", emphasis: .primary)
        ],
        ring: .init(ticks: .browse(thumb: 0.03), hub: .label("SELECT")),
        hint: "rotate to highlight an action · press to confirm"
    )

    // MARK: - 1g · Empty state

    /// `browse(thumb: nil)` is what "nothing to scroll yet" looks like on the ring: every tick dim,
    /// so the dial says the same thing the hint does.
    static let empty = DialScreen(
        chrome: .init(breadcrumb: ["LIBRARY", "RECORDINGS"], canGoBack: true),
        content: .message(.init(
            icon: .recording,
            title: "No recordings yet",
            body: "Press the wheel to start your first recording. It will save here automatically."
        )),
        actions: [
            .init(id: "back", label: "‹ Back"),
            .init(id: "record", label: "Record", emphasis: .primary)
        ],
        ring: .init(ticks: .browse(thumb: nil), hub: .recordDot),
        hint: "press to start recording · nothing to scroll yet"
    )

    // MARK: - 1h · Listen vs record

    /// Two rows, so `DialListView` renders them prominently — the contract folds this screen into
    /// `List` with the other three, and the row count is the honest signal for "a choice between
    /// two things" rather than "a list to scroll".
    static let chooser = DialScreen(
        chrome: .init(breadcrumb: ["START"], showsSettings: true),
        content: .list(.init(
            rows: [
                .init(
                    id: "listen",
                    icon: .session,
                    title: "Listen",
                    trailing: "▸",
                    subtitle: "Playlists · Sessions · Podcasts"
                ),
                .init(
                    id: "record",
                    icon: .recording,
                    title: "Record",
                    subtitle: "New recording · 4h 12m free"
                )
            ],
            highlighted: 0,
            position: "1 of 2"
        )),
        actions: [
            .init(id: "open", label: "Open", emphasis: .primary),
            .init(id: "settings", label: "Settings")
        ],
        ring: .init(ticks: .browse(thumb: 0), hub: .label("OPEN")),
        hint: "rotate to switch mode · press to choose"
    )

    // MARK: - Fixture waveforms

    /// A repeatable pseudo-random envelope, taken from the design file's own seed function.
    ///
    /// Deterministic on purpose: `Double.random` in a fixture means a preview that looks different
    /// every time it recompiles, so "did that change?" stops being answerable by looking.
    private static func levels(count: Int, seed: Double) -> [Double] {
        (0 ..< count).map { index in
            let noise = abs(sin(Double(index) * 12.9898 + seed) * 43758.5453)
                .truncatingRemainder(dividingBy: 1)
            // An envelope that swells toward the middle, so the bars read as audio rather than as
            // a bar chart of noise.
            let envelope = 1 - abs(Double(index) - Double(count) / 2) / (Double(count) / 2)
            return 0.2 + noise * 0.8 * (0.35 + envelope * 0.65)
        }
    }
}

// MARK: - Previews

#Preview("1a · Library home") {
    DialScreenView(screen: DialPreviewData.libraryHome) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("1b · Recordings") {
    DialScreenView(screen: DialPreviewData.recordings) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("1c · Now playing") {
    DialScreenView(screen: DialPreviewData.nowPlaying) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("1d · Recording") {
    DialScreenView(screen: DialPreviewData.recording) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("1e · Edit") {
    DialScreenView(screen: DialPreviewData.edit) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("1f · Item actions") {
    DialScreenView(screen: DialPreviewData.itemActions) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("1g · Empty") {
    DialScreenView(screen: DialPreviewData.empty) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("1h · Listen vs record") {
    DialScreenView(screen: DialPreviewData.chooser) { _ in }
        .preferredColorScheme(.dark)
}

// The design is dark and the app is not. These three cover the structurally different screens in
// light mode, because "check both" is a thing that only happens if it is one click away.

#Preview("Light · 1a") {
    DialScreenView(screen: DialPreviewData.libraryHome) { _ in }
        .preferredColorScheme(.light)
}

#Preview("Light · 1c") {
    DialScreenView(screen: DialPreviewData.nowPlaying) { _ in }
        .preferredColorScheme(.light)
}

#Preview("Light · 1d") {
    DialScreenView(screen: DialPreviewData.recording) { _ in }
        .preferredColorScheme(.light)
}

// The dial alone, in every mode it has. Faster to judge the ring against the design here than by
// hunting for the screen that happens to use a given tick set.

#Preview("Dial · every mode") {
    ScrollView {
        VStack(spacing: Spacing.xl) {
            DialRing(ticks: .browse(thumb: 0.3), hub: .label("OPEN")) { _ in }
            DialRing(ticks: .position(0.45), hub: .glyph("pause.fill")) { _ in }
            DialRing(ticks: .level(0.62), hub: .recordDot) { _ in }
            DialRing(ticks: .browse(thumb: nil), hub: .label("DONE")) { _ in }
        }
        .padding(Spacing.xl)
    }
    .background(Color.sonicBackground)
    .preferredColorScheme(.dark)
}
#endif
