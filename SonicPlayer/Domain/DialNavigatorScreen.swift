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
            isSettingsHighlighted: isSettingsHighlighted,
            isLive: isLive,
            transport: transport,
            canGoBack: stack.count > 1,
            isBackHighlighted: isBackHighlighted
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
        // **The empty state is a message again.** It was folded into the Import row's second line,
        // which worked only while Import was a row — with the verb pinned above the list, an empty
        // library would otherwise be a blank card that says nothing about why.
        //
        // It names the mode's verb and points **up**, at the row the highlight is already resting
        // on. It said "using the buttons below" for a while after those buttons had moved, which is
        // the failure mode of copy that describes a layout rather than an action.
        case .recordings, .folder:
            guard !currentItems.isEmpty else {
                // **The instruction lives here now.** Record and Import were the only controls
                // with a subtitle — "Capture something new", "Bring audio in from Files" — and as
                // chips they are a glyph and a VoiceOver label. On an empty library that sentence
                // was the whole empty state, so the empty state says it instead.
                return .message(.init(
                    icon: .recording,
                    title: "Nothing here yet",
                    body: "Record a take, or import audio from Files — both are below the card."
                ))
            }
            return .list(list(rows: recordingRows))

        case .settings:
            return .list(list(rows: settingRows))

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
                isPlaying: playback.isPlaying,
                volume: playback.volume
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
                operation: level.trimOperation,
                scale: [
                    DialTimeFormat.clock(0),
                    DialTimeFormat.clock(trim.start),
                    DialTimeFormat.clock(trim.end),
                    DialTimeFormat.clock(editing.duration)
                ]
            ))

        // The subject is not decoration here — it is the whole guard. Two verbs with nothing
        // naming what they act on is exactly the screen `Delete` must not be.
        // The subject is the whole point again: a list of folders with nothing saying what is
        // being filed is a list of folders.
        case .move(let itemID):
            return .list(list(rows: moveRows(for: itemID), subject: subject(for: itemID)))

        case .confirmDelete(let itemID):
            return .list(list(rows: deleteChoiceRows, subject: subject(for: itemID)))
        }
    }

    private func list(
        rows: [DialScreen.List.Row],
        subject: DialScreen.List.Subject? = nil
    ) -> DialScreen.List {
        DialScreen.List(
            rows: rows,
            // **Out of range on purpose when the wheel is on a chrome stop.**
            //
            // This clamped into the rows, which is exactly wrong at the ends: with the highlight on
            // Back, `min(rowCount, rows.count - 1)` handed the cursor back to the *last row* — so
            // the card drew two things selected at once, the row and the control, and neither
            // looked like the one the hub would act on. Seen on the phone, and it is the same
            // reading either stop: no row is highlighted, because the highlight is not on a row.
            highlighted: rows.indices.contains(level.highlighted) ? level.highlighted : -1,
            subject: subject,
            isProminent: route.showsProminentRows
        )
    }

    private func moveRows(for itemID: String) -> [DialScreen.List.Row] {
        MoveDestinations.all(in: content.recordings, excluding: itemID).map { destination in
            .init(
                id: destination.id ?? "root",
                icon: destination.id == nil ? .library : .playlist,
                title: destination.path,
                // **The folder it is already in says so rather than being hidden.** Removing it
                // would make the list depend on where the file happens to live, so the same folder
                // would be at a different index depending on what you are filing.
                subtitle: destination.id == currentFolderID ? "Where it is now" : nil
            )
        }
    }

    /// The recording the action rows act on. Without it the screen is five verbs and no object.
    private func subject(for itemID: String) -> DialScreen.List.Subject? {
        guard let item = content.item(itemID) else { return nil }

        // **A folder has to say what it takes with it.** Deleting one is not deleting one thing,
        // and a guard that names only the folder is a guard that hides the cost of confirming it.
        if let children = item.children {
            let files = children.count { !$0.isFolder }
            let folders = children.count(where: \.isFolder)
            let parts = [
                files == 1 ? "1 recording" : "\(files) recordings",
                folders == 0 ? nil : (folders == 1 ? "1 folder" : "\(folders) folders")
            ].compactMap { $0 }
            return DialScreen.List.Subject(
                icon: .playlist,
                title: item.title,
                detail: children.isEmpty ? "Empty" : parts.joined(separator: " · ")
            )
        }

        return DialScreen.List.Subject(
            icon: .recording,
            title: item.title,
            detail: [DialTimeFormat.clock(item.duration), item.subtitle]
                .compactMap { $0 }
                .joined(separator: " · ")
        )
    }


    /// Import, then every audio file the app can see.
    ///
    /// **Import belongs to a library, which is what this screen turned out to be.** It was tried as
    /// a card on home, a chip here, a row here, and then removed altogether — the removal on the
    /// The preference under the highlight, or `nil` anywhere but Settings.
    private var highlightedSetting: DialSetting? {
        guard case .settings = route,
              DialSetting.allCases.indices.contains(level.highlighted) else { return nil }
        return DialSetting.allCases[level.highlighted]
    }

    /// Preferences as rows, each carrying its current value in the trailing column.
    ///
    /// The values come from the host — `Domain/` is Foundation-only and knows nothing about what a
    /// playback speed is, only that it has a printable current value and a next one.
    private var settingRows: [DialScreen.List.Row] {
        DialSetting.allCases.map { setting in
            .init(
                id: setting.rawValue,
                icon: setting.icon,
                title: setting.title,
                trailing: content.settingValues[setting.rawValue],
                subtitle: setting.subtitle,
                opensSomewhere: !setting.cycles
            )
        }
    }

    /// Every row is a file or a folder.
    ///
    /// **Import and New folder used to be here and are buttons now.** They were a row, then a
    /// pinned row, and both versions had the same problem: a thing you *do* sitting in a list of
    /// things you *have*, competing for the highlight with the files and forcing every reader of
    /// that highlight through an offset. In the bottom bar they are next to Back and Refresh, which
    /// are the app's other verbs, and this list went back to being only its contents.
    private var recordingRows: [DialScreen.List.Row] {
        // **Folders read as folders, not as silent recordings.** They carry the playlist glyph the
        // `Add to playlist` nudge already uses, and their trailing column counts what is inside
        // rather than showing a duration — a folder's total length is a number nobody navigates by.
        currentItems.map { item in
            DialScreen.List.Row(
                id: item.id,
                icon: item.isFolder ? .playlist : .recording,
                title: item.title,
                trailing: item.isFolder
                    ? "\(item.children?.count ?? 0)"
                    : DialTimeFormat.clock(item.duration),
                subtitle: item.subtitle
            )
        }
    }

    private var deleteChoiceRows: [DialScreen.List.Row] {
        DialRoute.DeleteChoice.allCases.map {
            .init(id: $0.rawValue, icon: $0.icon, title: $0.label)
        }
    }

    // MARK: - Actions

    /// **Navigation is a chip again, and the card has no bottom bar.**
    ///
    /// Back spent a while as a control in the card's bottom-left and Settings as a gear in its
    /// top-right corner. Both are back in this row, which is where every other touch target on the
    /// dial lives — the bar was a second control surface inside the card, competing with the row
    /// twenty points below it for the same thumb.
    ///
    /// They are still ring stops: `.selected` is how a chip says the wheel is resting on it, the
    /// same signal a chosen mode uses on Now Playing.
    private var actions: [DialScreen.Action] {
        chipIDs.compactMap(chip)
    }

    /// One chip, built from its id.
    ///
    /// **The navigator owns the list and this owns the look.** They were one function, which is how
    /// Sort shipped drawn-but-unreachable: the projection invented a chip the ring had never heard
    /// of. Now `chipIDs` is the single list, the ring walks it, and anything it names gets a cursor
    /// here for free — `highlightedChipID` is the whole of that.
    private func chip(_ id: String) -> DialScreen.Action? {
        let isUnderTheWheel = highlightedChipID == id

        switch id {
        // **Disabled at the root rather than absent**, so the row keeps its shape: Back leads
        // everywhere, and a chip that appeared one level down would shove every other one sideways
        // under a thumb that had learned where they were.
        case "back":
            guard canGoBack(atDepth: stack.count - 1) else {
                return .init(id: id, label: "Back", icon: .back, emphasis: .disabled)
            }
            return .init(id: id, label: "Back", icon: .back, emphasis: isUnderTheWheel ? .selected : .plain)

        case "settings":
            return .init(id: id, label: "Settings", icon: .settings, emphasis: isUnderTheWheel ? .selected : .plain)

        case "newFolder":
            return .init(id: id, label: "New folder", icon: .newFolder,
                         emphasis: highlightedChipID == id ? .selected : .plain)

        case "record":
            return .init(id: id, label: "Record", icon: .recording,
                         emphasis: highlightedChipID == id ? .selected : .destructive)

        case "import":
            return .init(id: id, label: "Import", icon: .importFile,
                         emphasis: highlightedChipID == id ? .selected : .plain)

        case "sort":
            return .init(
                id: id,
                label: level.sort.title,
                icon: .sort,
                // **Two things share this fill and they do not conflict.** A sort that is not the
                // default is worth marking, and so is the wheel resting on it — either way the chip
                // is the one to look at.
                emphasis: isUnderTheWheel || level.sort != .newest ? .selected : .plain
            )

        case "repeat":
            guard let transport else { return nil }
            return .init(
                id: id,
                label: transport.repeatMode == .one ? "Repeat one" : "Repeat",
                // `repeat.1` is the one repeat state a bare `repeat` glyph cannot say, which is why
                // the icon follows the mode rather than the emphasis carrying all three.
                icon: transport.repeatMode == .one ? .repeatOne : .repeatAll,
                emphasis: transport.repeatMode == .off ? .plain : .selected
            )

        case "shuffle":
            guard let transport else { return nil }
            return .init(
                id: id,
                label: "Shuffle",
                icon: .shuffle,
                emphasis: transport.isShuffled ? .selected : .plain
            )

        default:
            return nil
        }
    }

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
    /// **Nothing defers any more, and the mode is why.**
    ///
    /// The deferral existed for exactly one ambiguity: on the library a single press played and a
    /// double press edited, so every single press had to wait to find out whether a second was
    /// coming. With Listen and Record the press means one thing on each side of the fork — so the
    /// wait bought nothing and cost `holdDuration` on every open.
    private var defersPress: Bool { false }

    /// What the highlight is pointing at on a library list, or `nil` anywhere else. Folders count:
    /// they are the same list at a deeper level, drawn and turned through the same way.
    private var highlightedLibraryItem: DialContent.Item? {
        guard isFileList, currentItems.indices.contains(level.highlighted) else { return nil }
        return currentItems[level.highlighted]
    }

    /// Whether this screen is a folder — asked in a couple of places that do not care which one.
    private var isFolder: Bool {
        if case .folder = route { return true }
        return false
    }

    /// Whether this screen lists files, which is the library root and every folder under it.
    private var isFileList: Bool { route == .recordings || isFolder }

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
                // The only two nudges that repeat while held — one shove is 5%, so crossing the
                // range was twenty of them.
                up: .init(id: "volumeUp", icon: .volumeUp, label: "Volume up", repeatsWhenHeld: true),
                down: .init(id: "volumeDown", icon: .volumeDown, label: "Volume down", repeatsWhenHeld: true),
                left: .init(id: "previous", icon: .previous, label: "Previous track"),
                right: .init(id: "next", icon: .next, label: "Next track")
            )

        // **Trim keeps the selection, delete removes it — the two things you can do to a region.**
        // The hub stays `DONE`, so the wheel says what the selection is *for* rather than making
        // you find it on a menu. Absent until the material has loaded: nothing to act on.
        case .edit:
            guard content.editing != nil else { return nil }
            return DialScreen.Directions(
                up: .init(id: "trim", icon: .trim, label: "Trim to selection"),
                down: .init(id: "cut", icon: .delete, label: "Delete selection"),
                // **Hearing the selection is the point of setting it.** Preview has moved three
                // times — a chip, then the hub's settle state — and both homes were wrong for the
                // same reason: it competed with the press that rewrites the file. On its own
                // direction it competes with nothing.
                right: .init(id: "preview", icon: .play, label: "Preview selection")
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
        case .settings:
            return nil

        case .recordings, .folder:
            guard let item = highlightedLibraryItem else { return nil }

            // **A folder answers two of the four.** Share takes a file URL and adding a folder to a
            // playlist is a move this slice does not do; renaming and deleting one were never the
            // problem, and the stick sat blank over folders for long enough that a library could
            // grow them and never touch them again.
            guard !item.isFolder else {
                return DialScreen.Directions(
                    up: .init(id: "rename", icon: .rename, label: "Rename folder"),
                    down: .init(id: "delete", icon: .delete, label: "Delete folder")
                )
            }

            // **All four, and no mode deciding which.** Up used to be absent in Listen and Rename in
            // Record; the fork is gone, so every verb a file answers is here, always. Edit is up
            // because it is the one that rewrites the file — the same reason it releases the player
            // on the way in.
            return DialScreen.Directions(
                up: .init(id: "edit", icon: .trim, label: "Trim"),
                down: .init(id: "delete", icon: .delete, label: "Delete"),
                left: .init(id: "move", icon: .move, label: "Move to folder"),
                right: .init(id: "share", icon: .share, label: "Share")
            )

        default:
            return nil
        }
    }

    /// The queue toggles, on the one screen that owns the queue.
    private var transport: DialScreen.Chrome.Transport? {
        guard case .nowPlaying = route, let playback = content.playback else { return nil }
        return .init(repeatMode: playback.repeatMode, isShuffled: playback.isShuffled)
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
            // **Measured over the whole ring, both stops included** — the same span
            // `moveHighlight` turns through. Counting only the rows leaves the thumb still while
            // the highlight moves onto a control, which reports the wheel as stuck exactly where
            // it is not.
            return .browse(
                thumb: fraction(level.highlighted - firstIndex, of: lastIndex - firstIndex + 1)
            )
        }
    }

    /// What the hub says while the wheel rests on a chip. Upper case like every other hub label,
    /// and the chip's own words rather than a second vocabulary.
    private func chipHubLabel(_ id: String) -> String {
        switch id {
        case "sort": return level.sort.next.hubLabel
        default: return (chip(id)?.label ?? id).uppercased()
        }
    }

    private var hub: DialScreen.Hub {
        // **A chip names itself, before the route gets a say.** The hub says what the thing under
        // the highlight does, everywhere — and on Back it cannot say OPEN. Driven off
        // `highlightedChipID` rather than a case per chip, so the next one added is named without
        // anyone remembering to come here.
        if let chip = highlightedChipID { return .label(chipHubLabel(chip)) }

        switch route {
        // The hub names what the row under it does, which on this screen is two different things.
        case .settings:
            return highlightedSetting?.cycles == false ? .label("OPEN") : .label("CHANGE")

        // A folder opens; a file plays. One meaning each, on one screen.
        case .recordings, .folder:
            // On the pinned stop the hub is the verb itself — the one row where PLAY and EDIT are
            // both wrong.
            if highlightedLibraryItem?.isFolder == true { return .label("OPEN") }
            return .label("PLAY")

        case .nowPlaying:
            return .glyph(content.playback?.isPlaying == false ? "play.fill" : "pause.fill")
        case .recording:
            return .recordDot
        // One state, one meaning: `DONE` applies whichever operation the nudges armed. It briefly
        // had two — settle, then play — which stopped making sense once the nudges themselves
        // committed, and stopped existing when they went back to arming.
        case .edit:
            return .label("DONE")
        case .confirmDelete:
            return .label("CONFIRM")
        case .move:
            return .label("FILE HERE")
        }
    }

    // MARK: - Hint

    /// The only thing teaching rotate/press/hold, so it follows the mode rather than describing the
    /// screen in general — a caption that says "rotate to seek" while the wheel is set to Volume is
    /// worse than none.
    private func chipHint(_ id: String) -> String {
        switch id {
        case "back": return "go back"
        case "settings": return "open settings"
        case "sort": return "sort \(level.sort.next.hint)"
        case "repeat": return "change repeat"
        case "shuffle": return "toggle shuffle"
        default: return (chip(id)?.label ?? id).lowercased()
        }
    }

    private var hint: String {
        if let chip = highlightedChipID {
            return "press to \(chipHint(chip)) · rotate for the list"
        }

        switch route {
        case .recordings, .folder:
            if currentItems.isEmpty { return "nothing here yet · record or import below" }
            if highlightedLibraryItem?.isFolder == true {
                return "rotate to scroll · press to open the folder"
            }
            return "rotate to scroll · press to play · nudge to trim, move, delete or share"

        case .settings:
            return highlightedSetting?.cycles == false
                ? "rotate to scroll · press to open"
                : "rotate to scroll · press to change"

        case .move:
            return "rotate to choose a folder · press to file it there"

        case .nowPlaying:
            // One sentence, because the wheel does one thing. The segments beside and above it
            // are named in the third clause rather than getting a hint each.
            let press = content.playback?.isPlaying == false ? "press to play" : "press to pause"
            return "rotate to seek · \(press) · nudge for track and volume"

        case .recording:
            return "ring shows input level · rotate to set gain · press to stop"

        case .edit:
            // Names the press, the way to change your mind, and the way to check first — in that
            // order, because that is the order they are wanted in.
            return level.trimOperation == .remove
                ? "press to delete the selection · up to keep it instead · right to hear it"
                : "press to trim to the selection · down to delete it instead · right to hear it"

        // Says what the press will do rather than how to press. This is the one screen where the
        // wrong answer cannot be taken back, so the caption names the outcome.
        case .confirmDelete:
            return "deleting cannot be undone · rotate to choose · press to confirm"
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
