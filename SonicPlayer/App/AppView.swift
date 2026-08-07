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
    @State var home: HomeViewModel
    @State private var recording = RecordingViewModel()

    // The root file browser, and the navigation path below it (#18). The root model is held here
    // rather than inside a CollectionsView because Home's swipe actions act on it — Home's UI is
    // inlined into this file and has no browser screen of its own to talk to.
    @State var filesRoot = CollectionsViewModel(currentDirectory: nil)
    @State var path: [URL] = []

    init(store: StoreOf<AppFeature>) {
        self.store = store
        let player = PlayerViewModel()
        _player = State(initialValue: player)
        _home = State(initialValue: HomeViewModel(player: player))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            NavigationStack(path: $path) {
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
                    .sheet(item: $shareItem) { item in
                        ActivityView(items: [item.url])
                    }
                    .onAppear {
                        if !ScreenshotMode.isEnabled {
                            filesRoot.onAppear()
                            home.loadRecentFiles()
                        }
                    }
                    .navigationDestination(for: URL.self) { folderURL in
                        CollectionsView(
                            directory: folderURL,
                            onCollectionTapped: { path.append($0.url) },
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
            if !store.isSettingsSheetPresented && path.isEmpty && !(filesRoot.items.isEmpty && home.recentFiles.isEmpty) {
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
                store.send(.dismissImportSheet)
                filesRoot.importFiles(urls)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            player.scenePhaseChanged(newPhase)
        }
        .onOpenURL { url in
            openedFromFiles(url)
        }
        .onAppear {
            wireViewModels()
            if ScreenshotMode.isEnabled {
                if let screen = ScreenshotMode.targetScreen {
                    ScreenshotDemoData.seedViewModels(player: player, home: home, filesRoot: filesRoot, for: screen)
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
        // Home's former `.none // Handled by parent` cases. These used to be store actions that
        // poked `filesRoot` state; they are method calls on the root browser now.
        home.onImportTapped = { store.send(.importTapped) }
        home.onNewCollectionTapped = { filesRoot.createCollectionTapped() }
        home.onViewAllCollectionsTapped = { path.append(filesRoot.documentsDirectoryURL ?? URL(fileURLWithPath: NSHomeDirectory())) }
        home.onRenameFile = { filesRoot.renameItemTapped(.file($0)) }
        home.onDeleteFile = {
            filesRoot.select(.file($0))
            filesRoot.deleteSelectedTapped()
        }
        home.onEditFile = { filesRoot.audioToEdit = $0 }
        home.onMoveFile = { filesRoot.presentPicker(moving: [.file($0)]) }

        // Formerly AppFeature observing `.recording(.recordingSaved)` / `.discardRecording`.
        recording.onFinished = {
            store.send(.dismissRecordingSheet)
            filesRoot.refreshFiles()
            home.loadRecentFiles()
        }

        // The root browser's out-edges. These are what the AppCommand channel used to carry.
        filesRoot.onCollectionTapped = { path.append($0.url) }
        filesRoot.onPlay = { file, queue, source in
            player.loadTrack(file, queue: queue, source: source)
        }
        filesRoot.onWillRemoveItems = { items in
            player.clearSessionIfAffected(by: items.map(\.url))
        }
        // Any reload of the root browser refreshes Home's recents, which are drawn from it.
        filesRoot.onItemsLoaded = { home.loadRecentFiles() }
    }

    /// Import a file handed over by another app, then play it.
    ///
    /// Was `AppFeature.openedFromFiles`. Unchanged apart from where it lives — including that it
    /// resolves the played file from a path computed before the import runs, which is #33.
    func openedFromFiles(_ url: URL) {
        Task {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let dest = docs.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: url, to: dest)
            }
            filesRoot.refreshFiles()

            if let file = try? await FileManagerClient.live.getMetadata(dest) {
                player.loadTrack(file, queue: [file], source: .singleFile)
            }
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

            if filesRoot.isLoading && filesRoot.items.isEmpty {
                ProgressView()
                    .tint(.sonicPrimary)
            } else if filesRoot.items.isEmpty && home.recentFiles.isEmpty {
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
                    filesRoot.refreshFiles()
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
