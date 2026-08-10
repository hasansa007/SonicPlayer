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

    /// `00:49 ▸ playing`, on every screen you can still be browsing from.
    ///
    /// **This is the fast path back, and it beat the row that briefly replaced it.** The row could
    /// name the track, which the corner cannot — but it only existed on home, so the moment you
    /// were two levels into the library there was no visible way back to what was playing at all.
    /// `hold` reaches it from anywhere and is invisible; a label that is already on screen saying
    /// something is playing costs nothing to make the door.
    ///
    /// Absent on the three screens that would be lying or shouting: Now Playing *is* the
    /// destination, and Recording and Edit have taken the audio session — playback is paused there
    /// by the time you arrive, so a line reporting it as playing would be stale on arrival.
    private var status: String? {
        switch route {
        case .nowPlaying, .recording, .edit:
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

        // **Always a list.** Import is row 0 and is always there, so there is never nothing to draw
        // — and the empty-state message could not have held a row anyway. What the message said
        // lives on that row's second line when the library is bare.
        case .recordings:
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
                activeHandle: axis == .trimEnd ? .end : .start,
                scale: [
                    DialTimeFormat.clock(0),
                    DialTimeFormat.clock(trim.start),
                    DialTimeFormat.clock(trim.end),
                    DialTimeFormat.clock(editing.duration)
                ]
            ))

        // The subject is not decoration here — it is the whole guard. Two verbs with nothing
        // naming what they act on is exactly the screen `Delete` must not be.
        case .confirmDelete(let itemID):
            return .list(list(rows: deleteChoiceRows, subject: subject(for: itemID)))

        case .confirmTrim(let itemID):
            return .list(list(rows: trimChoiceRows, subject: subject(for: itemID)))
        }
    }

    private func list(
        rows: [DialScreen.List.Row],
        subject: DialScreen.List.Subject? = nil
    ) -> DialScreen.List {
        DialScreen.List(
            rows: rows,
            highlighted: min(level.highlighted, max(0, rows.count - 1)),
            subject: subject,
            isProminent: route.showsProminentRows
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

    /// The count when there is one, and separately whether the row goes anywhere.
    ///
    /// The chevron used to be `▸` appended to the count string. It is a flag now, for the reason
    /// `DialScreen.List.Row.opensSomewhere` gives — one field cannot be both a number and an
    /// affordance without the view being unable to draw either properly.
    private var libraryRows: [DialScreen.List.Row] {
        content.sections.map { section in
            .init(
                id: section.id,
                icon: section.icon,
                title: section.title,
                trailing: section.count.map { "\($0)" },
                subtitle: section.subtitle,
                opensSomewhere: section.destination != nil
            )
        }
    }

    /// Import, then every audio file the app can see.
    ///
    /// **Import belongs to a library, which is what this screen turned out to be.** It was tried as
    /// a card on home, a chip here, a row here, and then removed altogether — the removal on the
    /// reasoning that iOS already provides the share sheet and Open-in. What that missed is that a
    /// library is the place you *add to*: reaching it from a card marked `Library` and finding no
    /// way to put anything in is the gap that sent it back.
    ///
    /// `RecordingsRow` owns the offset this creates, and everything that reads the highlight goes
    /// through it. This is only the drawing half of the same fact.
    private var recordingRows: [DialScreen.List.Row] {
        let importRow = DialScreen.List.Row(
            id: "import",
            icon: .importFile,
            title: "Import",
            // The empty state's sentence, folded into the row that answers it — with nothing else
            // in the library this is the only row, so it has to say why the screen is bare.
            subtitle: content.recordings.isEmpty
                ? "Nothing here yet · bring audio in"
                : "Bring audio in from Files"
        )

        return [importRow] + content.recordings.map {
            .init(
                id: $0.id,
                icon: .recording,
                title: $0.title,
                trailing: DialTimeFormat.clock($0.duration),
                subtitle: $0.subtitle
            )
        }
    }

    private var trimChoiceRows: [DialScreen.List.Row] {
        DialRoute.TrimChoice.allCases.map {
            .init(id: $0.rawValue, icon: $0.icon, title: $0.label)
        }
    }

    private var deleteChoiceRows: [DialScreen.List.Row] {
        DialRoute.DeleteChoice.allCases.map {
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

        // **No chip on the empty library either.** A red `Record` used to sit here, on the argument
        // that an empty library most wants filling. But that band is dead space on every other
        // screen in the app, and one lone control appearing in it — only when the library is empty,
        // only in red — reads as an alert rather than an offer. `Record` is a card on home, one Back
        // away, which is where every other destination lives.
        case .recordings:
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

        // **No chips.** `Start handle` and `End handle` were how you chose which one the wheel
        // nudged; you tap the handle itself now, which is where your eye already is. `Preview` went
        // with them — a third control to hear the result was one more thing between you and the
        // trim, and the waveform plus `Keeping` already say what you are about to keep.
        case .edit:
            return []

        case .confirmDelete, .confirmTrim:
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
        // Not on Import: there is no second meaning there, so waiting to find out whether a second
        // press is coming would delay the one press that has nothing to wait for.
        guard case .recording(let index)? = highlightedLibraryRow else { return false }
        return content.recordings.indices.contains(index)
    }

    /// What the highlight is pointing at on the library list, or `nil` anywhere else.
    private var highlightedLibraryRow: RecordingsRow? {
        guard case .recordings = route else { return nil }
        return RecordingsRow.at(level.highlighted, recordings: content.recordings.count)
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

        // **Trim keeps the selection, delete removes it — the two things you can do to a region.**
        // The hub stays `DONE`, so the wheel says what the selection is *for* rather than making
        // you find it on a menu. Absent until the material has loaded: nothing to act on.
        case .edit:
            guard content.editing != nil else { return nil }
            return DialScreen.Directions(
                up: .init(id: "trim", icon: .edit, label: "Trim to selection"),
                down: .init(id: "cut", icon: .delete, label: "Delete selection")
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

        // **All four, and no menu behind them.** These were rows on a pushed screen reached by a
        // `···` nudge: a nudge, a turn and a press to do one thing, and a whole route to hold five
        // verbs. Four fit the four directions the stick already has, so the screen went — and
        // `Rename`, the fifth, moved onto the edit screen, where you are already changing the
        // recording. A nudge has no room for a word, so the glyph is the whole label.
        //
        // Absent on the Import row: they act on the highlighted *recording*, and offering `Delete`
        // while the highlight is on Import is offering to delete nothing.
        case .recordings:
            guard case .recording? = highlightedLibraryRow else { return nil }
            return DialScreen.Directions(
                up: .init(id: "edit", icon: .edit, label: "Edit"),
                down: .init(id: "delete", icon: .delete, label: "Delete"),
                left: .init(id: "add", icon: .playlist, label: "Add to playlist"),
                right: .init(id: "share", icon: .share, label: "Share")
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
        // The hub says what *this row* does, which is the whole point of one button meaning
        // something different everywhere. On Import it cannot say OPEN.
        case .recordings: highlightedLibraryRow == .importFiles ? .label("IMPORT") : .label("OPEN")
        case .nowPlaying: .glyph(content.playback?.isPlaying == false ? "play.fill" : "pause.fill")
        case .recording: .recordDot
        // **Two states, one button.** `DONE` settles the handles; after that the hub plays the
        // region you are about to keep. Committing is not here at all — it is the question `Back`
        // asks, which is what stops `Done` and `Back` being one keystroke apart with opposite
        // consequences.
        case .edit: level.isTrimSettled ? .glyph("play.fill") : .label("DONE")
        case .confirmDelete: .label("CONFIRM")
        case .confirmTrim: .label("CONFIRM")
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
            if highlightedLibraryRow == .importFiles {
                return content.recordings.isEmpty
                    ? "press to import · nothing else here yet"
                    : "press to import · rotate for your files"
            }
            return "rotate to scroll · press to open · double-press to edit"

        case .nowPlaying:
            // One sentence, because the wheel does one thing. The segments beside and above it
            // are named in the third clause rather than getting a hint each.
            let press = content.playback?.isPlaying == false ? "press to play" : "press to pause"
            return "rotate to seek · \(press) · nudge for track and volume"

        case .recording:
            return "ring shows input level · rotate to set gain · press to stop"

        case .edit:
            return level.isTrimSettled
                ? "press to hear what you are keeping · back to save or discard"
                : "drag or rotate to move the handle · tap the other to switch"

        // Says what the press will do rather than how to press. This is the one screen where the
        // wrong answer cannot be taken back, so the caption names the outcome.
        case .confirmDelete:
            return "deleting cannot be undone · rotate to choose · press to confirm"

        case .confirmTrim:
            return "saving rewrites the recording · rotate to choose · press to confirm"
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
