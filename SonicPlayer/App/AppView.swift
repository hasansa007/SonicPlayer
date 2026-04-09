import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            NavigationStack(path: $store.scope(state: \.filesPath, action: \.filesPath)) {
                Group {
                    if store.home.isShowingAllCollections {
                        CollectionsView(
                            store: store.scope(state: \.filesRoot, action: \.filesRoot),
                            onDismiss: { store.send(.home(.dismissAllCollections)) }
                        )
                    } else {
                        homeRootContent
                    }
                }
                .navigationTitle(store.home.isShowingAllCollections ? "Collections" : "Home")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if !store.home.isShowingAllCollections {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                store.send(.settingsTapped)
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .foregroundColor(.sonicTextSecondary)
                            }
                        }
                    }
                }
                .navigationDestination(isPresented: isSettingsPresented) {
                    SettingsView(store: store.scope(state: \.settings, action: \.settings))
                }
                .onAppear {
                    store.send(.filesRoot(.onAppear))
                    store.send(.home(.loadRecentFiles))
                }
            } destination: { collectionsStore in
                CollectionsView(store: collectionsStore)
                    .navigationTitle(collectionsStore.currentDirectory?.lastPathComponent ?? "Library")
                    .navigationBarTitleDisplayMode(.large)
            }
            .preferredColorScheme(store.settings.colorScheme.colorScheme)

            // Mini Player (full-width bottom bar)
            if store.player.shouldShowMiniPlayer {
                VStack(spacing: 0) {
                    Spacer()
                    MiniPlayerView(store: store.scope(state: \.player, action: \.player))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }

            // Record FAB (home screen only, not on empty state)
            if !store.isSettingsSheetPresented && store.filesPath.isEmpty && !store.home.isShowingAllCollections && !(store.filesRoot.items.isEmpty && store.home.recentFiles.isEmpty) {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        recordFAB
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, store.player.shouldShowMiniPlayer ? 72 : 20)
                .zIndex(2)
            }
        }
        // Global sheets
        .sheet(isPresented: Binding(
            get: { store.player.isExpanded },
            set: { store.send(.player(.setExpanded($0))) }
        )) {
            PlayerView(store: store.scope(state: \.player, action: \.player))
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: isRecordingSheetPresented) {
            RecordingView(store: store.scope(state: \.recording, action: \.recording))
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(store.recording.isRecording)
        }
        .sheet(isPresented: isImportSheetPresented) {
            DocumentPicker { urls in
                store.send(.importFiles(urls))
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            store.send(.scenePhaseChanged(newPhase))
        }
        .onOpenURL { url in
            store.send(.openedFromFiles(url))
        }
        .onAppear {
            store.send(.player(.restoreSession))
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.onboarding != nil },
            set: { _ in }
        )) {
            if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                OnboardingView(store: onboardingStore)
            }
        }
    }
}

// MARK: - Private

private extension AppView {

    var isRecordingSheetPresented: Binding<Bool> {
        Binding(
            get: { store.isRecordingSheetPresented },
            set: { if !$0 { store.send(.dismissRecordingSheet) } }
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
            } else if store.filesRoot.items.isEmpty && store.home.recentFiles.isEmpty {
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
                            store.send(.home(.importTapped))
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
                    .padding(.bottom, store.player.shouldShowMiniPlayer ? 80 : 40)
                }
                .refreshable {
                    await store.send(.filesRoot(.refreshFiles)).finish()
                    store.send(.home(.loadRecentFiles))
                }
            }
        }
    }

    // MARK: - Section: Recent Files

    @ViewBuilder
    var recentFilesSection: some View {
        if !store.home.recentFiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Media")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(store.home.recentFiles) { file in
                        recentFileRow(file: file)

                        if file.id != store.home.recentFiles.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }

    func recentFileRow(file: AudioFile) -> some View {
        Button {
            store.send(.home(.fileTapped(file)))
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient.sonicGradient)
                        .frame(width: 40, height: 40)

                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.title)
                        .font(.body)
                        .foregroundColor(.sonicTextPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(file.durationFormatted)
                        Text("·")
                        Text(file.creationDate, style: .date)
                    }
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
                }

                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
