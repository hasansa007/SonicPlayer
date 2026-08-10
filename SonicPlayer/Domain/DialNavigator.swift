import Foundation

/// The dial's whole navigation model: commands in, screens out (#6).
///
/// Rotating moves a highlight, pressing commits, and that is the entire vocabulary — so everything
/// that would be a button elsewhere has to be a *decision* here. This type is where those decisions
/// live, and it is deliberately the only place: a view that renders `screen` and forwards
/// `DialCommand`s cannot get the navigation wrong, because it never sees it.
///
/// **Three rules run through all of it.**
///
/// 1. **Wrap, because the ring is continuous and pretending otherwise cost more than it saved.**
///    This read "clamp, never wrap" until `Delete` got a confirmation dialog — the whole argument
///    for a wall was that a thumb overshooting the top of the actions list would land on the
///    destructive row. Guarded, that objection goes. A fast spin still cannot wrap several times
///    unnoticed: `detents` is reduced modulo the row count before it is applied.
/// 2. **A tick that changes nothing is a `.limit`; a tick that changes anything is a `.detent`.**
///    One law, applied to the highlight, the seek position, the volume, the gain and both trim
///    handles. Travel that is merely truncated by a bound still moved, so it still clicks; only the
///    tick after you have arrived is silent under the thumb and loud in the hand. Without this the
///    user is turning against a wall they cannot feel.
/// 3. **Touch and wheel are equals.** `.action("edit")` and `.doublePress` run the same function.
///    The contract requires it — a double-press is invisible and VoiceOver cannot perform one — and
///    the only way to be sure is that there is one implementation, not two that agree today.
///
/// Nothing here reads a clock, touches a file or knows what a view is. Time arrives as data in
/// `DialContent`, the same way it arrives as a parameter in `RotaryTracker`.
struct DialNavigator {

    /// One entry on the stack: where you are, and everything about *how* you are there that must
    /// survive going deeper and coming back.
    ///
    /// The highlight lives here rather than on the navigator because popping has to restore it.
    /// A list that forgets where you were is the classic loss, and storing it per level is what
    /// makes remembering free.
    struct Level: Equatable {
        var route: DialRoute
        var highlighted: Int = 0
        /// Index into `route.modes`, clamped by construction — a route with no modes leaves it 0.
        var mode: Int = 0
        /// The trim editor's selection. Only `.edit` has one, and popping is what discards it.
        var trim: DialTrimRange?
    }

    /// One detent of input gain. Fifty detents end to end, matching `WheelRouter.volumePerDetent` —
    /// separate from it because gain and volume are different quantities and tuning one on a device
    /// must not silently move the other.
    static let gainPerDetent: Double = 0.02

    private(set) var content: DialContent
    /// Never empty: the root is placed at construction and `pop` refuses to remove it.
    private(set) var stack: [Level]

    init(content: DialContent = DialContent(), root: DialRoute = .library) {
        self.content = content
        self.stack = [Level(route: root)]
    }

    var level: Level { stack[stack.count - 1] }
    var route: DialRoute { level.route }

    /// The axis a tick currently drives — the selected mode's, or the route's own when it has no
    /// modes to choose between.
    var axis: DialAxis {
        let modes = route.modes
        guard !modes.isEmpty else { return route.defaultAxis }
        return modes[min(level.mode, modes.count - 1)].axis
    }

    // MARK: - Input

    mutating func receive(_ command: DialCommand) -> [DialEffect] {
        switch command {
        case .tick(let detents): tick(detents)
        case .volumeTick(let detents):
            // The small wheel has one job, so it bypasses the axis entirely.
            setVolume(by: Double(detents) * WheelRouter.volumePerDetent)
        case .press: press()
        case .doublePress: doublePress()
        case .hold: hold()
        case .action(let id): perform(id)
        }
    }

    /// The host's correction. Replaces the data wholesale and re-clamps every level's highlight,
    /// because a list can shrink under a screen you are not currently looking at.
    mutating func update(_ content: DialContent) {
        self.content = content
        for index in stack.indices {
            let rows = rowCount(stack[index].route)
            stack[index].highlighted = min(max(0, stack[index].highlighted), max(0, rows - 1))
        }
    }

    // MARK: - Rotation

    private mutating func tick(_ detents: Int) -> [DialEffect] {
        guard detents != 0 else { return [] }

        switch axis {
        case .highlight: return moveHighlight(by: detents)
        case .seek: return seek(by: Double(detents) * WheelRouter.secondsPerDetent)
        case .volume: return setVolume(by: Double(detents) * WheelRouter.volumePerDetent)
        case .queue: return stepQueue(by: detents)
        case .gain: return setGain(by: Double(detents) * Self.gainPerDetent)
        case .trimStart, .trimEnd: return nudgeTrim(by: Double(detents) * WheelRouter.secondsPerDetent)
        }
    }

    /// **The list wraps.** Past the last row is the first, and backwards past the first is the last.
    ///
    /// This was a wall in both directions, and the recorded reason was the actions menu: wrapping
    /// puts `Delete` — its last row — one detent from the top, so overshooting upward lands the
    /// thumb on the destructive one. That objection stands only while `Delete` is unguarded, and it
    /// is not: the confirmation dialog and this change belong to the same slice and must not be
    /// separated.
    ///
    /// A wheel with no ends also removes the thing a wheel is worst at — telling you *which* end
    /// you are against, when the only signal is a pulse that means several other things too.
    ///
    /// One row still cannot move: `(0 + n) % 1` is 0, so a single-row list would report a detent
    /// for a turn that changed nothing. That is the one honest limit left.
    private mutating func moveHighlight(by detents: Int) -> [DialEffect] {
        let rows = rowCount(route)
        guard rows > 1 else { return [.feedback(.limit)] }

        // `%` keeps the sign of its left operand in Swift, so a backward turn off row 0 lands
        // negative. Adding `rows` before the second modulo is what brings it round to the end
        // rather than out of bounds — and `detents` itself can exceed `rows` on a fast flick, which
        // is why it is reduced first.
        let offset = ((detents % rows) + rows) % rows
        let target = (level.highlighted + offset) % rows
        guard target != level.highlighted else { return [.feedback(.limit)] }

        stack[stack.count - 1].highlighted = target
        return [.feedback(.detent)]
    }

    private mutating func seek(by delta: TimeInterval) -> [DialEffect] {
        guard var playback = content.playback else { return [.feedback(.limit)] }

        let target = ScrubClamp.position(playback.position + delta, duration: playback.duration)
        guard target != playback.position else { return [.feedback(.limit)] }

        playback.position = target
        content.playback = playback
        return [.seek(to: target), .feedback(.detent)]
    }

    private mutating func setVolume(by delta: Double) -> [DialEffect] {
        guard var playback = content.playback else { return [.feedback(.limit)] }

        let target = min(max(0, playback.volume + delta), 1)
        guard target != playback.volume else { return [.feedback(.limit)] }

        playback.volume = target
        content.playback = playback
        return [.setVolume(target), .feedback(.detent)]
    }

    /// `Browse` moves the queue itself rather than a cursor over it.
    ///
    /// A cursor would be the safer design on a list screen, but Now Playing has no list to draw it
    /// in — the only place it could show is the ring's `thumb`, which is a single lit tick and says
    /// nothing about *which* track. Stepping the queue changes the title on screen, so the feedback
    /// is where the user is already looking.
    private mutating func stepQueue(by detents: Int) -> [DialEffect] {
        guard var playback = content.playback, playback.queueCount > 0 else { return [.feedback(.limit)] }

        let target = min(max(0, playback.queueIndex + detents), playback.queueCount - 1)
        guard target != playback.queueIndex else { return [.feedback(.limit)] }

        playback.queueIndex = target
        content.playback = playback
        return [.selectTrack(index: target), .feedback(.detent)]
    }

    /// **Hardware with no input gain is a wall, not a broken wheel.** `isGainSettable` is false on
    /// every built-in iPhone mic, so this is the ordinary case rather than the exotic one — and
    /// without the check the navigator would move its own copy of the number, report a detent, and
    /// emit a `.setGain` the recorder silently drops. That is the control that appears to work and
    /// does not, which is the thing #6 set out to avoid.
    private mutating func setGain(by delta: Double) -> [DialEffect] {
        guard var capture = content.capture, capture.isGainSettable else { return [.feedback(.limit)] }

        let target = min(max(0, capture.gain + delta), 1)
        guard target != capture.gain else { return [.feedback(.limit)] }

        capture.gain = target
        content.capture = capture
        return [.setGain(target), .feedback(.detent)]
    }

    private mutating func nudgeTrim(by delta: TimeInterval) -> [DialEffect] {
        guard var trim = currentTrim else { return [.feedback(.limit)] }

        let isStart = axis == .trimStart
        let before = isStart ? trim.start : trim.end
        let moved = isStart ? trim.moveStart(by: delta) : trim.moveEnd(by: delta)
        guard moved else { return [.feedback(.limit)] }

        let landed = isStart ? trim.start : trim.end
        let snapped = snap(&trim, isStart: isStart, from: before, landing: landed)

        stack[stack.count - 1].trim = trim
        return [.setTrim(start: trim.start, end: trim.end), .feedback(snapped ? .snap : .detent)]
    }

    /// Pulls a handle onto a nearby marker, and reports whether it took.
    ///
    /// The correction is applied **through `moveStart`/`moveEnd` rather than by assignment**, so a
    /// marker sitting inside the minimum-length gap cannot do what no other input can: cross the
    /// handles. That the range refuses such a marker is why the return value checks where the
    /// handle actually ended up rather than trusting the move.
    private func snap(
        _ trim: inout DialTrimRange, isStart: Bool, from before: TimeInterval, landing: TimeInterval
    ) -> Bool {
        guard let target = MarkerSnap.target(
            for: landing,
            from: before,
            markers: content.editing?.markers ?? [],
            // One detent, per §5 — the wheel's half of "tolerance scales with the input". The
            // finger's half is wider and arrives with the waveform that can measure it in points.
            tolerance: WheelRouter.secondsPerDetent
        ) else { return false }

        if isStart {
            trim.setStart(to: target)
            return trim.start == target
        } else {
            trim.setEnd(to: target)
            return trim.end == target
        }
    }

    /// The editor's selection — the one this level holds, or a whole-file range derived from the
    /// material when it has none yet.
    ///
    /// **The fallback is the normal path, not a defensive one.** `push` can only build a range when
    /// `content.editing` is already loaded, and it never is: the host learns *which* item to load
    /// from the route the push creates, so the material always arrives one `update(_:)` later. With
    /// only `level.trim` to read, the range therefore stayed nil for the life of the screen and
    /// every tick of the wheel was a limit. `DialNavigatorScreen` has always fallen back this way
    /// for rendering, which is what made the bug so quiet — the picture moved and the value did not.
    private var currentTrim: DialTrimRange? {
        if let trim = level.trim { return trim }
        guard let editing = content.editing else { return nil }
        return DialTrimRange(start: 0, end: editing.duration, duration: editing.duration)
    }

    // MARK: - Press

    /// The hub, which means something different on every screen — that is the point of it. There is
    /// one button, so what it does has to come from where you are.
    private mutating func press() -> [DialEffect] {
        switch route {
        case .chooseMode:
            return level.highlighted == 0 ? open(.library) : startRecording()

        case .library:
            guard let section = content.sections[safe: level.highlighted] else {
                return [.feedback(.limit)]
            }
            // **Every section is a place now.** There used to be a second kind — a section carrying
            // a `DialEffect` that did something and stayed put — and Import was its only instance.
            // With Import gone from the dial the mechanism had no setter left, so it went with it
            // rather than sitting here waiting for a second first user.
            guard let destination = section.destination else { return [.feedback(.limit)] }
            // **Opening the recorder *is* starting a take.** This used to `open(.recording)` like
            // any other destination, which pushed the screen and asked the host for nothing — so
            // the card landed you on "Not recording · press the hub to start", and pressing the hub
            // there stops and pops. A dead end, and it survived because the only tested way in was
            // the `Record` chip on the empty library, which called this properly and has since gone.
            if destination == .recording { return startRecording() }
            return open(destination)

        case .recordings:
            switch RecordingsRow.at(level.highlighted, recordings: content.recordings.count) {
            case .importFiles:
                // Stays put. The picker belongs to the host and the files land in this very list,
                // so navigating away would be a round trip back to where you already are.
                return [.importFiles, .feedback(.commit)]
            case .recording(let index):
                guard let item = content.recordings[safe: index] else { return [.feedback(.limit)] }
                return playItem(item, at: index)
            case nil:
                return [.feedback(.limit)]
            }

        case .nowPlaying:
            content.playback?.isPlaying.toggle()
            return [.togglePlayPause, .feedback(.commit)]

        case .recording:
            pop()
            return [.stopRecording, .feedback(.commit)]

        case .edit(let itemID):
            // **Refusing beats committing an empty range.** The old fallback was
            // `DialTrimRange(start: 0, end: 0, duration: 0)`, so pressing the hub before the
            // material had loaded asked the host to keep nothing at all — and the host is about to
            // rewrite a real file. Nothing loaded is a screen that says so, and a hub that says the
            // same rather than destroying a lecture.
            guard let trim = currentTrim else { return [.feedback(.limit)] }
            pop()
            return [.commitTrim(itemID: itemID, start: trim.start, end: trim.end), .feedback(.commit)]

        case .confirmDelete(let itemID):
            let choices = DialRoute.DeleteChoice.allCases
            let choice = choices[min(level.highlighted, choices.count - 1)]
            pop()
            switch choice {
            case .cancel: return [.feedback(.commit)]
            case .delete: return [.item(.delete, itemID: itemID), .feedback(.commit)]
            }

        case .actions(let itemID):
            let action = DialItemAction.allCases[min(level.highlighted, DialItemAction.allCases.count - 1)]
            pop()
            // **Edit is a place, not a thing done to a file.** Emitting `.item(.edit, …)` like the
            // others would hand it to `onItemAction`, which is deliberately unwired — the row would
            // have looked identical and done nothing at all.
            guard action != .edit else { return openEditor(itemID: itemID) }
            // **Delete goes through its own screen.** The menu has already popped by the time this
            // runs, so the guard rises over the library — where the file is about to vanish from.
            guard action != .delete else { return open(.confirmDelete(itemID: itemID)) }
            return [.item(action, itemID: itemID), .feedback(.commit)]
        }
    }

    /// Only the recordings list has a second meaning for a second press.
    ///
    /// Elsewhere it is **silent, not a limit**: `.limit` means you pushed against something that
    /// exists and would not move, and a double-press on the library is not pushing against
    /// anything at all. Buzzing there would teach the gesture is available everywhere.
    private mutating func doublePress() -> [DialEffect] {
        guard case .recordings = route,
              case .recording(let index)? = RecordingsRow.at(level.highlighted, recordings: content.recordings.count),
              content.recordings.indices.contains(index) else {
            return []
        }
        return openEditor()
    }

    /// Jump to Now Playing from anywhere.
    ///
    /// Nothing playing is a limit — there is a destination, it is simply empty. Already being there
    /// is a limit for the same reason the top of a list is: the command was understood and changed
    /// nothing.
    private mutating func hold() -> [DialEffect] {
        guard content.playback != nil, route != .nowPlaying else { return [.feedback(.limit)] }
        return open(.nowPlaying)
    }

    // MARK: - Chips

    /// A chip in the action row. `back` is accepted on **every** screen, including the ones whose
    /// design shows no Back chip — Now Playing's action row is three modes and nothing else, and
    /// the breadcrumb above it is itself a way back. What that costs is one universal id; what it
    /// buys is that no screen can become a trap.
    private mutating func perform(_ id: String) -> [DialEffect] {
        if id == "back" {
            guard stack.count > 1 else { return [.feedback(.limit)] }
            pop()
            return [.feedback(.commit)]
        }

        // Selecting a mode needs no per-screen code, which is what keeps a new mode from being a
        // new screen.
        if let index = route.modes.firstIndex(where: { $0.id == id }) {
            stack[stack.count - 1].mode = index
            return [.feedback(.commit)]
        }

        switch (route, id) {
        case (.library, "nowPlaying"):
            return hold()

        case (.recordings, "edit"):
            return doublePress()
        case (.recordings, "more"):
            guard case .recording(let index)? = RecordingsRow.at(level.highlighted, recordings: content.recordings.count),
                  let item = content.recordings[safe: index] else { return [.feedback(.limit)] }
            return open(.actions(itemID: item.id))

        // The tri-state's two ends. Reusing `.action` rather than inventing commands: previous and
        // next were already sayable, and a spring-return switch is a new *affordance* for them, not
        // a new thing to say.
        // The chrome's status is tappable, and this is what it sends. `hold` does the same thing
        // from anywhere and is invisible; this is the affordance that says the destination exists.
        case (_, "nowPlaying"):
            return hold()

        case (_, "settings"):
            return [.openSettings, .feedback(.commit)]

        // The stick's vertical axis. These had no handler at all — the nudge fired, the navigator
        // shrugged, and nothing moved. A command with no case is silent, which is why the
        // command/handler pair wants to be added in one breath.
        case (.nowPlaying, "volumeUp"):
            return setVolume(by: WheelRouter.volumePerDetent)
        case (.nowPlaying, "volumeDown"):
            return setVolume(by: -WheelRouter.volumePerDetent)

        case (.nowPlaying, "previous"):
            return stepQueue(by: -1)
        case (.nowPlaying, "next"):
            return stepQueue(by: 1)

        case (.recording, "marker"):
            return [.addMarker, .feedback(.commit)]
        case (.recording, "pause"):
            content.capture?.isPaused.toggle()
            return [.toggleRecordingPause, .feedback(.commit)]

        case (.edit(let itemID), "preview"):
            guard let trim = currentTrim else { return [.feedback(.limit)] }
            return [
                .previewTrim(itemID: itemID, start: trim.start, end: trim.end),
                .feedback(.commit)
            ]

        default:
            return []
        }
    }

    // MARK: - Transitions

    private mutating func open(_ route: DialRoute) -> [DialEffect] {
        push(route)
        return [.feedback(.commit)]
    }

    private mutating func openEditor() -> [DialEffect] {
        guard case .recording(let index)? = RecordingsRow.at(level.highlighted, recordings: content.recordings.count),
              let item = content.recordings[safe: index] else { return [.feedback(.limit)] }
        return openEditor(itemID: item.id)
    }

    /// Both of these silence playback first — see `DialEffect.pausePlayback` for why the microphone
    /// and the trim preview cannot share the session with a track.
    ///
    /// The navigator marks its own copy paused in the same breath. Without it the Now playing row
    /// keeps its play glyph until the host answers, and on the recording screen that is a picture
    /// of audio still running while the meter says otherwise.
    private mutating func startRecording() -> [DialEffect] {
        let silence = pausePlaybackIfNeeded()
        push(.recording)
        return silence + [.startRecording, .feedback(.commit)]
    }

    private mutating func openEditor(itemID: String) -> [DialEffect] {
        let silence = pausePlaybackIfNeeded()
        return silence + open(.edit(itemID: itemID))
    }

    private mutating func pausePlaybackIfNeeded() -> [DialEffect] {
        guard content.playback?.isPlaying == true else { return [] }
        content.playback?.isPlaying = false
        return [.pausePlayback]
    }

    /// Fills in the playback state optimistically so the pushed Now Playing screen is right on the
    /// frame it appears, rather than blank until the host reports back.
    private mutating func playItem(_ item: DialContent.Item, at index: Int) -> [DialEffect] {
        content.playback = DialContent.Playback(
            title: item.title,
            subtitle: item.subtitle,
            position: 0,
            duration: item.duration,
            isPlaying: true,
            volume: content.playback?.volume ?? 1,
            queueIndex: index,
            queueCount: content.recordings.count
        )
        push(.nowPlaying)
        return [.play(itemID: item.id), .feedback(.commit)]
    }

    private mutating func push(_ route: DialRoute) {
        var pushed = Level(route: route)
        if case .edit = route, let editing = content.editing {
            pushed.trim = DialTrimRange(start: 0, end: editing.duration, duration: editing.duration)
        }
        stack.append(pushed)
    }

    private mutating func pop() {
        guard stack.count > 1 else { return }
        stack.removeLast()
    }

    // MARK: - Rows

    func rowCount(_ route: DialRoute) -> Int {
        switch route {
        case .chooseMode: 2
        case .library: content.sections.count
        case .recordings: RecordingsRow.rowCount(recordings: content.recordings.count)
        case .actions: DialItemAction.allCases.count
        case .confirmDelete: DialRoute.DeleteChoice.allCases.count
        case .nowPlaying, .recording, .edit: 0
        }
    }
}

/// Bounds-checked subscript. The navigator clamps every index it owns, but the data behind one can
/// be replaced by `update(_:)` between a turn and a press.
///
/// Deliberately file-private rather than a module-wide convenience: `subscript(safe:)` is a name
/// several files could plausibly want, and two of them declaring it is a build failure for both.
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
