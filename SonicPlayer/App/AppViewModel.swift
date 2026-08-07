import Foundation
import Observation

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
@MainActor
@Observable
final class AppViewModel {

    // MARK: - Presentation
    //
    // The three flags that were all `AppFeature.State` had left. `isSettingsPresented` drives a
    // `.navigationDestination` push, not a sheet — the old name (`isSettingsSheetPresented`) said
    // otherwise and is corrected here, since nothing outside this type reads it any more.

    var isRecordingSheetPresented = false
    var isSettingsPresented = false
    var isImportSheetPresented = false

    // MARK: - Children

    let player: PlayerViewModel
    let home: HomeViewModel
    let recording: RecordingViewModel
    let settings: SettingsViewModel
    let filesRoot: CollectionsViewModel

    /// Non-`let` because completing onboarding discards it, which is what `store.onboarding != nil`
    /// expressed before #14.
    var onboarding: OnboardingViewModel?

    /// The navigation stack below the root browser. Lives here rather than on `AppView` so the
    /// wiring below can push onto it without reaching back into the view.
    var path: [URL] = []

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
        onboarding: OnboardingViewModel?
    ) {
        self.player = player
        self.recording = recording
        self.settings = settings
        self.filesRoot = filesRoot
        self.onboarding = onboarding
        // Home holds the *same* player instance — that is what let `HomeFeature`'s three mirrored
        // playback properties be deleted rather than ported (#16), so it cannot be defaulted
        // independently of `player`.
        self.home = HomeViewModel(player: player)
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
    }

    /// A file handed over by another app. The player owns this rather than the coordinator,
    /// because it has to outrank the session restore running alongside it (#33).
    func openedFromFiles(_ url: URL) {
        player.openFromFiles(url) { [filesRoot] in filesRoot.refreshFiles() }
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
            home.loadRecentFiles()
        }

        // The root browser's out-edges — what the `AppCommand` channel used to carry (#18).
        filesRoot.onCollectionTapped = { [weak self] folder in self?.path.append(folder.url) }
        filesRoot.onPlay = { [player] file, queue, source in
            player.loadTrack(file, queue: queue, source: source)
        }
        filesRoot.onWillRemoveItems = { [player] items in
            player.clearSessionIfAffected(by: items.map(\.url))
        }
        // Any reload of the root browser refreshes Home's recents, which are drawn from it.
        filesRoot.onItemsLoaded = { [home] in home.loadRecentFiles() }
    }
}
