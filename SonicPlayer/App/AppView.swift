import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var shareItem: ShareItem?

    // Settings and onboarding are @Observable view models rather than reducers (#13, #14).
    // They live here because AppFeature's State is a value type and cannot hold a reference.
    @State private var settingsViewModel: SettingsViewModel = SettingsViewModel()
    @State private var onboardingViewModel: OnboardingViewModel? = OnboardingViewModel.ifNeeded()

    // Player and Home join them (#15, #16). Home holds the *same* PlayerViewModel instance, which
    // is what let `HomeFeature`'s three mirrored playback properties be deleted rather than ported
    // — so they are built together here, not independently.
    @State private var player: PlayerViewModel
    @State private var home: HomeViewModel
    @State private var recording = RecordingViewModel()

    init(store: StoreOf<AppFeature>) {
        self.store = store
        let player = PlayerViewModel()
        _player = State(initialValue: player)
        _home = State(initialValue: HomeViewModel(player: player))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            NavigationStack(path: $store.scope(state: \.filesPath, action: \.filesPath)) {
                homeRootContent
                    .navigationTitle("Home")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                store.send(.settingsTapped)
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .foregroundColor(.sonicTextSecondary)
                            }
                        }
                    }
                    .navigationDestination(isPresented: isSettingsPresented) {
                        SettingsView(viewModel: settingsViewModel)
                    }
                    .alert($store.scope(state: \.filesRoot.alert, action: \.filesRoot.alert))
                    .alert("Rename", isPresented: isRenaming) {
                        TextField("Name", text: renameText)
                        Button("Rename") { store.send(.filesRoot(.confirmNameInput)) }
                        Button("Cancel", role: .cancel) { store.send(.filesRoot(.cancelNameInput)) }
                    }
                    .sheet(item: Binding(
                        get: { store.filesRoot.audioToEdit },
                        set: { if $0 == nil { store.send(.filesRoot(.editAudioDismissed)) } }
                    )) { file in
                        EditRecordingView(recording: file) {
                            store.send(.filesRoot(.editAudioDismissed))
                        }
                    }
                    .sheet(isPresented: isCollectionPickerPresented) {
                        InAppCollectionPicker(
                            collections: store.filesRoot.availableCollections,
                            onPick: { url in store.send(.filesRoot(.moveToDestination(url))) },
                            onCancel: { store.send(.filesRoot(.cancelMove)) }
                        )
                    }
                    .sheet(item: $shareItem) { item in
                        ActivityView(items: [item.url])
                    }
                    .onAppear {
                        if !ScreenshotMode.isEnabled {
                            store.send(.filesRoot(.onAppear))
                            home.loadRecentFiles()
                        }
                    }
            } destination: { collectionsStore in
                CollectionsView(store: collectionsStore)
                    .navigationTitle(collectionsStore.currentDirectory?.lastPathComponent ?? "Collections")
                    .navigationBarTitleDisplayMode(.large)
            }
            .preferredColorScheme(settingsViewModel.colorScheme.colorScheme)

            // Mini Player (full-width bottom bar)
            if player.shouldShowMiniPlayer {
                VStack(spacing: 0) {
                    Spacer()
                    MiniPlayerView(player: player)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }

            // Record FAB (home screen only, not on empty state)
            if !store.isSettingsSheetPresented && store.filesPath.isEmpty && !(store.filesRoot.items.isEmpty && home.recentFiles.isEmpty) {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        recordFAB
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, player.shouldShowMiniPlayer ? 72 : 20)
                .zIndex(2)
            }
        }
        // Global sheets
        .sheet(isPresented: $player.isExpanded) {
            PlayerView(player: player)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: isRecordingSheetPresented) {
            RecordingView(viewModel: recording)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: isImportSheetPresented) {
            DocumentPicker { urls in
                store.send(.importFiles(urls))
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            player.scenePhaseChanged(newPhase)
        }
        .onChange(of: store.commands) { _, commands in
            guard !commands.isEmpty else { return }
            commands.forEach(apply)
            store.send(.commandsHandled)
        }
        .onOpenURL { url in
            store.send(.openedFromFiles(url))
        }
        .onAppear {
            wireViewModels()
            if ScreenshotMode.isEnabled {
                if let screen = ScreenshotMode.targetScreen {
                    ScreenshotDemoData.seedViewModels(player: player, home: home, for: screen)
                }
                // In screenshot mode, show recording sheet if needed
                if ScreenshotMode.targetScreen == .recording || ScreenshotMode.targetScreen == .editRecording {
                    store.send(.recordButtonTapped)
                }
            } else {
                player.restoreSession()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { onboardingViewModel != nil },
            set: { _ in }
        )) {
            if let onboardingViewModel {
                OnboardingView(viewModel: onboardingViewModel)
            }
        }
    }
}

// MARK: - Private

private extension AppView {

    /// Replaces the cross-feature action taps AppFeature used to carry: settings changes
    /// reaching the player, and onboarding completion clearing itself.
    func wireViewModels() {
        settingsViewModel.onDefaultPlaybackSpeedChanged = { [player] speed in
            player.setPlaybackSpeed(speed)
        }
        settingsViewModel.onDefaultSkipDurationChanged = { [player] duration in
            player.setSkipDuration(duration)
        }
        onboardingViewModel?.onGetStarted = {
            OnboardingViewModel.markSeen()
            onboardingViewModel = nil
        }

        // Home's former `.none // Handled by parent` cases. Each needs reducer state — the file
        // browser's selection, the navigation stack, a sheet flag — so each lands back on the
        // store rather than being reimplemented on the view model.
        home.onImportTapped = { store.send(.importTapped) }
        home.onNewCollectionTapped = { store.send(.filesRoot(.createCollectionTapped)) }
        home.onViewAllCollectionsTapped = { store.send(.viewAllCollectionsTapped) }
        home.onRenameFile = { store.send(.filesRoot(.renameItemTapped(.file($0)))) }
        home.onDeleteFile = { store.send(.deleteRecentFile($0)) }
        home.onEditFile = { store.send(.editRecentFile($0)) }
        home.onMoveFile = { store.send(.moveRecentFile($0)) }

        // Formerly AppFeature observing `.recording(.recordingSaved)` / `.discardRecording`.
        recording.onFinished = { store.send(.dismissRecordingSheet) }
    }

    /// Drains `AppFeature.State.commands`. Temporary — see the doc comment there; #19 replaces the
    /// channel with a coordinator that holds the view models directly.
    func apply(_ command: AppFeature.AppCommand) {
        switch command {
        case let .play(file, queue, source):
            player.loadTrack(file, queue: queue, source: source)
        case .pauseIfPlaying:
            player.pauseIfPlaying()
        case let .clearSessionIfAffected(urls):
            player.clearSessionIfAffected(by: urls)
        case .refreshRecents:
            home.loadRecentFiles()
        }
    }

    var isRecordingSheetPresented: Binding<Bool> {
        Binding(
            get: { store.isRecordingSheetPresented },
            set: {
                if !$0 {
                    recording.discardIfUnsaved()
                    store.send(.dismissRecordingSheet)
                }
            }
        )
    }

    var isRenaming: Binding<Bool> {
        Binding(
            get: { store.filesRoot.renamingItem != nil },
            set: { if !$0 { store.send(.filesRoot(.cancelNameInput)) } }
        )
    }

    var renameText: Binding<String> {
        Binding(
            get: { store.filesRoot.inputText },
            set: { store.send(.filesRoot(.setInputText($0))) }
        )
    }

    var isCollectionPickerPresented: Binding<Bool> {
        Binding(
            get: { store.filesRoot.isShowingCollectionPicker },
            set: { if !$0 { store.send(.filesRoot(.cancelMove)) } }
        )
    }

    var isSettingsPresented: Binding<Bool> {
        Binding(
            get: { store.isSettingsSheetPresented },
            set: { if !$0 { store.send(.dismissSettings) } }
        )
    }

    var isImportSheetPresented: Binding<Bool> {
        Binding(
            get: { store.isImportSheetPresented },
            set: { if !$0 { store.send(.dismissImportSheet) } }
        )
    }


    // MARK: - Expanded Player Overlay

    // MARK: - Home Root Content

    @ViewBuilder
    var homeRootContent: some View {
        ZStack {
            Color.sonicBackground.ignoresSafeArea()

            if store.filesRoot.isLoading && store.filesRoot.items.isEmpty {
                ProgressView()
                    .tint(.sonicPrimary)
            } else if store.filesRoot.items.isEmpty && home.recentFiles.isEmpty {
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
                            store.send(.recordButtonTapped)
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
                    await store.send(.filesRoot(.refreshFiles)).finish()
                    home.loadRecentFiles()
                }
            }
        }
    }

    // MARK: - Section: Recent Files

    @ViewBuilder
    var recentFilesSection: some View {
        if !home.recentFiles.isEmpty {
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
                    ForEach(home.recentFiles) { file in
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
                                    shareItem = ShareItem(url: file.url)
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
                .frame(height: CGFloat(home.recentFiles.count) * 64)
            }
        }
    }

    func recentFileRow(file: AudioFile) -> some View {
        MediaFileRowView(
            file: file,
            onTap: { home.fileTapped(file) }
        )
    }

    // MARK: - Record FAB

    var recordFAB: some View {
        Button {
            store.send(.recordButtonTapped)
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
