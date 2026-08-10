import Foundation
import Observation

/// Holds the dial's navigator and connects it to the rest of the app (#6).
///
/// **It is deliberately thin.** `DialNavigator` decides everything — what a press means, where the
/// highlight goes, which feedback fires — and this type does the two things a pure struct cannot:
/// it keeps the navigator's content fed with the app's real data, and it turns `DialEffect`s into
/// calls on the things that own the hardware.
///
/// Out-edges are closures wired in `AppViewModel.wire()`, like every other cross-feature edge here,
/// which is what makes them reachable from a test with no view rendered.
@MainActor
@Observable
final class DialViewModel {

    /// What the view renders. Recomputed from the navigator, which is the single source of truth.
    var screen: DialScreen { navigator.screen }

    var onPlay: ((String, [String]) -> Void)?
    var onTogglePlayPause: (() -> Void)?
    /// Recording and trimming both want the audio session to themselves.
    var onPausePlayback: (() -> Void)?
    /// `0...1`, already clamped by the navigator.
    var onSetVolume: ((Double) -> Void)?
    var onImportFiles: ((String?) -> Void)?
    /// The dial has no text entry, so naming a new folder is the host's.
    var onCreateFolder: ((String?) -> Void)?
    var onMoveItem: ((String, String?) -> Void)?
    /// Raised only after the user has confirmed. The composition root does the deleting, because a
    /// file leaving disk concerns the player, the markers and the waveform cache as well.
    var onDeleteItem: ((String) -> Void)?

    /// Surfaced when a delete fails. The file is still there and the user has to be told, or the
    /// list quietly disagreeing with disk is the only clue.
    var operationError: String?
    var onSeek: ((TimeInterval) -> Void)?
    var onSelectTrack: ((Int) -> Void)?
    var onStartRecording: (() -> Void)?
    var onSetting: ((DialSetting) -> Void)?
    var onStopRecording: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onAddMarker: (() -> Void)?
    var onSetGain: ((Double) -> Void)?
    var onPreviewTrim: ((String, TimeInterval, TimeInterval) -> Void)?
    var onCommitTrim: ((String, TimeInterval, TimeInterval) -> Void)?
    var onCommitCut: ((String, TimeInterval, TimeInterval) -> Void)?

    /// The five rows of the actions screen. Declared and **not wired** — see `apply(_:)`.
    var onItemAction: ((DialItemAction, String) -> Void)?

    /// Rename the recording open in the editor.
    var onRenameItem: ((String) -> Void)?

    /// Asks the host to feed this type again, because something it renders finished loading
    /// asynchronously. Only the waveform needs it — every other input is state the host can already
    /// see change.
    var onNeedsRefresh: (() -> Void)?
    var onReleasePlayer: (() -> Void)?
    var onCycleRepeat: (() -> Void)?
    var onToggleShuffle: (() -> Void)?

    private var navigator: DialNavigator
    private let haptics: HapticsClient

    /// Extracted waveforms, keyed by file. Extraction reads the whole asset, and `refresh` runs on
    /// every tick of the player's clock, so re-running it there would cost a decode per second.
    private var waveforms: [URL: [Double]] = [:]
    private var waveformsLoading: Set<URL> = []

    init(haptics: HapticsClient = .live) {
        self.navigator = DialNavigator()
        self.haptics = haptics
        haptics.prepare()
    }

    /// Show what is playing, but only if you were not in the middle of something.
    ///
    /// **The guard is the whole design.** Coming back to the app with audio running and landing on
    /// the library is wrong — you returned *because* of the audio. But backgrounding deliberately
    /// while three levels into a list and coming back to Now Playing is worse: it throws away a
    /// place you chose. So this only acts at the root — which is the library itself now that the
    /// fork above it is gone — where there is no place to lose.
    ///
    /// It is safe to call whenever. The navigator refuses when nothing is playing, and refuses
    /// again when Now Playing is already on top, so neither case needs checking here.
    func showNowPlayingIfIdle() {
        guard navigator.route == .recordings else { return }
        receive(.action("nowPlaying"))
    }

    /// The Home-screen quick action, which arrives from UIKit with no view in the picture.
    func openRecorder() {
        for effect in navigator.openRecorder() { apply(effect) }
        onNeedsRefresh?()
    }

    /// The take that just landed is the one you want to name or trim, so the editor opens on it.
    ///
    /// Routed through the same `apply` every command uses, so the effects it produces — pausing
    /// playback, the commit pulse — happen exactly as they would from a press.
    func openEditorForFinishedTake(itemID: String) {
        let routeBefore = navigator.route
        for effect in navigator.openEditorForFinishedTake(itemID: itemID) { apply(effect) }
        if navigator.route != routeBefore { onNeedsRefresh?() }
    }

    /// The single entry point. Every turn, press and chip tap arrives here.
    ///
    /// **A route change asks to be fed.** Some screens are drawn from data the host only knows to
    /// load once the push has happened — the editor is the case: `content.editing` is built from
    /// `navigator.route`, so the material can only arrive on the refresh *after* the push.
    ///
    /// Nothing was asking for that refresh. It used to arrive by accident, because playback carried
    /// on into the editor and the player's clock ticked twice a second, and `AppView` refreshes on
    /// every tick. Then opening the editor started pausing playback — the clock stopped, the
    /// accident stopped with it, and the editor showed "Nothing to edit" for ever.
    ///
    /// So the request is explicit and tied to the thing that actually changed, rather than
    /// depending on an unrelated value happening to move.
    func receive(_ command: DialCommand) {
        let routeBefore = navigator.route
        for effect in navigator.receive(command) {
            apply(effect)
        }
        if navigator.route != routeBefore { onNeedsRefresh?() }
    }

    /// Re-feeds the navigator from the app's current state.
    ///
    /// Called whenever the underlying data moves. The navigator re-clamps every level's highlight
    /// against the new content, so a list shrinking under a screen you are not looking at cannot
    /// leave a highlight pointing past the end.
    func refresh(
        allFiles: [AudioFile],
        libraryTree: [DialContent.Item],
        settings: SettingsViewModel,
        player: PlayerViewModel,
        recorder: RecordingViewModel,
        markers: MarkerRegistry
    ) {
        var content = DialContent()

        // **Home is two cards, and Import is not one of them — it lives in the library it adds to.**
        //
        // It was a card here first, where it outranked the two things this screen exists to offer.
        // The library is where it belongs: that screen is the place you *add to*, and arriving there
        // from a card marked `Library` with no way to put anything in is the gap that settled it.

        // **There is no Now Playing row, and the corner label is why.**
        //
        // It was a row here for two rounds — a card, first in the list, naming the track the way a
        // corner label never could. What that could not do is exist anywhere else: two levels into
        // the library there was no visible way back to what was playing, because the row lives on
        // this screen only. The label in `DialChrome` follows you down, and following you down is
        // the whole job. See `DialNavigatorScreen.status`.

        // **Nested, not flat.** This used to map `allFiles`, which is a recursive sweep — so every
        // recording appeared at the top level and the folder it lived in appeared nowhere. The flat
        // list is still what the queue and the editor want; only the browsing shape changed.
        //
        // The fallback is not a convenience. The two are loaded by the same call but built by
        // different walks, and the nested one can fail on its own — a folder that becomes
        // unreadable mid-walk throws, and `LibraryTree.load` is caught into an empty array. Without
        // this, that would empty the library on screen while the flat sweep still held every file.
        // A flat list is a worse shape than a nested one; it is a far better answer than nothing.
        content.recordings = libraryTree.isEmpty
            ? allFiles.map {
                DialContent.Item(
                    id: $0.url.absoluteString, title: $0.title, duration: $0.duration
                )
            }
            : libraryTree

        if let track = player.currentTrack {
            content.playback = DialContent.Playback(
                title: track.title,
                subtitle: nil,
                position: player.currentTime,
                duration: player.duration,
                isPlaying: player.isPlaying,
                // **The second half of the volume bug.** `DialContent.Playback.volume` defaults to
                // 1, and this omitted it — so every refresh handed the navigator a full-volume
                // picture and overwrote whatever the wheel had just set. Even with the effect
                // wired, the arc would have snapped back to full on the next tick of the clock.
                volume: player.volume,
                queueIndex: player.currentIndex,
                queueCount: max(1, player.queue.count),
                repeatMode: player.repeatMode,
                isShuffled: player.isShuffleEnabled
            )
        }

        content.settingValues = [
            DialSetting.playbackSpeed.rawValue: settings.defaultPlaybackSpeed.displayText,
            DialSetting.skipDuration.rawValue: settings.defaultSkipDuration.displayText,
            DialSetting.appearance.rawValue: settings.colorScheme.rawValue
        ]

        content.capture = capture(from: recorder)
        content.editing = editable(from: allFiles, markers: markers)

        navigator.update(content)
    }

    // MARK: - Content

    /// **`nil` unless a take is actually open**, which is what makes the recording screen say "not
    /// recording" rather than showing a frozen clock, and what makes the gain axis refuse.
    ///
    /// The bar history is read from the recorder rather than accumulated here, and that is a
    /// correctness point rather than tidiness: this method runs on *every* refresh — the player's
    /// clock, the recents list, the track — so appending a sample per call would push several
    /// copies of one meter reading through the waveform and make it scroll at a rate that has
    /// nothing to do with time. `RecordingViewModel` appends once per `meterInterval`, which is the
    /// rate the waveform is supposed to move at.
    private func capture(from recorder: RecordingViewModel) -> DialContent.Capture? {
        guard recorder.isRecording else { return nil }

        return DialContent.Capture(
            elapsed: recorder.recordingTime,
            levels: recorder.levels,
            gain: recorder.gain,
            markers: recorder.markers.times.enumerated().map { index, time in
                DialContent.Capture.Marker(
                    id: "marker-\(index)",
                    label: String(localized: "Marker \(index + 1)"),
                    time: time
                )
            },
            isPaused: recorder.isPaused,
            isGainSettable: recorder.isGainSettable
        )
    }

    /// The material behind the edit screen, taken from the item the **route** names.
    ///
    /// The route is the input rather than a selection held here, because the navigator is what
    /// decides where you are. It also means the material necessarily arrives one refresh *after*
    /// the push, which is exactly what `DialNavigator.currentTrim` is written to absorb.
    private func editable(
        from allFiles: [AudioFile], markers: MarkerRegistry
    ) -> DialContent.Editable? {
        guard case .edit(let itemID) = navigator.route,
              let file = allFiles.first(where: { $0.url.absoluteString == itemID })
        else { return nil }

        return DialContent.Editable(
            id: itemID,
            title: file.title,
            waveform: waveform(for: file.url),
            duration: file.duration,
            markers: markers.markers(for: file.url).times
        )
    }

    /// The cached samples, or an empty waveform plus a load that will ask for another refresh.
    ///
    /// An empty array is a legitimate first frame rather than a failure: the screen draws its
    /// handles and its scale from the duration, and the wheel already moves them. Only the picture
    /// behind them is late.
    private func waveform(for url: URL) -> [Double] {
        if let cached = waveforms[url] { return cached }
        guard !waveformsLoading.contains(url) else { return [] }

        waveformsLoading.insert(url)
        Task { [weak self] in
            let samples = await AudioWaveformExtractor.extract(url: url)
            self?.adoptWaveform(samples.map(Double.init), for: url)
        }
        return []
    }

    private func adoptWaveform(_ samples: [Double], for url: URL) {
        waveforms[url] = samples
        waveformsLoading.remove(url)
        onNeedsRefresh?()
    }

    /// Drops a file's cached samples, so an edited recording is not drawn against the shape of the
    /// audio it replaced.
    func forgetWaveform(for url: URL) {
        waveforms.removeValue(forKey: url)
    }

    // MARK: - Effects

    /// **Every case is named, and that is the point of this method.** It used to end in
    /// `default: break` under a comment saying recording and trimming were deliberately inert. Two
    /// things were wrong with that: the default swallowed more cases than the comment described —
    /// volume and the whole actions screen went the same way, silently — and a `default` cannot
    /// distinguish an effect nobody has wired yet from one somebody forgot. Listing them makes the
    /// compiler raise the next addition instead of absorbing it.
    private func apply(_ effect: DialEffect) {
        switch effect {
        case .feedback(let event):
            haptics.fire(DetentFeedback.pulse(for: event))
        case .play(let itemID, let queue):
            onPlay?(itemID, queue)
        case .togglePlayPause:
            onTogglePlayPause?()
        case .releasePlayer:
            onReleasePlayer?()

        case .pausePlayback:
            onPausePlayback?()
        case .seek(let time):
            onSeek?(time)
        case .selectTrack(let index):
            onSelectTrack?(index)
        case .cycleRepeat:
            onCycleRepeat?()

        case .toggleShuffle:
            onToggleShuffle?()

        case .importFiles(let itemID):
            onImportFiles?(itemID)
        case .createFolder(let itemID):
            onCreateFolder?(itemID)
        case .moveItem(let itemID, let folderID):
            onMoveItem?(itemID, folderID)
        case .setting(let setting):
            onSetting?(setting)
        case .startRecording:
            onStartRecording?()
        case .stopRecording:
            onStopRecording?()
        case .toggleRecordingPause:
            onTogglePause?()
        case .addMarker:
            onAddMarker?()
        case .setGain(let value):
            onSetGain?(value)
        case .previewTrim(let itemID, let start, let end):
            onPreviewTrim?(itemID, start, end)
        case .commitCut(let itemID, let start, let end):
            onCommitCut?(itemID, start, end)
        case .commitTrim(let itemID, let start, let end):
            onCommitTrim?(itemID, start, end)

        case .setTrim:
            // **Already applied, not ignored.** The navigator writes the moved handles into its own
            // level before emitting this, and the edit screen is derived from that level — so the
            // waveform carries the new selection on the same frame. The effect exists for a host
            // that wants to hear about it; nothing here does, and calling something would apply the
            // change twice.
            break

        case .setVolume(let value):
            // **This used to be `break`**, under a note saying volume belongs to `MPVolumeView`,
            // which owns the system slider and offers no setter worth having — so an effect that
            // did nothing beat one that fought the hardware buttons.
            //
            // Right about the system volume, wrong as a conclusion. `AVPlayer.volume` is this
            // player's own gain: the wheel changes how loud the app is and the hardware buttons and
            // their slider are untouched. The nudges, the clamp and the ring's arc were all already
            // here; this was the only missing link, and it was silent because a `break` is.
            onSetVolume?(value)

        // **Delete arrives here already confirmed.** The guard is a screen now — `.confirmDelete`,
        // two rows and a subject naming the file — so by the time this effect exists the answer has
        // been given by the same turn-and-press as everything else. The alert this replaced was the
        // one place the dial handed over to UIKit chrome mid-flow, at the only irreversible step.
        case .item(.delete, let itemID):
            onDeleteItem?(itemID)

        case .renameItem(let itemID):
            onRenameItem?(itemID)

        case .item(let action, let itemID):
            // Share and rename are the browser's flows, and the actions screen is its own slice.
            // Named rather than defaulted so a new effect cannot join it by accident, and routed
            // through a closure so wiring it later is one line in `wire()` rather than a change here.
            onItemAction?(action, itemID)
        }
    }
}
