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
        /// What the editor will do to the selection when `DONE` is pressed.
        ///
        /// **Armed, not applied.** The nudges used to commit and pop on the spot, which left the
        /// `Back` gate asking whether to save something already written — two mechanisms from two
        /// rounds, both live, contradicting each other. Up and down choose; the hub does it.
        var trimOperation: DialScreen.TrimOperation = .keep
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
        case .dragTrim(let handle, let fraction): dragTrim(handle, to: fraction)
        // The stick engaging is felt, not decided: nothing about where you are changes.
        case .nudgeEngaged: [.feedback(.detent)]
        }
    }

    /// The host's correction. Replaces the data wholesale and re-clamps every level's highlight,
    /// because a list can shrink under a screen you are not currently looking at.
    mutating func update(_ content: DialContent) {
        self.content = content
        for index in stack.indices {
            let rows = rowCount(atDepth: index)
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
        let rows = currentRowCount
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

    /// A handle dragged straight to a position, which also selects it.
    ///
    /// The selection moves first so the wheel picks up the handle the finger just released — coarse
    /// with the finger, fine with the dial, which is the pairing this screen is for. `DialTrimRange`
    /// still owns the rule that the handles cannot cross, so a drag past the other one lands
    /// against it rather than through it.
    private mutating func dragTrim(_ handle: DialScreen.Handle, to fraction: Double) -> [DialEffect] {
        guard case .edit = route, let editing = content.editing else { return [.feedback(.limit)] }

        if let index = route.modes.firstIndex(where: { $0.axis == (handle == .start ? .trimStart : .trimEnd) }) {
            stack[stack.count - 1].mode = index
        }

        var trim = currentTrim ?? DialTrimRange(start: 0, end: editing.duration, duration: editing.duration)
        let target = min(max(0, fraction), 1) * editing.duration
        let before = (trim.start, trim.end)

        switch handle {
        case .start: trim.setStart(to: target)
        case .end: trim.setEnd(to: target)
        }
        stack[stack.count - 1].trim = trim

        guard (trim.start, trim.end) != before else { return [] }
        return [.setTrim(start: trim.start, end: trim.end), .feedback(.detent)]
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
            return open(destination)

        case .recordings, .folder:
            // **Every row here is a file or a folder.** Import and New folder were rows once, then
            // pinned rows, and are now buttons in the bottom bar — so the list has no exceptions
            // left and the highlight indexes the items directly. `RecordingsRow` existed to hold
            // the offset that created; it is gone with it.
            guard let item = currentItems[safe: level.highlighted] else { return [.feedback(.limit)] }
            // **A folder opens; a file plays.** One press, two outcomes, decided by the row rather
            // than by a mode — which is what keeps the hub saying OPEN on both.
            guard !item.isFolder else { return open(.folder(itemID: item.id)) }
            return playItem(item, at: level.highlighted)

        case .nowPlaying:
            content.playback?.isPlaying.toggle()
            return [.togglePlayPause, .feedback(.commit)]

        // **Arriving is not starting.** For an hour this screen started a take the instant the card
        // was pressed, which is worse than the dead end it replaced: you were recording before you
        // had decided to. The screen says "press the hub to start" — this is that press, and the
        // same button stops once a take is running.
        case .recording:
            guard content.capture != nil else { return beginRecording() }
            // **Stopping lands on the library, not back where you came from.** Popping returned you
            // to whatever pushed the recorder — home, usually — which is the one place the thing you
            // just made is not. You stop a take to have it; the library is where it now is.
            pop()
            push(.recordings)
            return [.stopRecording, .feedback(.commit)]

        // **`DONE` is the only thing that writes.** The nudges choose what will happen; this makes
        // it happen and leaves. One button, one moment where a real recording changes.
        case .edit(let itemID):
            // **Refusing beats acting on an empty range.** The old fallback was
            // `DialTrimRange(start: 0, end: 0, duration: 0)`, so pressing the hub before the
            // material had loaded asked the host to keep nothing at all — and the host is about to
            // rewrite a real file.
            guard let trim = currentTrim else { return [.feedback(.limit)] }
            let operation = level.trimOperation

            // **Applying does not leave.** DONE used to pop, which meant the one screen that can
            // show you the result was gone at the instant there was a result to show — you pressed,
            // the editor vanished, and whether the cut landed where you wanted was something you
            // found out by opening the file again. Leaving is the back control's job.
            //
            // Clearing `trim` rather than keeping it is what makes a second press safe: the
            // recording underneath has just been rewritten, so the old start and end describe a
            // file that no longer exists. `currentTrim` falls back to the whole of
            // `content.editing`, so the next refresh — carrying the new duration — seeds the
            // handles across the new file. Disarming to `.keep` for the same reason: the delete
            // has happened, and leaving it armed points a second one at the wrong region.
            stack[stack.count - 1].trim = nil
            stack[stack.count - 1].trimOperation = .keep

            switch operation {
            case .keep:
                return [.commitTrim(itemID: itemID, start: trim.start, end: trim.end), .feedback(.commit)]
            case .remove:
                return [.commitCut(itemID: itemID, start: trim.start, end: trim.end), .feedback(.commit)]
            }

        case .confirmDelete(let itemID):
            let choices = DialRoute.DeleteChoice.allCases
            let choice = choices[min(level.highlighted, choices.count - 1)]
            pop()
            switch choice {
            case .cancel: return [.feedback(.commit)]
            case .delete: return [.item(.delete, itemID: itemID), .feedback(.commit)]
            }

        }
    }

    /// The recording under the highlight, if the highlight is on one at all.
    ///
    /// Row 0 is Import, so this is `nil` there — and the stick's four nudges all act on a recording,
    /// which is why every one of them guards on it.
    private var highlightedRecording: DialContent.Item? {
        currentItems[safe: level.highlighted]
    }

    /// The highlighted row when it is a file — which is what all four nudges and the editor need.
    ///
    /// **Folders refuse rather than act.** Every one of the four does something a folder cannot
    /// answer: there is nothing to trim, the share sheet takes a file URL, adding a folder to a
    /// folder is a move this slice does not do, and deleting one would take everything inside it
    /// with no way to say so on a two-row guard. Refusing is a limit pulse, which is the honest
    /// answer for a control that exists but does not apply here.
    private var highlightedFile: DialContent.Item? {
        guard let item = highlightedRecording, !item.isFolder else { return nil }
        return item
    }

    /// Only the recordings list has a second meaning for a second press.
    ///
    /// Elsewhere it is **silent, not a limit**: `.limit` means you pushed against something that
    /// exists and would not move, and a double-press on the library is not pushing against
    /// anything at all. Buzzing there would teach the gesture is available everywhere.
    private mutating func doublePress() -> [DialEffect] {
        switch route {
        case .recordings, .folder: break
        default: return []
        }
        guard let item = currentItems[safe: level.highlighted], !item.isFolder else { return [] }
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
            // **Back leaves, and asks nothing.** It used to open a Save-or-Discard gate, which made
            // sense while the hub did not write — but the nudges then started committing on the
            // spot, so the gate offered to save something already on disk. `DONE` writes and
            // nothing else does, which leaves `Back` with nothing to guard.
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

        // Available wherever files are listed, and it stays put — you are reloading the list you
        // are looking at, so leaving it would be the one thing you did not ask for.
        // The bottom bar's two library actions. They stay put: the picker's files and the new
        // folder both land in the list you are looking at, so going anywhere would be leaving the
        // only place that shows what just happened.
        case (.recordings, "import"), (.folder, "import"):
            return [.importFiles(intoItemID: currentFolderID), .feedback(.commit)]
        case (.recordings, "newFolder"), (.folder, "newFolder"):
            return [.createFolder(inItemID: currentFolderID), .feedback(.commit)]

        case (.recordings, "sync"), (.folder, "sync"):
            return [.reloadLibrary, .feedback(.commit)]

        case (.recordings, "edit"), (.folder, "edit"):
            return doublePress()
        // **The stick's four nudges, each acting on the highlighted recording.** They were rows on
        // a pushed menu, which cost a nudge, a turn and a press to do one thing.
        case (.recordings, "share"), (.folder, "share"):
            guard let item = highlightedFile else { return [.feedback(.limit)] }
            return [.item(.share, itemID: item.id), .feedback(.commit)]
        case (.recordings, "add"), (.folder, "add"):
            guard let item = highlightedFile else { return [.feedback(.limit)] }
            return [.item(.addToPlaylist, itemID: item.id), .feedback(.commit)]
        case (.recordings, "delete"), (.folder, "delete"):
            guard let item = highlightedFile else { return [.feedback(.limit)] }
            return open(.confirmDelete(itemID: item.id))

        // **Renaming is the editor's, not the stick's.** Four directions cannot hold five verbs, and
        // of the five this is the one that belongs where you are already changing the recording.
        // **These arm; they do not act.** Nothing reaches disk until the hub is pressed, so a nudge
        // is free to change your mind about.
        case (.edit, "trim"):
            stack[stack.count - 1].trimOperation = .keep
            return [.feedback(.commit)]

        case (.edit, "cut"):
            stack[stack.count - 1].trimOperation = .remove
            return [.feedback(.commit)]

        case (.edit(let itemID), "rename"):
            return [.renameItem(itemID: itemID), .feedback(.commit)]

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
        case (.edit(let itemID), "preview"):
            guard let trim = currentTrim else { return [.feedback(.limit)] }
            return [.previewTrim(itemID: itemID, start: trim.start, end: trim.end), .feedback(.commit)]

        case (.nowPlaying, "repeat"):
            return [.cycleRepeat, .feedback(.commit)]
        case (.nowPlaying, "shuffle"):
            return [.toggleShuffle, .feedback(.commit)]

        case (.nowPlaying, "volumeUp"):
            return setVolume(by: WheelRouter.volumePerNudge)
        case (.nowPlaying, "volumeDown"):
            return setVolume(by: -WheelRouter.volumePerNudge)

        case (.nowPlaying, "previous"):
            return stepQueue(by: -1)
        case (.nowPlaying, "next"):
            return stepQueue(by: 1)

        case (.recording, "marker"):
            return [.addMarker, .feedback(.commit)]
        case (.recording, "pause"):
            content.capture?.isPaused.toggle()
            return [.toggleRecordingPause, .feedback(.commit)]

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
        guard let item = currentItems[safe: level.highlighted], !item.isFolder
        else { return [.feedback(.limit)] }
        return openEditor(itemID: item.id)
    }

    /// Both of these silence playback first — see `DialEffect.pausePlayback` for why the microphone
    /// and the trim preview cannot share the session with a track.
    ///
    /// The navigator marks its own copy paused in the same breath. Without it the Now playing row
    /// keeps its play glyph until the host answers, and on the recording screen that is a picture
    /// of audio still running while the meter says otherwise.
    /// Start a take on a screen already showing the recorder.
    private mutating func beginRecording() -> [DialEffect] {
        pausePlaybackIfNeeded() + [.startRecording, .feedback(.commit)]
    }

    /// Open the recorder *and* start a take — the mode chooser's Record, where there is no recording
    /// screen to arrive at first.
    private mutating func startRecording() -> [DialEffect] {
        let effects = beginRecording()
        push(.recording)
        return effects
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
            // Files only: folders sit in the same list but never in the queue, so counting them
            // would give the browse wheel ends that do not exist.
            queueCount: currentItems.count(where: { !$0.isFolder })
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

    /// The items visible at a given depth: the root list, descended once per `.folder` level.
    ///
    /// **Depth rather than "current", because `update(_:)` re-clamps every level**, including the
    /// ones underneath the screen you are looking at. A list shrinking two levels down still has to
    /// leave a highlight that points at something.
    ///
    /// A folder whose id is no longer in the tree yields an empty list rather than falling back to
    /// its parent's. The folder has been deleted or moved under you; showing its neighbours instead
    /// would be showing a different place under the same heading.
    func items(atDepth depth: Int) -> [DialContent.Item] {
        var items = content.recordings
        for level in stack.prefix(depth + 1) {
            guard case .folder(let itemID) = level.route else { continue }
            guard let children = items.first(where: { $0.id == itemID })?.children else { return [] }
            items = children
        }
        return items
    }

    /// What is on screen now.
    var currentItems: [DialContent.Item] { items(atDepth: stack.count - 1) }

    /// The folder the actions act on: the one you are standing in, or `nil` at the library root.
    var currentFolderID: String? {
        if case .folder(let itemID) = route { return itemID }
        return nil
    }

    func rowCount(atDepth depth: Int) -> Int {
        let items = items(atDepth: depth)
        switch stack[depth].route {
        case .chooseMode: return 2
        case .library: return content.sections.count
        case .recordings, .folder: return items.count
        case .confirmDelete: return DialRoute.DeleteChoice.allCases.count
        case .nowPlaying, .recording, .edit: return 0
        }
    }

    /// The row count of the screen on top.
    var currentRowCount: Int { rowCount(atDepth: stack.count - 1) }
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
