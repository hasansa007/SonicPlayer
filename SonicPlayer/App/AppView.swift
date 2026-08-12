import SwiftUI
import UniformTypeIdentifiers

/// The root screen. It owns nothing but its own share sheet — every view model comes from
/// `AppViewModel` in the environment, which is what replaced the root `Store` (#19).
struct AppView: View {
    @Environment(AppViewModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        // Local `@Bindable` shadows: the documented way to get bindings out of an @Observable
        // held in the environment. `app` itself is not bindable from an @Environment property.
        @Bindable var app = app
        @Bindable var player = app.player
        @Bindable var filesRoot = app.filesRoot

        return ZStack(alignment: .bottom) {
            // Main content
            // **A plain `NavigationStack` with no path and no destinations.** It held the Files
            // browser, pushed by URL; the dial browses now and its stack is its own. What is left
            // is the container the sheets and alerts below hang from.
            NavigationStack {
                // **The dial is the app** (#6, #76). There is no Home screen and no tab bar: the
                // player is the root, and everything else — recordings, now playing, recording —
                // is a level of the dial's own stack rather than a separate destination.
                //
                // **The toolbar gear is gone with the push.** Settings is a dial route now, reached
                // from the gear in the card's own header — there were briefly two of them, one in a
                // navigation bar the rest of the app hides.
                dialRoot
                    .alert("Delete \(filesRoot.pendingDeleteCount) \(filesRoot.pendingDeleteCount == 1 ? "item" : "items")?",
                           isPresented: $filesRoot.isConfirmingDelete) {
                        Button("Delete", role: .destructive) { filesRoot.confirmDelete() }
                        Button("Cancel", role: .cancel) {}
                    }
                    .alert("New Collection", isPresented: Binding(
                        get: { filesRoot.isCreatingCollection },
                        set: { if !$0 { filesRoot.cancelNameInput() } }
                    )) {
                        TextField("Name", text: $filesRoot.inputText)
                        Button("Create") { filesRoot.confirmNameInput() }
                        Button("Cancel", role: .cancel) { filesRoot.cancelNameInput() }
                    }
                    // Naming a folder the dial asked for. The dial has no text entry, so this is
                    // where a `createFolder` effect turns into a folder.
                    .alert("New Folder", isPresented: $app.isNamingNewFolder) {
                        TextField("Name", text: $app.newFolderName)
                        Button("Create") { app.confirmNewFolder(named: app.newFolderName) }
                        Button("Cancel", role: .cancel) { app.isNamingNewFolder = false }
                    }
                    .alert("Rename", isPresented: isRenaming) {
                        TextField("Name", text: $filesRoot.inputText)
                        Button("Rename") { filesRoot.confirmNameInput() }
                        Button("Cancel", role: .cancel) { filesRoot.cancelNameInput() }
                    }
                    .sheet(item: $app.shareItem) { item in
                        ActivityView(items: [item.url])
                    }
                    .onAppear {
                        if !ScreenshotMode.isEnabled {
                            filesRoot.onAppear()
                            home.loadAllFiles()
                        }
                    }
            }
            .preferredColorScheme(app.settings.colorScheme.colorScheme)

            // The mini-player is gone with Home. It existed to get you *back* to the player from
            // somewhere else, and there is no longer a somewhere else — the player is the root.

            // The record FAB is gone too. The dial carries Record as a section, and a floating
            // button over it would be a second door to the same room.
        }
        // **There is no recording sheet.** The dial's recorder is the only one, reached by its own
        // Record route and by the Home-screen quick action, which used to raise a second one here.
        .sheet(isPresented: isImportSheetPresented) {
            DocumentPicker { urls in
                app.isImportSheetPresented = false
                app.importPickedFiles(urls)
            }
        }
        // **About and How it works are dial screens now** (#50). Two `.sheet`s stood here — the last
        // modals the dial raised over itself, and the last two conventional screens in the app. Both
        // are routes on the dial's own stack, so there is nothing left to present.
        .onChange(of: scenePhase) { _, newPhase in
            app.scenePhaseChanged(newPhase)
        }
        .onOpenURL { url in
            app.openedFromFiles(url)
        }
        .alert("Action Failed", isPresented: Binding(
            get: { player.openError != nil },
            set: { if !$0 { player.openError = nil } }
        )) {
            Button("OK", role: .cancel) { player.openError = nil }
        } message: {
            if let error = player.openError { Text(error) }
        }
        // Wiring used to happen here too. It is construction work now — `AppViewModel.init` —
        // so this only carries what genuinely belongs to appearing.
        .onAppear { app.onAppear() }
        .fullScreenCover(isPresented: Binding(
            get: { app.onboarding != nil },
            set: { _ in }
        )) {
            if let onboarding = app.onboarding {
                OnboardingView(viewModel: onboarding)
            }
        }
    }
}

// MARK: - Children
//
// Read-only pass-throughs to the coordinator. `home` and `filesRoot` are internal because
// `CollectionsSection` is an extension on this type in another file.

extension AppView {
    var player: PlayerViewModel { app.player }
    var home: HomeViewModel { app.home }
    var filesRoot: CollectionsViewModel { app.filesRoot }
}

// MARK: - Private

private extension AppView {

    var isRenaming: Binding<Bool> {
        Binding(
            get: { filesRoot.renamingItem != nil },
            set: { if !$0 { filesRoot.cancelNameInput() } }
        )
    }

    var isImportSheetPresented: Binding<Bool> {
        Binding(
            get: { app.isImportSheetPresented },
            set: { if !$0 { app.isImportSheetPresented = false } }
        )
    }


    // MARK: - Expanded Player Overlay

    // MARK: - Home Root Content

    @ViewBuilder
    /// The dial, fed from the app whenever anything it renders moves.
    ///
    /// The navigator holds a *snapshot* rather than reaching back into the view models, so every
    /// source it draws from has to push. That is the cost of the contract being a plain value, and
    /// it is the same cost that makes the whole navigator testable without a view.
    var dialRoot: some View {
        DialScreenView(screen: app.dial.screen) { app.dial.receive($0) }
            .onAppear { app.refreshDial() }
            // **The dial's volume is the phone's volume.** This stream seeds it on the first
            // value — so the ring opens at the device's level rather than at a default of full —
            // and then keeps it there through every hardware press and Control Centre drag. It runs
            // for the lifetime of the view, which is the lifetime of the app.
            .task { await app.player.observeSystemVolume() }
            .onChange(of: app.player.volume) { _, _ in app.refreshDial() }
            .onChange(of: app.player.currentTime) { _, _ in app.refreshDial() }
            .onChange(of: app.player.isPlaying) { _, _ in app.refreshDial() }
            .onChange(of: app.player.currentTrack) { _, track in
                app.refreshDial()
                // Session restore is asynchronous, so a cold launch reaches the library first and
                // the track lands a moment later. This is where that arrival is noticed.
                if track != nil { app.dial.showNowPlayingIfIdle() }
            }
            .onChange(of: app.home.allFiles) { _, _ in app.refreshDial() }
            .onChange(of: app.recording.isRecording) { _, _ in app.refreshDial() }
            // **The clock, not the microphone.** This watched `peakLevel`, and the meter loop sets
            // the time, the peak and the waveform sample in one 100ms tick — so any of them looks
            // like it would do. It does not: in a quiet room consecutive peak readings are
            // *identical*, `onChange` does not fire on an equal value, and the running timer
            // stopped for as long as the room stayed the same. It advanced when you made a noise,
            // which is a clock that appears to stall and then catch up.
            //
            // `recordingTime` changes on every tick by construction, and it is the value on screen.
            // Watching it covers the meter and the waveform too, since they arrive together.
            .onChange(of: app.recording.recordingTime) { _, _ in app.refreshDial() }
            // Pausing stops the meter, so `recordingTime` stops changing — without this the screen
            // would keep the running state it had at the moment the take was paused (#75).
            .onChange(of: app.recording.isPaused) { _, _ in app.refreshDial() }
            // A marker must appear under the thumb, not up to a meter interval later.
            .onChange(of: app.recording.markers) { _, _ in app.refreshDial() }
            .alert(
                "Action Failed",
                isPresented: Binding(
                    get: { app.dial.operationError != nil },
                    set: { if !$0 { app.dial.operationError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { app.dial.operationError = nil }
            } message: {
                Text(app.dial.operationError ?? "")
            }
            .toolbar(.hidden, for: .navigationBar)
    }


}
