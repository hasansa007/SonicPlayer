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

    var onPlay: ((String) -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?
    var onSelectTrack: ((Int) -> Void)?
    var onStartRecording: (() -> Void)?
    var onImportFiles: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onAddMarker: (() -> Void)?
    var onSetGain: ((Double) -> Void)?
    var onPreviewTrim: ((String, TimeInterval, TimeInterval) -> Void)?
    var onCommitTrim: ((String, TimeInterval, TimeInterval) -> Void)?

    /// The five rows of the actions screen. Declared and **not wired** — see `apply(_:)`.
    var onItemAction: ((DialItemAction, String) -> Void)?

    /// Asks the host to feed this type again, because something it renders finished loading
    /// asynchronously. Only the waveform needs it — every other input is state the host can already
    /// see change.
    var onNeedsRefresh: (() -> Void)?

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

    /// The single entry point. Every turn, press and chip tap arrives here.
    func receive(_ command: DialCommand) {
        for effect in navigator.receive(command) {
            apply(effect)
        }
    }

    /// Re-feeds the navigator from the app's current state.
    ///
    /// Called whenever the underlying data moves. The navigator re-clamps every level's highlight
    /// against the new content, so a list shrinking under a screen you are not looking at cannot
    /// leave a highlight pointing past the end.
    func refresh(
        recentFiles: [AudioFile],
        player: PlayerViewModel,
        recorder: RecordingViewModel,
        markers: MarkerRegistry
    ) {
        var content = DialContent()

        content.sections = [
            // **Import is first**, because it is the only way audio the app did not record itself
            // gets in — and with Home gone, nothing else asks for it.
            DialContent.Section(
                id: "import",
                icon: .add,
                title: String(localized: "Import"),
                count: nil,
                destination: nil,
                effect: .importFiles
            ),
            DialContent.Section(
                id: "recordings",
                icon: .recording,
                title: String(localized: "Library"),
                count: recentFiles.count,
                destination: .recordings
            ),
            // **No "Now Playing" row.** It is not a place you go — it is where the app rests, and a
            // list of places that includes the thing you are already doing is a category error. It
            // is also useless exactly half the time, since there is nothing to go to when nothing
            // plays. The chrome's status line is the way in, and `hold` still works from anywhere.
            DialContent.Section(
                id: "record",
                icon: .marker,
                title: String(localized: "Record"),
                count: nil,
                destination: .recording
            )
        ]

        content.recordings = recentFiles.map { file in
            DialContent.Item(
                id: file.url.absoluteString,
                title: file.title,
                duration: file.duration,
                subtitle: nil
            )
        }

        if let track = player.currentTrack {
            content.playback = DialContent.Playback(
                title: track.title,
                subtitle: nil,
                position: player.currentTime,
                duration: player.duration,
                isPlaying: player.isPlaying,
                queueIndex: player.currentIndex,
                queueCount: max(1, player.queue.count)
            )
        }

        content.capture = capture(from: recorder)
        content.editing = editable(from: recentFiles, markers: markers)

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
        from recentFiles: [AudioFile], markers: MarkerRegistry
    ) -> DialContent.Editable? {
        guard case .edit(let itemID) = navigator.route,
              let file = recentFiles.first(where: { $0.url.absoluteString == itemID })
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
        case .play(let itemID):
            onPlay?(itemID)
        case .togglePlayPause:
            onTogglePlayPause?()
        case .seek(let time):
            onSeek?(time)
        case .selectTrack(let index):
            onSelectTrack?(index)
        case .importFiles:
            onImportFiles?()
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
        case .commitTrim(let itemID, let start, let end):
            onCommitTrim?(itemID, start, end)

        case .setTrim:
            // **Already applied, not ignored.** The navigator writes the moved handles into its own
            // level before emitting this, and the edit screen is derived from that level — so the
            // waveform carries the new selection on the same frame. The effect exists for a host
            // that wants to hear about it; nothing here does, and calling something would apply the
            // change twice.
            break

        case .setVolume:
            // Volume belongs to `MPVolumeView`, which owns the system slider and publishes no
            // setter worth having. `AppViewModel.wire()` records the same decision for the shell's
            // `onVolumeBy`: an effect that silently does nothing beats one that fights the hardware
            // buttons.
            break

        case .item(let action, let itemID):
            // Share, rename and delete are the browser's flows, and the actions screen is its own
            // slice. Named rather than defaulted so a new effect cannot join it by accident, and
            // routed through a closure so wiring it later is one line in `wire()` rather than a
            // change here.
            onItemAction?(action, itemID)
        }
    }
}
