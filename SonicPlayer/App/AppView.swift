import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenQuickstart") private var hasSeenQuickstart = false

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
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenQuickstart },
            set: { _ in }
        )) {
            QuickstartView(hasSeenQuickstart: $hasSeenQuickstart)
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
        HomeView(
            store: store.scope(state: \.home, action: \.home),
            isRecordingMode: store.isRecordingMode,
            canSwitchMode: !store.recording.isRecording,
            onToggleMode: { store.send(.settings(.toggleRecordingMode)) }
        )
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(AppFeature.Tab.home)
    }

    var recordingView: some View {
        RecordingView(
            store: store.scope(state: \.recording, action: \.recording),
            isRecordingMode: store.isRecordingMode,
            canSwitchMode: !store.recording.isRecording,
            onToggleMode: { store.send(.settings(.toggleRecordingMode)) }
        )
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

struct QuickstartView: View {
    @Binding var hasSeenQuickstart: Bool
    @State private var selection = 0

    private let pages: [QuickstartPageModel] = [
        QuickstartPageModel(
            title: "Home",
            message: "Jump to Library or Recording and tap any item to start playback instantly.",
            systemImage: "house.fill",
            colors: Color.sonicTealColors,
            demo: .home,
            actions: [
                QuickstartAction(title: "Go to Library", systemImage: "square.stack.3d.up.fill"),
                QuickstartAction(title: "Go to Recording", systemImage: "mic.fill"),
                QuickstartAction(title: "Tap item to play", systemImage: "play.fill")
            ]
        ),
        QuickstartPageModel(
            title: "Library",
            message: "Tap the + button to import files or folders and keep everything organized.",
            systemImage: "square.stack.3d.up.fill",
            colors: Color.sonicBlueColors,
            demo: .library,
            actions: [
                QuickstartAction(title: "Import files or folders", systemImage: "square.and.arrow.down"),
                QuickstartAction(title: "New Folder", systemImage: "folder.badge.plus")
            ]
        ),
        QuickstartPageModel(
            title: "Recording",
            message: "Switch to Recording Mode and capture audio. Start, pause, and stop, then trim takes.",
            systemImage: "mic.fill",
            colors: Color.sonicOrangeColors,
            demo: .recording,
            actions: [
                QuickstartAction(title: "Start recording", systemImage: "record.circle"),
                QuickstartAction(title: "Stop recording", systemImage: "stop.fill"),
                QuickstartAction(title: "Trim takes", systemImage: "scissors")
            ]
        ),
        QuickstartPageModel(
            title: "Settings",
            message: "Tune playback speed, skip duration, and appearance. Replay this quickstart any time.",
            systemImage: "gearshape.fill",
            colors: Color.sonicGreenColors,
            demo: .settings,
            actions: [
                QuickstartAction(title: "Playback speed", systemImage: "speedometer"),
                QuickstartAction(title: "Skip duration", systemImage: "arrow.left.arrow.right"),
                QuickstartAction(title: "Theme", systemImage: "paintbrush.fill")
            ]
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient.sonic(colors: [Color.sonicBackground, Color.sonicSurface])
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button("Skip") {
                        hasSeenQuickstart = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.sonicTextSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                TabView(selection: $selection) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        QuickstartPage(model: page)
                            .tag(index)
                            .padding(.horizontal, 24)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                QuickstartPageControl(count: pages.count, selection: selection)
                    .padding(.top, 6)
                    .padding(.bottom, 6)

                Button {
                    if selection < pages.count - 1 {
                        withAnimation(.easeInOut) {
                            selection += 1
                        }
                    } else {
                        hasSeenQuickstart = true
                    }
                } label: {
                    Text(selection < pages.count - 1 ? "Next" : "Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .sonicGradientBackground(colors: Color.sonicTealColors, cornerRadius: 18)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

struct QuickstartPageModel {
    let title: String
    let message: String
    let systemImage: String
    let colors: [Color]
    let demo: QuickstartDemo
    let actions: [QuickstartAction]
}

struct QuickstartPageControl: View {
    let count: Int
    let selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == selection ? Color.sonicPrimary : Color.sonicBorder)
                    .frame(width: index == selection ? 8 : 6, height: index == selection ? 8 : 6)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selection)
        .accessibilityLabel("Page \(selection + 1) of \(count)")
    }
}

struct QuickstartPage: View {
    let model: QuickstartPageModel
    @State private var animate = false
    @State private var pulse = false
    private let demoHeight: CGFloat = 170
    private let actionsHeight: CGFloat = 110

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(LinearGradient.sonic(colors: model.colors))
                    .frame(width: 105, height: 105)
                    .opacity(0.25)
                    .scaleEffect(animate ? 1.05 : 0.92)

                Circle()
                    .stroke(LinearGradient.sonic(colors: model.colors), lineWidth: 2)
                    .frame(width: 110, height: 110)
                    .opacity(animate ? 0.2 : 0.6)
                    .scaleEffect(animate ? 1.08 : 0.95)

                Image(systemName: model.systemImage)
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(LinearGradient.sonic(colors: model.colors))
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
            }
            
            QuickstartDemoView(demo: model.demo, colors: model.colors)
                .frame(height: demoHeight)


            Text(model.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.sonicTextPrimary)
                .multilineTextAlignment(.center)

            Text(model.message)
                .font(.body)
                .foregroundColor(.sonicTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            QuickstartActionsView(actions: model.actions, colors: model.colors)
                .frame(height: actionsHeight)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                animate = true
            }
            if model.demo == .recording || model.demo == .library {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

enum QuickstartDemo {
    case home
    case library
    case recording
    case settings
}

struct QuickstartDemoView: View {
    let demo: QuickstartDemo
    let colors: [Color]
    @State private var pulse = false

    private var title: String {
        switch demo {
        case .home:
            return "Home"
        case .library:
            return "Library"
        case .recording:
            return "Recording"
        case .settings:
            return "Settings"
        }
    }

    private var subtitle: String {
        switch demo {
        case .home:
            return "Suggested folders + last played"
        case .library:
            return "Browse folders and import"
        case .recording:
            return "Waveform + trim tools"
        case .settings:
            return "Playback + theme"
        }
    }

    private var highlightIcon: String {
        switch demo {
        case .home:
            return "play.fill"
        case .library:
            return "plus"
        case .recording:
            return "record.circle"
        case .settings:
            return "slider.horizontal.3"
        }
    }

    private var tabIcon: String {
        switch demo {
        case .home:
            return "house.fill"
        case .library:
            return "square.stack.3d.up.fill"
        case .recording:
            return "mic.fill"
        case .settings:
            return "gearshape.fill"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextPrimary)
                    Spacer()
                    ZStack {
                        Image(systemName: highlightIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LinearGradient.sonic(colors: colors))
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())

                        if demo == .library || demo == .recording {
                            Circle()
                                .stroke(LinearGradient.sonic(colors: colors), lineWidth: 1.5)
                                .frame(width: 30, height: 30)
                                .scaleEffect(pulse ? 1.5 : 0.9)
                                .opacity(pulse ? 0.0 : 0.5)
                        }
                    }
                }

                demoContent
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient.sonic(colors: colors.map { $0.opacity(0.12) }))
            )

            HStack(spacing: 6) {
                Image(systemName: tabIcon)
                    .font(.caption2)
                    .foregroundColor(.sonicTextSecondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if demo == .library || demo == .recording {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
    }

    @ViewBuilder
    private var demoContent: some View {
        switch demo {
        case .home:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    demoPill(text: "Library", icon: "square.stack.3d.up.fill", fill: colors)
                    demoPill(text: "Recording", icon: "mic.fill", fill: colors.reversed())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.sonicSurface)
                    .frame(height: 60)
                    .overlay(
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundColor(.sonicPrimary)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder)
                                    .frame(width: 150, height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder.opacity(0.8))
                                    .frame(width: 110, height: 6)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    )
            }
        case .library:
            VStack(spacing: 10) {
                HStack {
                    demoPill(text: "Import", icon: "square.and.arrow.down", fill: colors)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.sonicPrimary)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                }

                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.sonicSurface)
                    .frame(height: 60)
                    .overlay(
                        HStack(spacing: 10) {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundColor(.sonicPrimary)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder)
                                    .frame(width: 140, height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder.opacity(0.8))
                                    .frame(width: 90, height: 6)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    )
            }
        case .recording:
            VStack(spacing: 12) {
                HStack {
                    Text("00:12.48")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextSecondary)
                    Spacer()
                    demoPill(text: "Stop", icon: "stop.fill", fill: [Color.red, Color.red.opacity(0.8)])
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(0.5), lineWidth: 6)
                                .scaleEffect(pulse ? 1.4 : 0.8)
                                .opacity(pulse ? 0.0 : 0.8)
                        )

                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.sonicSurface)
                        .frame(height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.sonicBorder.opacity(0.6))
                                .frame(width: 160, height: 10),
                            alignment: .leading
                        )
                }
            }
        case .settings:
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.sonicSurface)
                    .frame(height: 54)
                    .overlay(
                        HStack(spacing: 10) {
                            Image(systemName: "speedometer")
                                .font(.caption)
                                .foregroundColor(.sonicPrimary)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder)
                                    .frame(width: 140, height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.sonicBorder.opacity(0.8))
                                    .frame(width: 100, height: 6)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    )
            }
        }
    }

    private func demoPill(text: String, icon: String, fill: [Color]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.sonicTextPrimary)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(LinearGradient.sonic(colors: fill.map { $0.opacity(0.18) }), in: Capsule())
    }
}

struct QuickstartAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
}

struct QuickstartActionsView: View {
    let actions: [QuickstartAction]
    let colors: [Color]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(actions) { action in
                HStack(spacing: 8) {
                    Image(systemName: action.systemImage)
                        .font(.caption)
                        .foregroundStyle(LinearGradient.sonic(colors: colors))
                    Text(action.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextPrimary)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
