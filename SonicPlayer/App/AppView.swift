import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            NavigationStack(path: $store.scope(state: \.filesPath, action: \.filesPath)) {
                homeRootContent
                    .navigationTitle("SonicPlayer")
                    .navigationBarTitleDisplayMode(.large)
                    .searchable(
                        text: Binding(
                            get: { store.filesRoot.searchText },
                            set: { store.send(.filesRoot(.setSearchText($0))) }
                        ),
                        placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Search media..."
                    )
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
                    .alert($store.scope(state: \.filesRoot.alert, action: \.filesRoot.alert))
                    .alert("New Collection", isPresented: Binding(
                        get: { store.filesRoot.isCreatingFolder },
                        set: { if !$0 { store.send(.filesRoot(.cancelNameInput)) } }
                    )) {
                        TextField("Name", text: Binding(
                            get: { store.filesRoot.inputText },
                            set: { store.send(.filesRoot(.setInputText($0))) }
                        ))
                        Button("Create") { store.send(.filesRoot(.confirmNameInput)) }
                        Button("Cancel", role: .cancel) { store.send(.filesRoot(.cancelNameInput)) }
                    }
                    .alert("Rename", isPresented: Binding(
                        get: { store.filesRoot.renamingItem != nil },
                        set: { if !$0 { store.send(.filesRoot(.cancelNameInput)) } }
                    )) {
                        TextField("Name", text: Binding(
                            get: { store.filesRoot.inputText },
                            set: { store.send(.filesRoot(.setInputText($0))) }
                        ))
                        Button("Rename") { store.send(.filesRoot(.confirmNameInput)) }
                        Button("Cancel", role: .cancel) { store.send(.filesRoot(.cancelNameInput)) }
                    }
                    .sheet(isPresented: Binding(
                        get: { store.filesRoot.isShowingFolderPicker },
                        set: { if !$0 { store.send(.filesRoot(.cancelMove)) } }
                    )) {
                        FolderPickerView(store: store.scope(state: \.filesRoot, action: \.filesRoot))
                    }
                    .sheet(item: $store.scope(state: \.filesRoot.editAudio, action: \.filesRoot.editAudio)) { editStore in
                        EditRecordingView(store: editStore)
                    }
                    .navigationDestination(isPresented: isSettingsPresented) {
                        SettingsView(store: store.scope(state: \.settings, action: \.settings))
                    }
                    .navigationDestination(isPresented: isAllRecentFilesPresented) {
                        allRecentFilesView
                    }
                    // All Collections presented via global sheet below
                    .onAppear {
                        store.send(.filesRoot(.onAppear))
                        store.send(.home(.loadRecentFiles))
                    }
            } destination: { filesStore in
                FilesView(store: filesStore)
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
            if !store.isSettingsSheetPresented && store.filesPath.isEmpty && !store.home.isShowingAllFolders && !store.home.isShowingAllRecentFiles && !(store.filesRoot.items.isEmpty && store.home.recentFiles.isEmpty) {
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
        .sheet(isPresented: isPlayerSheetPresented) {
            PlayerView(store: store.scope(state: \.player, action: \.player))
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: isRecordingSheetPresented) {
            RecordingView(store: store.scope(state: \.recording, action: \.recording))
                .presentationDetents([.large])
        }
        .sheet(isPresented: isImportSheetPresented) {
            DocumentPicker(
                contentTypes: [.item, .folder],
                asCopy: false,
                allowsMultipleSelection: true
            ) { urls in
                store.send(.importFiles(urls))
            }
        }
        .sheet(isPresented: isAllFoldersPresented) {
            AllCollectionsView(store: store)
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
    }
}

// MARK: - Private

private extension AppView {

    var isPlayerSheetPresented: Binding<Bool> {
        Binding(
            get: { store.player.isExpanded },
            set: { store.send(.player(.setExpanded($0))) }
        )
    }

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

    var isAllRecentFilesPresented: Binding<Bool> {
        Binding(
            get: { store.home.isShowingAllRecentFiles },
            set: { if !$0 { store.send(.home(.dismissAllRecentFiles)) } }
        )
    }

    var isAllFoldersPresented: Binding<Bool> {
        Binding(
            get: { store.home.isShowingAllFolders },
            set: { if !$0 { store.send(.home(.dismissAllFolders)) } }
        )
    }

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
                        // 1. Quick Actions
                        quickActionsSection

                        // 2. Collections
                        foldersSection

                        // 3. Recent Files (2 + View All)
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

    // MARK: - Section 2: Folders

    private static let folderGradients: [[Color]] = [
        [Color(hex: "1a3a5a"), Color(hex: "1B5B7E")],   // dark teal
        [Color(hex: "2a4a3a"), Color(hex: "1a6b4a")],    // dark green
        [Color(hex: "2e2a50"), Color(hex: "4a3a6e")],    // dark purple
        [Color(hex: "4a2a3a"), Color(hex: "6e3a4a")],    // dark rose
        [Color(hex: "4a3a1a"), Color(hex: "6e5a2a")],    // dark amber
    ]

    private static let folderIcons: [String] = [
        "waveform", "music.note.list", "mic.fill", "headphones", "square.stack.3d.up"
    ]

    @ViewBuilder
    var foldersSection: some View {
        let folderCards = store.filesRoot.filteredFolderCards
        if !folderCards.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Collections")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // First 2 folder cards
                        ForEach(Array(folderCards.prefix(2).enumerated()), id: \.element.id) { index, card in
                            folderCardView(folder: card.folder, index: index) {
                                store.send(.filesRoot(.folderCards(.element(id: card.id, action: .tapped))))
                            } onMove: {
                                store.send(.filesRoot(.folderCards(.element(id: card.id, action: .moveTapped))))
                            } onRename: {
                                store.send(.filesRoot(.folderCards(.element(id: card.id, action: .renameTapped))))
                            } onDelete: {
                                store.send(.filesRoot(.folderCards(.element(id: card.id, action: .deleteTapped))))
                            }
                        }

                        // "View All" dashed card (at end)
                        if folderCards.count > 2 {
                            Button {
                                store.send(.home(.viewAllFoldersTapped))
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "square.grid.2x2")
                                        .font(.title2)
                                        .foregroundColor(.sonicPrimary)

                                    Text("View All")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.sonicPrimary)
                                }
                                .frame(width: 120, height: 120)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.sonicPrimary.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(Color.sonicPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    func folderCardView(folder: Folder, index: Int, onTap: @escaping () -> Void, onMove: @escaping () -> Void, onRename: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        let colors = Self.folderGradients[index % Self.folderGradients.count]
        let icon = Self.folderIcons[index % Self.folderIcons.count]

        return Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: icon)
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.2))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 5)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: 0) {
                    Text(folder.name)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.caption2)
                        Text("\(folder.itemCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
                }
                .padding(14)
            }
            .frame(width: 180, height: 120)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onMove) { Label("Move", systemImage: "folder") }
            Button(action: onRename) { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - All Folders View

    var allFoldersView: some View {
        AllCollectionsView(store: store)
    }

    // MARK: - Section 3: Quick Actions

    var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    quickActionCard(
                        title: "Import Media",
                        icon: "square.and.arrow.down",
                        colors: [Color(hex: "1a3a5a"), Color(hex: "1B5B7E")]
                    ) {
                        store.send(.home(.importTapped))
                    }

                    quickActionCard(
                        title: "New Collection",
                        icon: "folder.badge.plus",
                        colors: [Color(hex: "2a4a3a"), Color(hex: "1a6b4a")]
                    ) {
                        store.send(.filesRoot(.createFolderTapped))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    func quickActionCard(title: LocalizedStringKey, icon: String, colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.2))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 5)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(14)
            }
            .frame(width: 160, height: 80)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 4: Recent Files (2 + View All)

    @ViewBuilder
    var recentFilesSection: some View {
        if !store.home.recentFiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent Media")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    if store.home.recentFiles.count > 2 {
                        Button {
                            store.send(.home(.viewAllRecentFilesTapped))
                        } label: {
                            Text("View All")
                                .font(.subheadline)
                                .foregroundColor(.sonicPrimary)
                        }
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(store.home.recentFiles.prefix(2)) { file in
                        recentFileRow(file: file)

                        if file.id != store.home.recentFiles.prefix(2).last?.id {
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

    // MARK: - View All Recent Files

    var allRecentFilesView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.home.recentFiles) { file in
                    recentFileRow(file: file)

                    if file.id != store.home.recentFiles.last?.id {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color.sonicBackground.ignoresSafeArea())
        .navigationTitle("Recent Media")
        .navigationBarTitleDisplayMode(.inline)
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
