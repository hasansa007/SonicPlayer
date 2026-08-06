import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.systemID
    private let supportedLanguages = AppLanguage.supportedLanguages
    @State private var expandedSection: ExpandableSection?

    private enum ExpandableSection {
        case speed, skipDuration, theme, language
    }

    var body: some View {
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
                .padding(.bottom, 80)
            }
        }
        .navigationTitle("Settings")
        .navigationDestination(isPresented: Binding(
            get: { viewModel.showAbout },
            set: { _ in viewModel.dismissAbout() }
        )) {
            AboutView(viewModel: viewModel)
        }
        .navigationDestination(isPresented: Binding(
            get: { viewModel.showHelp },
            set: { _ in viewModel.dismissHelp() }
        )) {
            HelpView(viewModel: viewModel)
        }
    }

    private var appHeaderView: some View {
        VStack(spacing: 16) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22.5))
                .shadow(color: Color.sonicPrimary.opacity(0.4), radius: 20, x: 0, y: 10)

            VStack(spacing: 4) {
                Text("Sonic Player")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(LinearGradient.sonicGradient)

                Text("v\(appShortVersion)")
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
            }
        }
        .padding(.vertical, 20)
    }

    private var appShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var playbackSettingsSection: some View {
        SettingsSection(title: "Playback", icon: "play.circle.fill") {
            VStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expandedSection = expandedSection == .speed ? nil : .speed
                    }
                } label: {
                    SettingsRow(
                        icon: "speedometer",
                        title: "Default Speed",
                        iconColor: .sonicPrimary
                    ) {
                        HStack(spacing: 4) {
                            Text(viewModel.defaultPlaybackSpeed.displayText)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.sonicPrimary)
                                .monospacedDigit()
                            Image(systemName: expandedSection == .speed ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.sonicTextMuted)
                        }
                    }
                }
                .buttonStyle(.plain)

                if expandedSection == .speed {
                    VStack(spacing: 0) {
                        ForEach(PlaybackSpeed.allCases) { speed in
                            Button {
                                viewModel.setDefaultPlaybackSpeed(speed)
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    expandedSection = nil
                                }
                            } label: {
                                HStack {
                                    Text(speed.displayText)
                                        .font(.subheadline)
                                        .foregroundColor(.sonicTextPrimary)
                                    Spacer()
                                    if speed == viewModel.defaultPlaybackSpeed {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundColor(.sonicPrimary)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 36)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expandedSection = expandedSection == .skipDuration ? nil : .skipDuration
                    }
                } label: {
                    SettingsRow(
                        icon: "arrow.left.arrow.right",
                        title: "Skip Duration",
                        iconColor: .sonicPrimary
                    ) {
                        HStack(spacing: 4) {
                            Text(viewModel.defaultSkipDuration.displayText)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.sonicPrimary)
                                .monospacedDigit()
                            Image(systemName: expandedSection == .skipDuration ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.sonicTextMuted)
                        }
                    }
                }
                .buttonStyle(.plain)

                if expandedSection == .skipDuration {
                    VStack(spacing: 0) {
                        ForEach(SkipDuration.allCases) { duration in
                            Button {
                                viewModel.setDefaultSkipDuration(duration)
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    expandedSection = nil
                                }
                            } label: {
                                HStack {
                                    Text(duration.displayText)
                                        .font(.subheadline)
                                        .foregroundColor(.sonicTextPrimary)
                                    Spacer()
                                    if duration == viewModel.defaultSkipDuration {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundColor(.sonicPrimary)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 36)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance", icon: "paintbrush.fill") {
            VStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expandedSection = expandedSection == .theme ? nil : .theme
                    }
                } label: {
                    SettingsRow(
                        icon: viewModel.colorScheme.icon,
                        title: "Theme",
                        iconColor: .orange
                    ) {
                        HStack(spacing: 4) {
                            Text(viewModel.colorScheme.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.sonicPrimary)
                            Image(systemName: expandedSection == .theme ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.sonicTextMuted)
                        }
                    }
                }
                .buttonStyle(.plain)

                if expandedSection == .theme {
                    VStack(spacing: 0) {
                        ForEach(AppColorScheme.allCases) { scheme in
                            Button {
                                viewModel.setColorScheme(scheme)
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    expandedSection = nil
                                }
                            } label: {
                                HStack {
                                    Image(systemName: scheme.icon)
                                        .font(.body)
                                        .foregroundColor(.sonicTextSecondary)
                                        .frame(width: 20)
                                    Text(scheme.rawValue)
                                        .font(.subheadline)
                                        .foregroundColor(.sonicTextPrimary)
                                    Spacer()
                                    if scheme == viewModel.colorScheme {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundColor(.sonicPrimary)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 36)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expandedSection = expandedSection == .language ? nil : .language
                    }
                } label: {
                    SettingsRow(
                        icon: "globe",
                        title: "Language",
                        iconColor: .sonicPrimary
                    ) {
                        HStack(spacing: 4) {
                            Text(selectedLanguage.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.sonicPrimary)
                            Image(systemName: expandedSection == .language ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.sonicTextMuted)
                        }
                    }
                }
                .buttonStyle(.plain)

                if expandedSection == .language {
                    VStack(spacing: 0) {
                        ForEach(supportedLanguages) { language in
                            Button {
                                setLanguage(language)
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    expandedSection = nil
                                }
                            } label: {
                                HStack {
                                    Text(language.displayName)
                                        .font(.subheadline)
                                        .foregroundColor(.sonicTextPrimary)
                                    Spacer()
                                    if language.id == appLanguage {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundColor(.sonicPrimary)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 36)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Text("Language updates immediately.")
                    .font(.caption)
                    .foregroundColor(.sonicTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 44)
            }
        }
    }

    private var infoSection: some View {
        SettingsSection(title: "Information", icon: "info.circle.fill") {
            VStack(spacing: 12) {
                SettingsButton(
                    icon: "info.circle",
                    title: "About Sonic",
                    iconColor: .blue
                ) {
                    viewModel.showAboutTapped()
                }

                Divider()

                SettingsButton(
                    icon: "questionmark.circle",
                    title: "Help & Support",
                    iconColor: .green
                ) {
                    viewModel.showHelpTapped()
                }
            }
        }
    }

    private var selectedLanguage: AppLanguage {
        supportedLanguages.first { $0.id == appLanguage } ?? .system
    }

    private func setLanguage(_ language: AppLanguage) {
        appLanguage = language.id
        if let code = language.code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}

struct AppLanguage: Identifiable, Equatable {
    static let systemID = "system"
    static let system = AppLanguage(code: nil)
    static let supportedLanguages: [AppLanguage] = [
        .system,
        AppLanguage(code: "en"),
        AppLanguage(code: "zh-Hans"),
        AppLanguage(code: "hi"),
        AppLanguage(code: "es"),
        AppLanguage(code: "fr"),
        AppLanguage(code: "ar"),
        AppLanguage(code: "bn"),
        AppLanguage(code: "pt"),
        AppLanguage(code: "ru"),
    ]

    let code: String?
    var id: String { code ?? Self.systemID }

    var displayName: String {
        guard let code else { return NSLocalizedString("System", comment: "System language option") }
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code) ?? code
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

                Image(systemName: "chevron.forward")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicTextMuted)
            }
        }
    }
}
