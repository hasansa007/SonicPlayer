import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            tabView
            .tint(.sonicPrimary)
            .preferredColorScheme(store.settings.colorScheme.colorScheme)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            // Mini Player Overlay (only in play mode)
            if isBrowsingMode && store.player.shouldShowMiniPlayer {
                MiniPlayerView(store: store.scope(state: \.player, action: \.player))
                    .padding(.bottom, 56) // Float above TabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .sheet(isPresented: isPlayerSheetPresented) {
            PlayerView(store: store.scope(state: \.player, action: \.player))
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .onChange(of: scenePhase) { _, newPhase in
            store.send(.scenePhaseChanged(newPhase))
        }
        .onAppear {
            store.send(.player(.restoreSession))
        }
    }
}

private extension AppView {
    var isBrowsingMode: Bool {
        !store.isRecordingMode
    }

    var selectedTab: Binding<AppFeature.Tab> {
        Binding(
            get: { store.selectedTab },
            set: { store.send(.selectTab($0)) }
        )
    }

    var isPlayerSheetPresented: Binding<Bool> {
        Binding(
            get: { isBrowsingMode && store.player.isExpanded },
            set: { store.send(.player(.setExpanded($0))) }
        )
    }

    var homeView: some View {
        HomeView(store: store.scope(state: \.home, action: \.home))
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppFeature.Tab.home)
    }

    var recordingView: some View {
        RecordingView(store: store.scope(state: \.recording, action: \.recording))
            .tabItem { Label("Recordings", systemImage: "mic.fill") }
            .tag(AppFeature.Tab.home)
    }

    var libraryView: some View {
        NavigationStack(path: $store.scope(state: \.filesPath, action: \.filesPath)) {
            FilesView(store: store.scope(state: \.filesRoot, action: \.filesRoot))
        } destination: { store in
            FilesView(store: store)
        }
        .tabItem { Label("Library", systemImage: "square.stack.3d.up.fill") }
        .tag(AppFeature.Tab.files)
    }

    var settingsView: some View {
        SettingsView(store: store.scope(state: \.settings, action: \.settings))
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(AppFeature.Tab.settings)
    }
    
    var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    @ViewBuilder
    var tabView: some View {
        let base = TabView(selection: selectedTab) {
            if isBrowsingMode {
                Tab("Home", systemImage: "house.fill", value: AppFeature.Tab.home) { homeView }
                Tab("Library", systemImage: "square.stack.3d.up.fill", value: AppFeature.Tab.files, role: .search) { libraryView }
            } else {
                Tab("Recordings", systemImage: "mic.fill", value: AppFeature.Tab.home) { recordingView }
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppFeature.Tab.settings) { settingsView }
        }

        if isPad {
            base.tabViewStyle(.sidebarAdaptable)
        } else {
            base
        }
    }
}
