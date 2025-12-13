import ComposableArchitecture
import SwiftUI

struct SettingsView: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sonicBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // App branding
                        appHeaderView

                        // Playback settings
                        playbackSettingsSection

                        // Appearance settings
                        appearanceSection

                        // About & Help
                        infoSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 80) // Add bottom padding for Mini Player
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: Binding(
                get: { store.showAbout },
                set: { _ in store.send(.dismissAbout) }
            )) {
                AboutView(store: store)
            }
            .sheet(isPresented: Binding(
                get: { store.showHelp },
                set: { _ in store.send(.dismissHelp) }
            )) {
                HelpView(store: store)
            }
        }
    }

    private var appHeaderView: some View {
        VStack(spacing: 16) {
            // Logo
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22.5))
                .shadow(color: Color.sonicPrimary.opacity(0.4), radius: 20, x: 0, y: 10)

            VStack(spacing: 4) {
                Text("SonicPlayer")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(LinearGradient.sonicGradient)

                Text("v1.0.0")
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
            }
        }
        .padding(.vertical, 20)
    }

    private var playbackSettingsSection: some View {
        SettingsSection(title: "Playback", icon: "play.circle.fill") {
            VStack(spacing: 12) {
                // Default playback speed
                SettingsRow(
                    icon: "speedometer",
                    title: "Default Speed",
                    iconColor: .sonicPrimary
                ) {
                    Menu {
                        ForEach(PlaybackSpeed.allCases) { speed in
                            Button {
                                store.send(.setDefaultPlaybackSpeed(speed))
                            } label: {
                                HStack {
                                    Text(speed.displayText)
                                    if speed == store.defaultPlaybackSpeed {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(store.defaultPlaybackSpeed.displayText)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.sonicPrimary)
                                .monospacedDigit()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundColor(.sonicTextMuted)
                        }
                    }
                }

                Divider()

                // Default skip duration
                SettingsRow(
                    icon: "arrow.left.arrow.right",
                    title: "Skip Duration",
                    iconColor: .sonicPrimary
                ) {
                    Menu {
                        ForEach(SkipDuration.allCases) { duration in
                            Button {
                                store.send(.setDefaultSkipDuration(duration))
                            } label: {
                                HStack {
                                    Text(duration.displayText)
                                    if duration == store.defaultSkipDuration {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(store.defaultSkipDuration.displayText)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.sonicPrimary)
                                .monospacedDigit()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundColor(.sonicTextMuted)
                        }
                    }
                }
            }
        }
    }

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance", icon: "paintbrush.fill") {
            SettingsRow(
                icon: store.colorScheme.icon,
                title: "Theme",
                iconColor: .orange
            ) {
                Menu {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Button {
                            store.send(.setColorScheme(scheme))
                        } label: {
                            HStack {
                                Image(systemName: scheme.icon)
                                Text(scheme.rawValue)
                                if scheme == store.colorScheme {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(store.colorScheme.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.sonicPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(.sonicTextMuted)
                    }
                }
            }
        }
    }

    private var infoSection: some View {
        SettingsSection(title: "Information", icon: "info.circle.fill") {
            VStack(spacing: 12) {
                SettingsButton(
                    icon: "info.circle",
                    title: "About SonicPlayer",
                    iconColor: .blue
                ) {
                    store.send(.showAboutTapped)
                }

                Divider()

                SettingsButton(
                    icon: "questionmark.circle",
                    title: "Help & Support",
                    iconColor: .green
                ) {
                    store.send(.showHelpTapped)
                }
            }
        }
    }
}

// MARK: - Settings Components

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.sonicPrimary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicTextSecondary)
                    .textCase(.uppercase)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct SettingsRow<Content: View>: View {
    let icon: String
    let title: String
    let iconColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(iconColor)
                    .frame(width: 24)

                Text(title)
                    .font(.body)
                    .foregroundColor(.sonicTextPrimary)
            }

            Spacer()

            content
        }
    }
}

struct SettingsButton: View {
    let icon: String
    let title: String
    let iconColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundColor(iconColor)
                        .frame(width: 24)

                    Text(title)
                        .font(.body)
                        .foregroundColor(.sonicTextPrimary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicTextMuted)
            }
        }
    }
}
