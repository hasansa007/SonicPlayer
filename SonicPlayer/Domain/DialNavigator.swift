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
        /// **The order this list is in.** Per level, not per navigator: a folder of lectures wants
        /// A–Z and the library above it wants newest-first, and one setting for both means every
        /// folder you open inherits an order chosen for a different list. Reset by construction, so
        /// a folder opens in the order its contents were handed over.
        var sort: DialSort = .newest
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

    /// **Which job you are doing.** Set by the fork at the root and unchanged until you go back to
    /// it — see `DialActivity` for why this is a mode rather than two screens.
    private(set) var mode: DialActivity = .listen


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
        for index in stack.indices { clampHighlight(atDepth: index) }
    }

    /// Pulls a level's highlight back into the range that exists — which starts at the leading
    /// stop, not at zero, on the screens that have one.
    ///
    /// **A list with no rows goes to that stop rather than being clamped.** It is the case where it
    /// matters most and the one where clamping gets it exactly wrong: with no rows, index 0 is not
    /// row 0, it is *Back* — so an empty folder would open with the highlight on the way out
    /// instead of on the one thing there is to do in it. Run from `push` as well as `update`, so a
    /// level is right on the frame it appears rather than after the host's next refresh.
    private mutating func clampHighlight(atDepth depth: Int) {
        let first = firstIndex(atDepth: depth)
        let rows = rowCount(atDepth: depth)
        guard rows > 0 else {
            stack[depth].highlighted = first
            return
        }

        let current = stack[depth].highlighted
        guard current < first || current > lastIndex(atDepth: depth) else { return }

        // **Out of range comes back to a row, never onto a chrome stop.** A list shrinking under
        // you should leave the highlight on the nearest *file* — landing it on Back would answer a
        // list that got shorter by offering to leave, which is not what you were doing. The stops
        // are places you turn to on purpose, not places you get pushed.
        stack[depth].highlighted = current < first ? first : rows - 1
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
    ///
    /// **The chrome stops are on the ring too.** The leading one sits at `pinnedIndex`, before the
    /// first row, and the trailing one just past the last — so the ring can be two longer than the
    /// list, and turning off either end of the rows lands on a control rather than wrapping
    /// straight round. Everything below counts from `first` instead of from zero for that reason,
    /// and that is the whole of the arithmetic it costs.
    private mutating func moveHighlight(by detents: Int) -> [DialEffect] {
        let first = firstIndex
        let rows = lastIndex - first + 1
        guard rows > 1 else { return [.feedback(.limit)] }

        // `%` keeps the sign of its left operand in Swift, so a backward turn off the first stop
        // lands negative. Adding `rows` before the second modulo is what brings it round to the end
        // rather than out of bounds — and `detents` itself can exceed `rows` on a fast flick, which
        // is why it is reduced first.
        let offset = ((detents % rows) + rows) % rows
        let target = first + ((level.highlighted - first + offset) % rows)
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
    /// **Wraps when Repeat All is on, clamps when it is not** — because that is what Repeat All
    /// means, and the toggle has to change something a thumb can find.
    ///
    /// This clamped unconditionally and never read `repeatMode` at all, so Next on the last track
    /// was a limit pulse whatever the toggle said. `PlayerViewModel.nextTrack` had the wrapping
    /// rule all along; the dial had its own copy of the arithmetic and only half the rule.
    ///
    /// Repeat One does **not** wrap here. It means the current track repeats when it *ends*, which
    /// is a different question from what Next does — a Next that refused to advance would be a
    /// control that stops working while a mode is on.
    private mutating func stepQueue(by detents: Int) -> [DialEffect] {
        guard var playback = content.playback, playback.queueCount > 0 else { return [.feedback(.limit)] }

        let count = playback.queueCount
        let target: Int
        if playback.repeatMode == .all {
            target = ((playback.queueIndex + detents) % count + count) % count
        } else {
            target = min(max(0, playback.queueIndex + detents), count - 1)
        }
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
        // **The two chrome stops answer first, and answer by calling the same function the tap
        // calls.** Not an equivalent one — `perform` with the id the control was drawn from, so
        // that touch and wheel cannot drift apart. Rule 3 in the header is only true while there is
        // one implementation, and for a while there were controls with *no* wheel implementation
        // at all, which is the same failure taken to its limit.
        if let leading = leadingActionID, level.highlighted == Self.pinnedIndex {
            return perform(leading)
        }
        if let chip = highlightedChipID {
            return perform(chip)
        }

        switch route {
        // **Home is the fork.** It has always been two prominent cards; what changed is what they
        // mean. They used to be *places* — Library and Record — which put browsing and capturing on
        // the same footing as each other and left editing homeless. Now they are the two jobs, and
        // both open the same library with a different set of verbs over it.
        //
        // A separate `chooseMode` screen was written for this and never reached, because a second
        // two-card screen in front of a two-card screen is the same screen twice.
        case .library:
            guard let chosen = DialActivity.at(level.highlighted) else { return [.feedback(.limit)] }
            mode = chosen
            // Entering Record lets go of whatever was loaded. The editor rewrites files on disk, and
            // a player still holding one holds a stale duration and position — see `DialActivity`.
            let release: [DialEffect] = chosen == .record
                ? pausePlaybackIfNeeded() + [.releasePlayer]
                : []
            return release + open(.recordings)

        case .settings:
            guard let setting = DialSetting.allCases[safe: level.highlighted] else {
                return [.feedback(.limit)]
            }
            // Cycling rows stay put: the value is on the row under the highlight, so leaving would
            // hide the thing that just changed.
            return [.setting(setting), .feedback(setting.cycles ? .detent : .commit)]

        case .recordings, .folder:
            // **Every row is a file or a folder.** Import and New folder were rows once, and the
            // highlight had to skip them; the stops live outside the list instead, so the items are
            // still indexed directly. `RecordingsRow` held that old offset and is gone with it.
            guard let item = currentItems[safe: level.highlighted] else { return [.feedback(.limit)] }
            // A folder opens in both modes: it is the same shelf whichever job you are doing.
            guard !item.isFolder else { return open(.folder(itemID: item.id)) }
            // A file plays or opens for editing, and that is the whole of what the mode decides.
            return mode.opensEditor
                ? openEditor(itemID: item.id)
                : playItem(item, at: level.highlighted)

        case .nowPlaying:
            content.playback?.isPlaying.toggle()
            return [.togglePlayPause, .feedback(.commit)]

        // **Arriving is not starting.** For an hour this screen started a take the instant the card
        // was pressed, which is worse than the dead end it replaced: you were recording before you
        // had decided to. The screen says "press the hub to start" — this is that press, and the
        // same button stops once a take is running.
        case .recording:
            guard content.capture != nil else { return beginRecording() }
            // **Stopping goes nowhere.** It used to pop to the library, on the reasoning that you
            // stop a take in order to have it and the library is where it now is — which is true
            // and is still the wrong moment to say it. The instant a take ends is the instant you
            // decide whether to keep it, and being thrown onto a list is what makes trimming or
            // deleting it a navigation problem instead of the next press.
            //
            // What the screen becomes is the host's business: the save flow it raises is where the
            // take is named, kept or discarded. This is only the promise that the dial will not
            // move out from under it.
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

        case .move(let itemID):
            let destinations = MoveDestinations.all(in: content.recordings, excluding: itemID)
            guard let destination = destinations[safe: level.highlighted] else {
                return [.feedback(.limit)]
            }
            pop()
            return [.moveItem(itemID: itemID, toFolderID: destination.id), .feedback(.commit)]

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
        // **Nothing here answers a second press.** It used to open the editor on the library, which
        // is what Record mode's press does now — so a double press would be a second, slower way to
        // do the same thing, and it made every single press wait to find out it was not coming.
        return []
    }


    /// **Open the recorder from outside the dial** — the Home-screen quick action.
    ///
    /// It arrives from `AppDelegate`, where there is no view and no place you were, so this resets
    /// rather than pushes: a quick action means "start here", and stacking the recorder on top of
    /// wherever the app happened to be left would put a Back on it that leads somewhere the user
    /// never chose.
    ///
    /// It **opens** the recorder and does not start a take, which is the rule the hub already
    /// holds — arriving is not starting. The old sheet behaved the same way; it simply had a
    /// different screen to say it on.
    ///
    /// The mode goes to Record and the fork's highlight with it, so going back lands on a home that
    /// agrees with where you just were rather than on Listen.
    mutating func openRecorder() -> [DialEffect] {
        let release = pausePlaybackIfNeeded() + [.releasePlayer]
        mode = .record
        stack = [Level(route: .library, highlighted: 1)]
        push(.recordings)
        push(.recording)
        return release + [.feedback(.commit)]
    }

    /// **Open the editor on a take that has just been written.**
    ///
    /// Called by the host rather than reached by a press, because the id is a URL and the URL does
    /// not exist until the recorder has closed the file — there is nothing for the hub to name at
    /// the moment it is pressed.
    ///
    /// Guarded on still being at the recorder: a take can finish while you have already walked
    /// away, and a screen arriving under a thumb that went somewhere else is worse than a take you
    /// have to open yourself. **Pushed rather than replacing**, so Back from the editor is the
    /// recorder again — ready for the next take, which is where you were.
    mutating func openEditorForFinishedTake(itemID: String) -> [DialEffect] {
        guard case .recording = route, content.capture == nil else { return [] }
        return openEditor(itemID: itemID)
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
            guard mode == .listen else { return [.feedback(.limit)] }
            return [.importFiles(intoItemID: currentFolderID), .feedback(.commit)]

        // **Cycles and stays put**, like the settings rows: the thing that just changed is the list
        // you are looking at, so going anywhere would hide it. The highlight is re-clamped because
        // reordering can move the row it was on past the end — and it deliberately does *not*
        // follow that row: you sorted to read the list from the top, not to keep your place in it.
        case (.recordings, "sort"), (.folder, "sort"):
            guard currentItems.count > 1 else { return [.feedback(.limit)] }
            stack[stack.count - 1].sort = level.sort.next
            clampHighlight(atDepth: stack.count - 1)
            return [.feedback(.commit)]
        // **No `edit` nudge any more.** In Record mode the press opens the editor, so a nudge for
        // it would be a second way to do the thing the hub already does.
        case (.recordings, "edit"), (.folder, "edit"):
            return [.feedback(.limit)]
        // **The stick's four nudges, each acting on the highlighted recording.** They were rows on
        // a pushed menu, which cost a nudge, a turn and a press to do one thing.
        // **Rename and Delete take folders too.** They were guarded on `highlightedFile`, which is
        // nil for a folder — so a library could grow folders it could never rename or remove. The
        // other two verbs stay file-only for reasons a folder genuinely cannot answer: there is no
        // single URL to share, and adding a folder to a playlist is a move this slice does not do.
        case (.recordings, "rename"), (.folder, "rename"):
            guard mode == .record, let item = highlightedRecording else { return [.feedback(.limit)] }
            return [.renameItem(itemID: item.id), .feedback(.commit)]

        // Stays put: the folder lands in the list you are looking at, so going anywhere would be
        // leaving the only place that shows what just happened.
        case (.recordings, "newFolder"), (.folder, "newFolder"):
            return [.createFolder(inItemID: currentFolderID), .feedback(.commit)]

        // Opens the recorder; the hub there starts the take. Arriving is not starting.
        case (.recordings, "record"), (.folder, "record"):
            guard mode == .record else { return [.feedback(.limit)] }
            return open(.recording)

        // **Filing is a screen, not a sheet.** The left nudge was the one direction Record mode
        // never used, and moving a recording is the verb that was missing from it — a library that
        // grows folders needs a way to put things in them.
        case (.recordings, "move"), (.folder, "move"):
            guard mode == .record, let item = highlightedFile else { return [.feedback(.limit)] }
            return open(.move(itemID: item.id))

        case (.recordings, "share"), (.folder, "share"):
            guard let item = highlightedFile else { return [.feedback(.limit)] }
            return [.item(.share, itemID: item.id), .feedback(.commit)]
        case (.recordings, "add"), (.folder, "add"):
            guard mode == .listen, let item = highlightedFile else { return [.feedback(.limit)] }
            return [.item(.addToPlaylist, itemID: item.id), .feedback(.commit)]
        // **Destruction is Record's alone.** Listen is a mode where nothing can be lost, which is
        // the point of having modes at all — and the price is that an import can only be deleted
        // from the Files sheet.
        case (.recordings, "delete"), (.folder, "delete"):
            guard mode == .record, let item = highlightedRecording else { return [.feedback(.limit)] }
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
            return open(.settings)

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
        // **Counted among the files, not among the rows.** `index` is a row index and folders sit
        // in the same list, so at the root — folders first — every file's queue position was off by
        // the number of folders above it.
        let queueIndex = currentItems.prefix(index).count { !$0.isFolder }
        content.playback = DialContent.Playback(
            title: item.title,
            subtitle: item.subtitle,
            position: 0,
            duration: item.duration,
            isPlaying: true,
            volume: content.playback?.volume ?? 1,
            queueIndex: queueIndex,
            // Files only: folders sit in the same list but never in the queue, so counting them
            // would give the browse wheel ends that do not exist.
            queueCount: currentItems.count(where: { !$0.isFolder })
        )
        push(.nowPlaying)
        // Files only, in the order on screen — the same list `queueCount` counts, so the index the
        // navigator holds and the index the host loads are the same number by construction.
        return [
            .play(itemID: item.id, queue: currentItems.filter { !$0.isFolder }.map(\.id)),
            .feedback(.commit)
        ]
    }

    private mutating func push(_ route: DialRoute) {
        var pushed = Level(route: route)
        if case .edit = route, let editing = content.editing {
            pushed.trim = DialTrimRange(start: 0, end: editing.duration, duration: editing.duration)
        }
        stack.append(pushed)
        clampHighlight(atDepth: stack.count - 1)
    }

    /// Returning to home clears the mode. Landing back on the fork still in `.record` would make
    /// the next Listen press behave as an edit until something happened to reset it.
    private mutating func popToRootResetsMode() {
        if stack.count == 1, case .library = route { mode = .listen }
    }

    private mutating func pop() {
        guard stack.count > 1 else { return }
        stack.removeLast()
        popToRootResetsMode()
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
    /// **Sorted here, which is the only place it can be.** The projection draws the rows and `press`
    /// indexes them, and if those two saw different orders the hub would open whatever used to be
    /// under the highlight. One function answers "what is at this depth, in what order", and both
    /// halves ask it.
    ///
    /// The descent is against the *unsorted* children — a folder is found by id, and an id does not
    /// move when a list is reordered.
    func items(atDepth depth: Int) -> [DialContent.Item] {
        var items = content.recordings
        for level in stack.prefix(depth + 1) {
            guard case .folder(let itemID) = level.route else { continue }
            guard let children = items.first(where: { $0.id == itemID })?.children else { return [] }
            items = children
        }
        return stack[depth].sort.applied(to: items)
    }

    /// What is on screen now.
    var currentItems: [DialContent.Item] { items(atDepth: stack.count - 1) }

    /// The folder the actions act on: the one you are standing in, or `nil` at the library root.
    var currentFolderID: String? {
        if case .folder(let itemID) = route { return itemID }
        return nil
    }

    // MARK: - The chrome stops

    /// **Everything on a list screen is a stop on the ring, not only the rows.**
    ///
    /// The dial is the one control this app is built around, and for a while three things on the
    /// card could only be tapped: the verb pinned above the list, the gear in home's corner, and
    /// Back in the bottom bar. Each was reachable by finger and invisible to the wheel — which is
    /// the same defect three times, and the kind you only notice holding the phone.
    ///
    /// So the ring runs in the order the card is drawn:
    ///
    ///     -1            the leading stop   — the mode's verb, or Settings on home
    ///     0 ..< rows    the rows
    ///     rows          the trailing stop  — Back
    ///
    /// **Negative and past-the-end rather than rows 0 and n.** Import was row 0 once, and every
    /// place that read the highlight had to subtract one to find the file — the offset
    /// `RecordingsRow` existed to hold, which took 28 tests down with it when it was removed.
    /// Outside the list the items keep indexing from zero, `currentItems[safe:]` returns nil for
    /// both stops without being asked to, and the only code that knows they exist is the wrap
    /// arithmetic, the clamp and two lines of `press`.
    static let pinnedIndex = -1

    /// The verb pinned to the top of the card — **the mode's**, because each mode has exactly one
    /// way to bring material in. `nil` on every screen that pins nothing.
    ///
    /// It lives here rather than in the projection so that the thing drawn and the thing pressed
    /// cannot drift apart: the view reads this to label the row, and `press` reads it to run it.
    func pinnedActionID(atDepth depth: Int) -> String? {
        switch stack[depth].route {
        case .recordings, .folder: return mode == .record ? "record" : "import"
        default: return nil
        }
    }

    var pinnedActionID: String? { pinnedActionID(atDepth: stack.count - 1) }

    /// What the stop before the first row does: **the verb pinned above the list**, and only that.
    /// Nothing else is drawn up there.
    func leadingActionID(atDepth depth: Int) -> String? { pinnedActionID(atDepth: depth) }

    var leadingActionID: String? { leadingActionID(atDepth: stack.count - 1) }

    /// **The chip row, in the order it is drawn — and the navigator owns it.**
    ///
    /// It lived in the projection, which built the chips and named them; the ring then knew about
    /// exactly two of them, Back and Settings, because those were the two somebody had thought to
    /// wire. Sort arrived and was tap-only, and would have stayed tap-only until it was noticed.
    /// A list the ring reads and the projection draws cannot grow a control the wheel misses.
    func chipIDs(atDepth depth: Int) -> [String] {
        var ids: [String] = []
        // **The guard screen is deliberately two rows.** `Cancel` is already the way back, so a
        // Back chip beside it would be a second one, differently worded.
        if depth > 0, case .confirmDelete = stack[depth].route {} else if depth > 0 {
            ids.append("back")
        }

        switch stack[depth].route {
        case .library: ids.append("settings")
        // **New folder is back, and on the wheel this time.** It was a bar button, removed with the
        // bar — which left no way to make a folder from the dial at all, so folders could be
        // browsed and filed into and never created. The chip row is reachable by the wheel now,
        // which is what makes this the right home rather than the last one that was tried.
        case .recordings, .folder: ids += ["newFolder", "sort"]
        case .nowPlaying where content.playback != nil: ids += ["repeat", "shuffle"]
        default: break
        }
        return ids
    }

    var chipIDs: [String] { chipIDs(atDepth: stack.count - 1) }

    /// The chips the **wheel** can reach: all of them, wherever the wheel scrolls a highlight.
    ///
    /// Now Playing, the recorder and the editor bind it to seek, gain and trim — there is no
    /// highlight to park on a chip there, and stealing a detent from scrubbing would be the worse
    /// trade. Their chips stay touch-only, which is the one honest exception.
    func ringChipIDs(atDepth depth: Int) -> [String] {
        stack[depth].route.defaultAxis == .highlight && stack[depth].route.modes.isEmpty
            ? chipIDs(atDepth: depth)
            : []
    }

    var ringChipIDs: [String] { ringChipIDs(atDepth: stack.count - 1) }

    /// The lowest and highest index the highlight can hold here.
    func firstIndex(atDepth depth: Int) -> Int {
        leadingActionID(atDepth: depth) != nil ? Self.pinnedIndex : 0
    }

    func lastIndex(atDepth depth: Int) -> Int {
        rowCount(atDepth: depth) - 1 + ringChipIDs(atDepth: depth).count
    }

    var firstIndex: Int { firstIndex(atDepth: stack.count - 1) }
    var lastIndex: Int { lastIndex(atDepth: stack.count - 1) }

    /// Whether the highlight is resting on the pinned verb rather than on a row or a chip.
    var isPinnedActionHighlighted: Bool {
        pinnedActionID != nil && level.highlighted == Self.pinnedIndex
    }

    /// Which chip the wheel is on, if it is on one. The projection reads this to mark it selected,
    /// so a chip added to `chipIDs` gets its cursor without anyone remembering to add it.
    var highlightedChipID: String? {
        let offset = level.highlighted - currentRowCount
        guard offset >= 0, offset < ringChipIDs.count else { return nil }
        return ringChipIDs[offset]
    }

    var isSettingsHighlighted: Bool { highlightedChipID == "settings" }
    var isBackHighlighted: Bool { highlightedChipID == "back" }

    func rowCount(atDepth depth: Int) -> Int {
        let items = items(atDepth: depth)
        switch stack[depth].route {
        case .library: return DialActivity.all.count
        case .settings: return DialSetting.allCases.count
        case .recordings, .folder: return items.count
        case .confirmDelete: return DialRoute.DeleteChoice.allCases.count
        case .move(let itemID): return MoveDestinations.all(in: content.recordings, excluding: itemID).count
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
