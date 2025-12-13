import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: Binding(
                get: { store.selectedTab },
                set: { store.send(.selectTab($0)) }
            )) {
                HomeView(store: store.scope(state: \.home, action: \.home))
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(AppFeature.Tab.home)

                NavigationStack(path: $store.scope(state: \.filesPath, action: \.filesPath)) {
                    FilesView(store: store.scope(state: \.filesRoot, action: \.filesRoot))
                } destination: { store in
                    FilesView(store: store)
                }
                .tabItem {
                    Label("Library", systemImage: "square.stack.3d.up.fill")
                }
                .tag(AppFeature.Tab.files)

                SettingsView(store: store.scope(state: \.settings, action: \.settings))
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(AppFeature.Tab.settings)
            }
            .tint(.sonicPrimary)
            .preferredColorScheme(store.settings.colorScheme.colorScheme)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            // Mini Player Overlay
            if store.player.shouldShowMiniPlayer {
                MiniPlayerView(store: store.scope(state: \.player, action: \.player))
                    .padding(.bottom, 56) // Float above TabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .sheet(isPresented: Binding(
            get: { store.player.isExpanded },
            set: { store.send(.player(.setExpanded($0))) }
        )) {
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
