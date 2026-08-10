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
            NavigationStack(path: $app.path) {
                // **The dial is the app** (#6, #76). There is no Home screen and no tab bar: the
                // player is the root, and everything else — recordings, now playing, recording —
                // is a level of the dial's own stack rather than a separate destination.
                //
                // The `NavigationStack` stays only because Settings is still a push. When Settings
                // becomes a dial route it goes too.
                dialRoot
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                app.isSettingsPresented = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .foregroundColor(.sonicTextSecondary)
                            }
                        }
                    }
                    .navigationDestination(isPresented: isSettingsPresented) {
                        SettingsView(viewModel: app.settings)
                            // **Explicit, not inherited.** The dial root hides the navigation bar,
                            // and a pushed screen that inherits that has no back button — which is
                            // a trap rather than a style choice. Stating it here means Settings
                            // cannot be reached and then not left.
                            .toolbar(.visible, for: .navigationBar)
                            .navigationTitle("Settings")
                            .navigationBarTitleDisplayMode(.inline)
                    }
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
                    .alert("Rename", isPresented: isRenaming) {
                        TextField("Name", text: $filesRoot.inputText)
                        Button("Rename") { filesRoot.confirmNameInput() }
                        Button("Cancel", role: .cancel) { filesRoot.cancelNameInput() }
                    }
                    .sheet(item: $filesRoot.audioToEdit) { file in
                        EditRecordingView(recording: file) {
                            filesRoot.audioToEdit = nil
                            filesRoot.refreshFiles()
                        }
                    }
                    .sheet(isPresented: isCollectionPickerPresented) {
                        InAppCollectionPicker(
                            collections: filesRoot.availableCollections,
                            onPick: { filesRoot.moveToDestination($0) },
                            onCancel: { filesRoot.cancelMove() }
                        )
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
                    .navigationDestination(for: URL.self) { folderURL in
                        CollectionsView(
                            directory: folderURL,
                            onCollectionTapped: { app.path.append($0.url) },
                            onPlay: { file, queue, source in
                                player.loadTrack(file, queue: queue, source: source)
                            },
                            onWillRemoveItems: { items in
                                player.clearSessionIfAffected(by: items.map(\.url))
                            }
                        )
                        .navigationTitle(folderURL.lastPathComponent)
                        .navigationBarTitleDisplayMode(.large)
                    }
            }
            .preferredColorScheme(app.settings.colorScheme.colorScheme)

            // The mini-player is gone with Home. It existed to get you *back* to the player from
            // somewhere else, and there is no longer a somewhere else — the player is the root.

            // The record FAB is gone too. The dial carries Record as a section, and a floating
            // button over it would be a second door to the same room.
        }
        // Global sheets
        .sheet(isPresented: isRecordingSheetPresented) {
            RecordingView(viewModel: app.recording)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: isImportSheetPresented) {
            DocumentPicker { urls in
                app.isImportSheetPresented = false
                filesRoot.importFiles(urls)
            }
        }
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

    var isRecordingSheetPresented: Binding<Bool> {
        Binding(
            get: { app.isRecordingSheetPresented },
            set: { if !$0 { app.dismissRecordingSheet() } }
        )
    }

    var isRenaming: Binding<Bool> {
        Binding(
            get: { filesRoot.renamingItem != nil },
            set: { if !$0 { filesRoot.cancelNameInput() } }
        )
    }

    var isCollectionPickerPresented: Binding<Bool> {
        Binding(
            get: { filesRoot.isShowingCollectionPicker },
            set: { if !$0 { filesRoot.cancelMove() } }
        )
    }

    var isSettingsPresented: Binding<Bool> {
        Binding(
            get: { app.isSettingsPresented },
            set: { if !$0 { app.isSettingsPresented = false } }
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
            .onChange(of: app.recording.peakLevel) { _, _ in app.refreshDial() }
            // Pausing stops the meter, so `peakLevel` stops changing — without this the screen
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

    var homeRootContent: some View {
        ZStack {
            Color.sonicBackground.ignoresSafeArea()

            if filesRoot.isLoading && filesRoot.items.isEmpty {
                ProgressView()
                    .tint(.sonicPrimary)
            } else if filesRoot.items.isEmpty && home.allFiles.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: "waveform.circle")
                        .font(.system(size: 72))
                        .foregroundStyle(LinearGradient.sonicGradient)
                        .opacity(0.6)

                    Text("Welcome to SonicPlayer")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextPrimary)

                    Text("Record audio, import files, or open media\nfrom other apps to get started.")
                        .font(.subheadline)
                        .foregroundColor(.sonicTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    HStack(spacing: 12) {
                        Button {
                            app.isRecordingSheetPresented = true
                        } label: {
                            Label("Record", systemImage: "mic.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.red, in: Capsule())
                        }

                        Button {
                            home.onImportTapped()
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.sonicPrimary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.sonicPrimary.opacity(0.12), in: Capsule())
                        }
                    }
                    .padding(.top, 4)

                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // 1. Collections
                        collectionsSection

                        // 2. Recent Files
                        recentFilesSection
                    }
                    .padding(.vertical)
                    .padding(.bottom, player.shouldShowMiniPlayer ? 80 : 40)
                }
                .refreshable {
                    filesRoot.refreshFiles()
                    home.loadAllFiles()
                }
            }
        }
    }

    // MARK: - Section: Recent Files

    @ViewBuilder
    var recentFilesSection: some View {
        if !home.allFiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent Media")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "hand.draw")
                            .font(.caption2)
                        Text("Swipe for actions")
                            .font(.caption2)
                    }
                    .foregroundColor(.sonicTextMuted)
                }
                .padding(.horizontal)

                List {
                    ForEach(home.allFiles) { file in
                        recentFileRow(file: file)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    home.onDeleteFile(file)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    home.onRenameFile(file)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.sonicPrimary)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    home.onEditFile(file)
                                } label: {
                                    Label("Edit", systemImage: "waveform.and.magnifyingglass")
                                }
                                .tint(.blue)
                                Button {
                                    app.shareItem = ShareItem(url: file.url)
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .tint(.gray)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(home.allFiles.count) * Sizing.rowHeight)
            }
        }
    }

    /// Second consumer of the shared Row (#48). Home is the one place that shows *which*
    /// collection a file came from — the browser is already inside one.
    func recentFileRow(file: AudioFile) -> some View {
        SonicRow(
            leading: .tile(image: nil, side: Sizing.thumbnail, fallbackSystemImage: "waveform"),
            title: file.title,
            secondary: .durationDateAndCollection(
                file.durationFormatted,
                file.creationDate.formatted(date: .abbreviated, time: .omitted),
                CollectionLabel.name(for: file.url, documentsURL: home.documentsURL)
            )
        )
        .onTapGesture { home.fileTapped(file) }
    }

    // MARK: - Record FAB

    var recordFAB: some View {
        Button {
            app.isRecordingSheetPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.85), Color.red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.red.opacity(0.3), radius: 12, x: 0, y: 6)

                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundColor(.white)
            }
        }
    }
}
