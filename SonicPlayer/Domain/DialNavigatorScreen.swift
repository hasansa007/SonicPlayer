import Foundation

/// The projection half of `DialNavigator`: state in, `DialScreen` out (#6).
///
/// Split from the state machine because the two grow for different reasons — the machine grows a
/// case when a *command* means something new, this file grows one when a *screen* looks different.
/// `PlayerViewModel` reached 633 lines by keeping both kinds of growth in one type.
///
/// Everything here is derived. There is no stored copy of a breadcrumb, a hint, a hub label or a
/// row count, so no two of them can disagree about what screen this is.
extension DialNavigator {

    var screen: DialScreen {
        DialScreen(
            chrome: chrome,
            content: screenContent,
            actions: actions,
            ring: ring,
            hint: hint
        )
    }

    // MARK: - Chrome

    private var chrome: DialScreen.Chrome {
        DialScreen.Chrome(
            breadcrumb: stack.compactMap { $0.route.crumb(in: content) },
            status: status,
            isRecording: content.capture.map { !$0.isPaused } ?? false,
            showsSettings: stack.count == 1,
            canGoBack: stack.count > 1
        )
    }

    /// **Nothing, now that the corner is Settings.**
    ///
    /// Kept as a field rather than deleted because the recorder may yet want a word up there, and
    /// because removing it from the contract would touch every screenshot test to prove a negative.
    private var status: String? {
        switch route {
        case .nowPlaying, .recording:
            return nil
        default:
            guard let playback = content.playback else { return nil }
            let state = playback.isPlaying ? "playing" : "paused"
            return "\(DialTimeFormat.clock(playback.position)) ▸ \(state)"
        }
    }

    // MARK: - Content

    private var screenContent: DialScreen.Content {
        switch route {
        case .chooseMode:
            return .list(list(rows: chooserRows))

        case .library:
            return .list(list(rows: libraryRows))

        case .recordings:
            guard !content.recordings.isEmpty else {
                return .message(.init(
                    icon: .recording,
                    title: "No recordings yet",
                    body: "Press the hub to record the first one."
                ))
            }
            return .list(list(rows: recordingRows))

        case .nowPlaying:
            guard let playback = content.playback else {
                return .message(.init(
                    icon: .none,
                    title: "Nothing playing",
                    body: "Open something from the library first."
                ))
            }
            return .nowPlaying(.init(
                title: playback.title,
                subtitle: playback.subtitle,
                elapsed: DialTimeFormat.clock(playback.position),
                remaining: DialTimeFormat.remaining(playback.duration - playback.position),
                progress: playback.progress,
                isPlaying: playback.isPlaying
            ))

        case .recording:
            guard let capture = content.capture else {
                return .message(.init(
                    icon: .recording,
                    title: "Not recording",
                    body: "Press the hub to start."
                ))
            }
            return .recording(.init(
                elapsed: DialTimeFormat.clock(capture.elapsed),
                fraction: DialTimeFormat.tenths(capture.elapsed),
                levels: capture.levels,
                markers: capture.markers.map {
                    .init(id: $0.id, label: $0.label, time: DialTimeFormat.clock($0.time))
                }
            ))

        case .edit:
            guard let editing = content.editing else {
                return .message(.init(
                    icon: .none,
                    title: "Nothing to edit",
                    body: "Open a recording first."
                ))
            }
            let trim = trimRange(for: editing)
            return .edit(.init(
                title: editing.title,
                keeping: DialTimeFormat.clock(trim.length),
                waveform: editing.waveform,
                inFraction: trim.inFraction,
                outFraction: trim.outFraction,
                playheadFraction: nil,
                scale: [
                    DialTimeFormat.clock(0),
                    DialTimeFormat.clock(trim.start),
                    DialTimeFormat.clock(trim.end),
                    DialTimeFormat.clock(editing.duration)
                ]
            ))

        case .actions(let itemID):
            return .list(list(rows: actionRows, subject: subject(for: itemID)))
        }
    }

    private func list(
        rows: [DialScreen.List.Row],
        subject: DialScreen.List.Subject? = nil
    ) -> DialScreen.List {
        DialScreen.List(
            rows: rows,
            highlighted: min(level.highlighted, max(0, rows.count - 1)),
            position: route.countsRows && !rows.isEmpty
                ? "\(min(level.highlighted, rows.count - 1) + 1) of \(rows.count)"
                : nil,
            subject: subject
        )
    }

    /// The recording the action rows act on. Without it the screen is five verbs and no object.
    private func subject(for itemID: String) -> DialScreen.List.Subject? {
        guard let item = content.item(itemID) else { return nil }
        return DialScreen.List.Subject(
            icon: .recording,
            title: item.title,
            detail: [DialTimeFormat.clock(item.duration), item.subtitle]
                .compactMap { $0 }
                .joined(separator: " · ")
        )
    }

    private var chooserRows: [DialScreen.List.Row] {
        [
            .init(id: "listen", icon: .playlist, title: "Listen", subtitle: "Play from your library"),
            .init(id: "record", icon: .recording, title: "Record", subtitle: "Capture something new")
        ]
    }

    /// `12 ▸` when there is somewhere to go, a bare `6` when there is only a count, nothing when
    /// there is neither. The chevron is the affordance, so it is tied to the destination rather
    /// than typed into the title.
    private var libraryRows: [DialScreen.List.Row] {
        content.sections.map { section in
            let trailing = section.count.map { count in
                section.destination == nil ? "\(count)" : "\(count) ▸"
            }
            return .init(
                id: section.id,
                icon: section.icon,
                title: section.title,
                trailing: trailing,
                subtitle: section.subtitle
            )
        }
    }

    private var recordingRows: [DialScreen.List.Row] {
        content.recordings.map {
            .init(
                id: $0.id,
                icon: .recording,
                title: $0.title,
                trailing: DialTimeFormat.clock($0.duration),
                subtitle: $0.subtitle
            )
        }
    }

    private var actionRows: [DialScreen.List.Row] {
        DialItemAction.allCases.map {
            .init(id: $0.rawValue, icon: $0.icon, title: $0.label)
        }
    }

    // MARK: - Actions

    private var actions: [DialScreen.Action] {
        switch route {
        case .chooseMode:
            return []

        case .library:
            // The "Now playing" chip is gone: the dial's border says it now, by moving while
            // audio moves. `Now Playing` is also a row in this very list, so the chip was a second
            // door to a room already on screen.
            return []

        case .recordings:
            guard !content.recordings.isEmpty else {
                // Destructive rather than primary: starting a recording is the obvious action here
                // and also the one you cannot casually undo, and those must not look alike.
                return [.init(id: "record", label: "Record", emphasis: .destructive)]
            }
            // `Edit` is the visible partner for `.doublePress`; the contract requires one.
            // Both moved onto the stick — right nudges to Edit, left to the actions menu.
            return []

        // Nothing at all: the wheel seeks, the segments do volume and track, and Back is in the
        // top bar. A screen can legitimately have no chips.
        case .nowPlaying:
            return []

        case .recording:
            let paused = content.capture?.isPaused ?? false
            // Both moved onto the stick — up adds a marker, left pauses.
            _ = paused
            return []

        case .edit:
            return modeChips + [.init(id: "preview", label: "Preview")]

        case .actions:
            return []
        }
    }

    /// `back` is no longer a chip — it is the top bar's chevron — but the *command* is unchanged
    /// and still accepted on every screen, so nothing that used to send it has broken.

    /// Exactly one `.selected`, always — the selected index is clamped into the mode list, so there
    /// is no state in which a screen with modes shows none chosen.
    private var modeChips: [DialScreen.Action] {
        let modes = route.modes
        guard !modes.isEmpty else { return [] }

        let selected = min(level.mode, modes.count - 1)
        return modes.enumerated().map { index, mode in
            .init(id: mode.id, label: mode.label, emphasis: index == selected ? .selected : .plain)
        }
    }

    // MARK: - Ring

    private var ring: DialScreen.Ring {
        DialScreen.Ring(
            ticks: ticks,
            hub: hub,
            defersPress: defersPress,
            directions: directions,
            isLive: isLive
        )
    }

    /// True only where `doublePress()` has something to do — which today is a highlighted recording.
    /// Everywhere else a press is instant, because there is no second meaning to wait for.
    private var defersPress: Bool {
        guard case .recordings = route else { return false }
        return content.recordings.indices.contains(level.highlighted)
    }

    /// What the gear stick does here.
    ///
    /// **This is where the chip row went.** Each screen's most-used actions moved onto the four
    /// nudges, which is why `actions` is empty on the three screens below — one control surface
    /// instead of two, and the height the chips took back for content.
    private var directions: DialScreen.Directions? {
        switch route {
        case .nowPlaying:
            guard content.playback != nil else { return nil }
            return DialScreen.Directions(
                up: .init(id: "volumeUp", icon: .volumeUp, label: "Volume up"),
                down: .init(id: "volumeDown", icon: .volumeDown, label: "Volume down"),
                left: .init(id: "previous", icon: .previous, label: "Previous track"),
                right: .init(id: "next", icon: .next, label: "Next track")
            )

        case .recording:
            guard let capture = content.capture else { return nil }
            return DialScreen.Directions(
                up: .init(id: "marker", icon: .marker, label: "Add marker"),
                left: .init(
                    id: "pause",
                    icon: capture.isPaused ? .play : .pause,
                    label: capture.isPaused ? "Resume" : "Pause"
                )
            )

        case .recordings:
            guard !content.recordings.isEmpty else { return nil }
            return DialScreen.Directions(
                left: .init(id: "more", icon: .more, label: "More actions"),
                right: .init(id: "edit", icon: .edit, label: "Edit")
            )

        default:
            return nil
        }
    }

    /// The border cycles while audio is moving, and only then.
    private var isLive: Bool {
        if let capture = content.capture { return !capture.isPaused }
        return content.playback?.isPlaying == true && route == .nowPlaying
    }

    private var ticks: DialScreen.Ticks {
        switch route {
        case .nowPlaying:
            guard let playback = content.playback else { return .browse(thumb: nil) }
            switch axis {
            case .volume: return .position(playback.volume)
            case .queue: return .browse(thumb: fraction(playback.queueIndex, of: playback.queueCount))
            default: return .position(playback.progress)
            }

        case .recording:
            return .level(content.capture?.level ?? 0)

        case .edit:
            guard let editing = content.editing else { return .browse(thumb: nil) }
            let trim = trimRange(for: editing)
            return .position(axis == .trimEnd ? trim.outFraction : trim.inFraction)

        default:
            return .browse(thumb: fraction(level.highlighted, of: rowCount(route)))
        }
    }

    private var hub: DialScreen.Hub {
        switch route {
        case .chooseMode: .label("CHOOSE")
        case .library: .label("OPEN")
        case .recordings: content.recordings.isEmpty ? .label("RECORD") : .label("OPEN")
        case .nowPlaying: .glyph(content.playback?.isPlaying == false ? "play.fill" : "pause.fill")
        case .recording: .recordDot
        case .edit: .label("DONE")
        case .actions: .label("SELECT")
        }
    }

    // MARK: - Hint

    /// The only thing teaching rotate/press/hold, so it follows the mode rather than describing the
    /// screen in general — a caption that says "rotate to seek" while the wheel is set to Volume is
    /// worse than none.
    private var hint: String {
        switch route {
        case .chooseMode:
            return "rotate to switch mode · press to choose"

        case .library:
            return "rotate to browse · press to open · hold for now playing"

        case .recordings:
            return content.recordings.isEmpty
                ? "press to start recording · nothing to scroll yet"
                : "rotate to scroll · press to open · double-press to edit"

        case .nowPlaying:
            // One sentence, because the wheel does one thing. The segments beside and above it
            // are named in the third clause rather than getting a hint each.
            let press = content.playback?.isPlaying == false ? "press to play" : "press to pause"
            return "rotate to seek · \(press) · nudge for track and volume"

        case .recording:
            return "ring shows input level · rotate to set gain · press to stop"

        case .edit:
            return "rotate to nudge the active handle · press when done"

        case .actions:
            return "rotate to highlight an action · press to confirm"
        }
    }

    // MARK: - Helpers

    /// The editor's selection, or the whole recording when the level has none — which happens only
    /// if `content.editing` arrived after the screen was pushed.
    private func trimRange(for editing: DialContent.Editable) -> DialTrimRange {
        level.trim ?? DialTrimRange(start: 0, end: editing.duration, duration: editing.duration)
    }

    /// Where an index sits across a run of them, `0...1`. A run of one has no position to report —
    /// lighting the first tick would claim the wheel is at the start of something it cannot leave.
    private func fraction(_ index: Int, of count: Int) -> Double? {
        guard count > 1 else { return nil }
        return Double(min(max(0, index), count - 1)) / Double(count - 1)
    }
}
