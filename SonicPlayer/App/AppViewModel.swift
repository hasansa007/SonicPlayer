import Foundation
import Observation
import SwiftUI    // ScenePhase only — this type renders nothing.

/// The composition root, and what replaced `AppFeature` and the root `Store` (#19).
///
/// **It exists because something outside SwiftUI needs a handle.** `AppDelegate` receives quick
/// actions from UIKit and has to reach app state from there; `@State` cannot be static, so the
/// root object must be. That was the only thing keeping the store alive by this slice — the
/// thirteen cross-feature taps the issue described had already been absorbed by slices 7-9, and
/// what was left of `AppFeature` was three booleans.
///
/// **It owns the child view models so that wiring is construction rather than a view side effect.**
/// `AppView.wireViewModels()` used to run in `.onAppear`, which fires again whenever the view
/// reappears; it was idempotent, so this is tidiness rather than a bug fix. Owning them also means
/// `CollectionsSection` — an extension on `AppView` — reads them from here instead of from stored
/// properties that had to be widened to internal for it.
///
/// **Deliberately not a place for logic.** It composes, it wires, and it holds the three
/// presentation flags. Anything that decides something belongs on the view model that owns the
/// state, or in `Domain/`.
///
/// **One exception, taken knowingly (#41):** it holds a `FileManagerClient` and decides, in
/// `scenePhaseChanged`, when to drain iOS's staging directory. That is app housekeeping no feature
/// owns — draining belongs to neither the player nor the browser — and its two conditions
/// (`.background` only, and never while an import is in flight) are lifecycle facts rather than
/// domain rules, so `Domain/` would not hold them either. ADR 0003 has the reasoning. If a second
/// such thing appears, that is the signal this rule needs revisiting rather than another exception.
@MainActor
@Observable
final class AppViewModel {

    // MARK: - Presentation
    //
    // The three flags that were all `AppFeature.State` had left. `isSettingsPresented` drives a
    // `.navigationDestination` push, not a sheet — the old name (`isSettingsSheetPresented`) said
    // otherwise and is corrected here, since nothing outside this type reads it any more.

    var isRecordingSheetPresented = false
    /// The file the share sheet is presenting.
    ///
    /// **It lived on `AppView` as `@State`, which is why sharing did not work from anywhere.** A
    /// view model cannot set a view's private state, and the one place that assigned it —
    /// `recentFilesSection`, inside `homeRootContent` — has been unreferenced since the dial
    /// replaced Home. The sheet was there, its trigger was not.
    var shareItem: ShareItem?
    var isSettingsPresented = false
    var isImportSheetPresented = false

    // MARK: - Children

    let player: PlayerViewModel
    let home: HomeViewModel
    let recording: RecordingViewModel
    let settings: SettingsViewModel
    let filesRoot: CollectionsViewModel

    /// Holds the *same* player instance, for the same reason `home` does: the shell is a second
    /// face on one playback engine, not a second engine (#6).
    let shell: ShellViewModel

    /// The dial navigator (#6). Replaces `shell` as the presented player; `shell` stays only until
    /// the landscape design lands, since it is still what compact height falls back to.
    let dial: DialViewModel

    /// Which markers belong to which recording (#75). Owned here for the same reason `fileManager`
    /// is: no single feature owns it. The recorder *produces* markers and the editor *reads* them,
    /// and they never exist at the same time — the take is saved and gone before the editor opens.
    let markers = MarkerRegistry()

    /// Bounded playback for the trim editor's preview chip (#74). Separate from `player` because it
    /// plays a *range*, and because a preview must not become part of the listening session.
    let trimPreview: TrimPreview

    /// Non-`let` because completing onboarding discards it, which is what `store.onboarding != nil`
    /// expressed before #14.
    var onboarding: OnboardingViewModel?

    /// The navigation stack below the root browser. Lives here rather than on `AppView` so the
    /// wiring below can push onto it without reaching back into the view.
    var path: [URL] = []

    /// Held for one reason: draining iOS's hand-off directory (#41). No feature owns that — it is
    /// housekeeping for the app, not state any screen shows.
    private let fileManager: FileManagerClient

    /// Held so committing the dial editor's trim can reach it (#74). The dial has no view model of
    /// its own for the edit screen — the navigator holds the selection — so the commit is wired
    /// here like every other cross-feature edge.
    private let audioTrimmer: AudioTrimmerClient

    /// The live composition. Separate from the designated initialiser below because a default
    /// argument expression is evaluated in a *nonisolated* context, and every one of these
    /// initialisers is `@MainActor` — so they cannot be defaults, only a body.
    convenience init() {
        self.init(
            player: PlayerViewModel(),
            recording: RecordingViewModel(),
            settings: SettingsViewModel(),
            filesRoot: CollectionsViewModel(currentDirectory: nil),
            onboarding: OnboardingViewModel.ifNeeded()
        )
    }

    init(
        player: PlayerViewModel,
        recording: RecordingViewModel,
        settings: SettingsViewModel,
        filesRoot: CollectionsViewModel,
        onboarding: OnboardingViewModel?,
        fileManager: FileManagerClient = .live,
        haptics: HapticsClient = .live,
        audioPlayer: AudioPlayerClient = .live,
        audioTrimmer: AudioTrimmerClient = .live
    ) {
        self.player = player
        self.recording = recording
        self.settings = settings
        self.filesRoot = filesRoot
        self.onboarding = onboarding
        self.fileManager = fileManager
        self.audioTrimmer = audioTrimmer
        self.trimPreview = TrimPreview(audioPlayer: audioPlayer)
        // Home holds the *same* player instance — that is what let `HomeFeature`'s three mirrored
        // playback properties be deleted rather than ported (#16), so it cannot be defaulted
        // independently of `player`.
        self.home = HomeViewModel(player: player)
        // Same reasoning as `home`: built from `player` rather than defaulted independently, so a
        // caller substituting the player gets a shell driving that substitute.
        self.shell = ShellViewModel(player: player, haptics: haptics)
        self.dial = DialViewModel(haptics: haptics)
        wire()
    }

    // MARK: - Quick actions
    //
    // The reason this type is reachable statically. `AppDelegate` calls these from UIKit, where
    // there is no view and no environment.

    func quickActionRecord() { isRecordingSheetPresented = true }
    func quickActionImport() { isImportSheetPresented = true }

    // MARK: - Lifecycle

    /// Dismissing the recording sheet throws away an unsaved take — the sheet is
    /// `interactiveDismissDisabled`, so this only runs on an explicit dismissal.
    func dismissRecordingSheet() {
        recording.discardIfUnsaved()
        isRecordingSheetPresented = false
    }

    func onAppear() {
        guard !ScreenshotMode.isEnabled else {
            if let screen = ScreenshotMode.targetScreen {
                ScreenshotDemoData.seedViewModels(
                    player: player, home: home, filesRoot: filesRoot, for: screen
                )
            }
            if ScreenshotMode.targetScreen == .recording || ScreenshotMode.targetScreen == .editRecording {
                isRecordingSheetPresented = true
            }
            return
        }
        player.restoreSession()
        // The restore is asynchronous, so the dial is fed and asked *after* it lands rather than
        // here, where `player.currentTrack` is still nil.
    }

    /// A file handed over by another app. The player owns this rather than the coordinator,
    /// because it has to outrank the session restore running alongside it (#33).
    func openedFromFiles(_ url: URL) {
        player.openFromFiles(url) { [filesRoot] in filesRoot.refreshFiles() }
    }

    /// Forwards to the player, and takes the one piece of housekeeping that belongs to no feature.
    ///
    /// **Draining on `.background`, not at launch, is the whole point.** `OpenInImport` keeps the
    /// staging directory empty from #41 onward, but installs that predate it still hold copies iOS
    /// left there — now invisible, because the browser filters that directory. A launch-time drain
    /// would race `.onOpenURL`: launching the app *by opening a file* is exactly when a staged file
    /// is sitting there waiting to be imported, and the two orderings are not guaranteed — the
    /// session-restore comment above this type says so. Backgrounding cannot collide with a
    /// hand-off, because iOS stages the file when the user shares it, which is after this ran.
    ///
    /// **Synchronous, and that is the correction that makes the placement true.** The first version
    /// dispatched into a `Task`, and measured on the simulator the app suspended before that
    /// continuation ever ran: the drain landed on the *next foreground* instead — reintroducing the
    /// race it was placed here to avoid, because the next foreground is often the `.onOpenURL` that
    /// follows the user sharing a file. Deleting a handful of directory entries on the main actor
    /// costs less than the `session.json` write happening beside it on the same line.
    ///
    /// **An in-flight import outranks it.** `openFromFiles` runs the move detached, so it can still
    /// be working on a file in that directory when the app backgrounds — a large file plus a user
    /// who switches away is all it takes. Draining then would delete the file mid-import, losing it
    /// and raising "Action Failed" for an open iOS had already accepted. Skipping is free: the
    /// leftovers this clears are old, and the next backgrounding gets them.
    ///
    /// Failure is swallowed for the same reason it is in `OpenInImport`: not tidying a directory
    /// the user cannot see must not surface as an error they cannot act on.
    func scenePhaseChanged(_ phase: ScenePhase) {
        player.scenePhaseChanged(phase)

        // Returning to the app with audio running: show what is playing. Guarded to the dial's root
        // so a deliberate background from inside a list does not cost you your place — see
        // `DialViewModel.showNowPlayingIfIdle`.
        if phase == .active {
            refreshDial()
            dial.showNowPlayingIfIdle()
        }

        guard phase == .background, !player.isImporting else { return }
        try? fileManager.drainStagingDirectory()
    }

    // MARK: - Wiring

    /// Every cross-feature edge in the app, in one place, run once at construction.
    ///
    /// Closures capture the specific child they need rather than `self` wherever possible: a child
    /// holding a closure that retains this object would be a cycle, and although a process-lifetime
    /// root would never notice, a test that builds one would leak it.
    private func wire() {
        settings.onDefaultPlaybackSpeedChanged = { [player] speed in player.setPlaybackSpeed(speed) }
        settings.onDefaultSkipDurationChanged = { [player] duration in player.setSkipDuration(duration) }

        onboarding?.onGetStarted = { [weak self] in
            OnboardingViewModel.markSeen()
            self?.onboarding = nil
        }

        // Home's former `.none // Handled by parent` cases. Each needed reducer state — the
        // browser's selection, the navigation stack, a sheet flag — and each is a method call now.
        home.onImportTapped = { [weak self] in self?.isImportSheetPresented = true }
        home.onNewCollectionTapped = { [filesRoot] in filesRoot.createCollectionTapped() }
        home.onViewAllCollectionsTapped = { [weak self] in
            guard let self else { return }
            path.append(filesRoot.documentsDirectoryURL ?? URL(fileURLWithPath: NSHomeDirectory()))
        }
        home.onRenameFile = { [filesRoot] in filesRoot.renameItemTapped(.file($0)) }
        home.onDeleteFile = { [filesRoot] in
            filesRoot.select(.file($0))
            filesRoot.deleteSelectedTapped()
        }
        home.onEditFile = { [filesRoot] in filesRoot.audioToEdit = $0 }
        home.onMoveFile = { [filesRoot] in filesRoot.presentPicker(moving: [.file($0)]) }

        recording.onFinished = { [weak self] in
            guard let self else { return }
            isRecordingSheetPresented = false
            filesRoot.refreshFiles()
            home.loadAllFiles()
        }

        // The root browser's out-edges — what the `AppCommand` channel used to carry (#18).
        filesRoot.onCollectionTapped = { [weak self] folder in self?.path.append(folder.url) }
        filesRoot.onPlay = { [player] file, queue, source in
            player.loadTrack(file, queue: queue, source: source)
        }
        filesRoot.onWillRemoveItems = { [weak self] items in
            guard let self else { return }
            player.clearSessionIfAffected(by: items.map(\.url))
            // A path can be reused: delete `Recording 3.m4a` and record another, and
            // `UniqueNameResolver` may hand out that exact name again. Without this the new take
            // inherits the dead one's markers (#75).
            for url in items.map(\.url) {
                markers.forget(url)
                dial.forgetWaveform(for: url)
            }
        }
        // Any reload of the root browser refreshes Home's recents, which are drawn from it.
        filesRoot.onItemsLoaded = { [home] in home.loadAllFiles() }

        // The shell's out-edges (#6). Closures rather than direct calls for the reason every other
        // edge here is one: it makes the edge reachable from a test without rendering a view.
        shell.onSeek = { [player] time in player.seek(to: time) }
        shell.onPlayPause = { [player] in player.playPauseTapped() }
        shell.onNextTrack = { [player] in player.nextTrack() }
        shell.onPreviousTrack = { [player] in player.previousTrack() }
        shell.onSpeedBy = { [player] steps in
            let all = PlaybackSpeed.allCases
            guard let index = all.firstIndex(of: player.playbackSpeed) else { return }
            player.setPlaybackSpeed(all[min(max(0, index + steps), all.count - 1)])
        }
        // **`onVolumeBy` is the shell's, and it is now wired** — the note that used to sit here said
        // volume belongs to `MPVolumeView` and had no setter worth having, which was true of the
        // *system* volume and became an argument for having no volume control at all. `AVPlayer`
        // has per-player gain; nothing here touches the hardware buttons.
        shell.onVolumeBy = { [player] delta in player.setVolume(player.volume + delta) }

        // The dial's out-edges (#6). It navigates on its own; these are the moments it needs
        // something that owns hardware.
        dial.onPlay = { [player, home] itemID in
            guard let file = home.allFiles.first(where: { $0.url.absoluteString == itemID })
            else { return }
            player.loadTrack(file, queue: home.allFiles, source: nil)
        }
        dial.onTogglePlayPause = { [player] in player.playPauseTapped() }
        // Opening the recorder or the trim editor silences whatever is playing. `pauseIfPlaying`
        // rather than a stop: the track and its position survive, so Now Playing is still there to
        // come back to.
        dial.onPausePlayback = { [player] in player.pauseIfPlaying() }
        dial.onSetVolume = { [player] value in player.setVolume(value) }
        dial.onImportFiles = { [weak self] in self?.isImportSheetPresented = true }

        // **Deleting from the dial goes through the browser's own edge, not around it.**
        //
        // `onWillRemoveItems` is what stops playback of a file about to vanish, forgets its markers
        // and drops its cached waveform — three things that are easy to forget and silent when you
        // do. Calling it here rather than re-implementing them means the dial's delete and the
        // browser's delete cannot drift apart.
        // Renaming moved onto the edit screen when the actions menu became four stick nudges —
        // four directions cannot hold five verbs. The flow is still the browser's, and `AppView`
        // attaches its alert at the root, so it renders over the dial with nothing further to build.
        dial.onRenameItem = { [weak self] itemID in
            guard let self,
                  let file = home.allFiles.first(where: { $0.url.absoluteString == itemID })
            else { return }
            filesRoot.renameItemTapped(.file(file))
        }

        dial.onDeleteItem = { [weak self] itemID in
            guard let self,
                  let file = home.allFiles.first(where: { $0.url.absoluteString == itemID })
            else { return }

            filesRoot.onWillRemoveItems([.file(file)])

            Task { [fileManager] in
                do {
                    try await fileManager.deleteItem(file.url)
                } catch {
                    self.dial.operationError = error.localizedDescription
                    return
                }
                self.home.loadAllFiles()
                self.filesRoot.refreshFiles()
                self.refreshDial()
            }
        }
        dial.onSeek = { [player] time in player.seek(to: time) }
        dial.onSelectTrack = { [player] index in player.jumpToTrack(index) }
        // **Drives the recorder directly rather than presenting the old sheet.** Raising
        // `isRecordingSheetPresented` here put the legacy recording UI *over* the dial's own
        // recording screen, so the level meter was unreachable even once the route was.
        dial.onOpenSettings = { [weak self] in self?.isSettingsPresented = true }
        dial.onStartRecording = { [recording] in recording.startRecordingTapped() }
        dial.onStopRecording = { [recording] in recording.stopRecordingTapped() }

        // Capture (#75). The recorder owns the hardware and the take; the dial owns where you are.
        dial.onTogglePause = { [recording] in recording.togglePauseTapped() }
        dial.onAddMarker = { [recording] in recording.addMarker() }
        dial.onSetGain = { [recording] value in recording.setGain(value) }

        // The take's markers are filed under the name it actually landed as, which
        // `UniqueNameResolver` only settles at save time.
        recording.onSaved = { [weak self] url in
            guard let self else { return }
            markers.set(recording.markers, for: url)
            // **A new take has to enter the library, and nothing was putting it there.** This filed
            // the markers and stopped, so the recording existed on disk and in no list — invisible
            // until some unrelated reload happened to run. Stopping a take now lands you on the
            // library, which made the gap obvious the moment you looked.
            home.loadAllFiles()
            filesRoot.refreshFiles()
        }

        // Trimming (#74). Preview is the hub's second state — press once to settle the handles,
        // again to hear what survives.
        dial.onPreviewTrim = { [weak self] itemID, start, end in
            guard let self,
                  let file = home.allFiles.first(where: { $0.url.absoluteString == itemID })
            else { return }
            // The preview takes the shared engine, so the transport must stop claiming it is
            // playing something it no longer owns.
            if player.isPlaying { player.playPauseTapped() }
            trimPreview.play(url: file.url, from: start, to: end)
        }
        dial.onCommitTrim = { [weak self] itemID, start, end in
            guard let self,
                  let file = home.allFiles.first(where: { $0.url.absoluteString == itemID })
            else { return }
            commitTrim(on: file.url, start: start, end: end)
        }

        // **The actions screen's rows, wired to the flows that already exist.**
        //
        // `.edit` never arrives here — the navigator turns it into a push, because the editor is a
        // place. `.delete` does not either: it stops at `DialViewModel` to raise its confirmation,
        // and comes back through `onDeleteItem`.
        dial.onItemAction = { [weak self] action, itemID in
            guard let self,
                  let file = home.allFiles.first(where: { $0.url.absoluteString == itemID })
            else { return }

            switch action {
            case .share:
                shareItem = ShareItem(url: file.url)
            case .addToPlaylist:
                // **The picker already existed and had one caller.** `InAppCollectionPicker` lists
                // every collection and can create one, `moveToDestination` moves the file and tells
                // the app to reload — which is the "files UI, with a way to add a folder, then
                // refetch" this row was asking for, already built and already presented at the root.
                filesRoot.moveItemTapped(.file(file))
            case .edit, .delete:
                break
            }
        }

        // The waveform is the one input the dial loads for itself, so it is the one that has to ask
        // to be fed again.
        dial.onNeedsRefresh = { [weak self] in self?.refreshDial() }
    }

    /// Rewrites a recording to what its trim keeps, then tells everything that draws it to look
    /// again.
    ///
    /// **The staging discipline is `TrimCommit`'s**, not this method's — a failed export must leave
    /// the recording untouched, and `AudioTrimmerClient.trimAudio` on its own does not promise that.
    /// What belongs here is the part that is genuinely cross-feature: the browser and Home both
    /// draw this file, and the dial has a picture of its old shape cached.
    private func commitTrim(on url: URL, start: TimeInterval, end: TimeInterval) {
        trimPreview.stop()
        Task { [weak self, audioTrimmer] in
            guard let self else { return }
            do {
                _ = try await TrimCommit.run(
                    url: url, start: start, end: end, trimmer: audioTrimmer
                )
            } catch {
                print("Failed to commit trim: \(error.localizedDescription)")
                return
            }
            dial.forgetWaveform(for: url)
            filesRoot.refreshFiles()
            home.loadAllFiles()
            refreshDial()
        }
    }

    /// Re-feeds the dial from the app's current state. Called wherever the data it renders moves,
    /// because the navigator holds a snapshot rather than reaching back into the view models.
    func refreshDial() {
        dial.refresh(
            allFiles: home.allFiles, player: player, recorder: recording, markers: markers
        )
    }
}
