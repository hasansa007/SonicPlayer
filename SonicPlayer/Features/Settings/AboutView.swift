import ComposableArchitecture
import SwiftUI

struct AboutView: View {
    let store: StoreOf<SettingsFeature>
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Hero section
                    heroSection

                    // Mission section
                    missionSection

                    // Features section
                    featuresSection

                    // Tech stack section
                    techStackSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color.sonicBackground.ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.sonicTextMuted)
                    }
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 20) {
            // App logo
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .shadow(color: Color.sonicPrimary.opacity(0.4), radius: 30, x: 0, y: 15)

            VStack(spacing: 8) {
                Text("Sonic Player")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(LinearGradient.sonicGradient)

                Text("Offline-first Audio Player")
                    .font(.subheadline)
                    .foregroundColor(.sonicTextSecondary)
                    .multilineTextAlignment(.center)

                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundColor(.sonicTextMuted)
                    .padding(.top, 4)
            }
        }
    }

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, build) {
        case let (shortVersion?, build?):
            return "\(shortVersion) (\(build))"
        case let (shortVersion?, nil):
            return shortVersion
        case let (nil, build?):
            return build
        case (nil, nil):
            return "—"
        }
    }

    private var missionSection: some View {
        InfoCard(
            title: "Our Mission",
            icon: "target",
            iconColor: .sonicPrimary
        ) {
            Text("Sonic Player is built to help you enjoy your personal audio library without ads, algorithms, or distractions. Import your files, organize by folders, search quickly, and listen anywhere — even offline.")
                .font(.body)
                .foregroundColor(.sonicTextSecondary)
                .lineHeight(1.6)
        }
    }

    private var featuresSection: some View {
        InfoCard(
            title: "Key Features",
            icon: "star.fill",
            iconColor: .orange
        ) {
            VStack(spacing: 16) {
                FeatureItem(
                    icon: "square.stack.3d.up.fill",
                    title: "Library + Search",
                    description: "Browse folders, sort, and search your audio collection"
                )

                FeatureItem(
                    icon: "wifi.slash",
                    title: "Offline First",
                    description: "Your files stay on your device — no internet required"
                )

                FeatureItem(
                    icon: "lock.shield.fill",
                    title: "Background Playback",
                    description: "Continue listening with your screen locked or in other apps"
                )

                FeatureItem(
                    icon: "arrow.left.arrow.right",
                    title: "Smart Skip Controls",
                    description: "Jump forward or backward with customizable intervals"
                )

                FeatureItem(
                    icon: "mic.fill",
                    title: "Recording",
                    description: "Record audio and edit recordings (trim or delete sections)"
                )
            }
        }
    }

    private var techStackSection: some View {
        InfoCard(
            title: "Built With",
            icon: "hammer.fill",
            iconColor: .purple
        ) {
            VStack(spacing: 12) {
                TechBadge(name: "Swift", icon: "swift")
                TechBadge(name: "SwiftUI", icon: "paintbrush.fill")
                TechBadge(name: "TCA (The Composable Architecture)", icon: "building.columns.fill")
                TechBadge(name: "AVFoundation", icon: "waveform")
            }
        }
    }
}

// MARK: - Supporting Views

struct InfoCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicTextPrimary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.sonicSurface)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.sonicPrimary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicTextPrimary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.sonicTextSecondary)
                    .lineHeight(1.4)
            }
        }
    }
}

struct TechBadge: View {
    let name: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.sonicPrimary)

            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.sonicTextPrimary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LinearGradient.sonicGradientLight)
        .cornerRadius(12)
    }
}

struct SocialButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(LinearGradient.sonicGradient)
            .cornerRadius(12)
        }
    }
}

struct StatBox: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(label)
                .font(.caption)
                .foregroundColor(.sonicTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.1))
        .cornerRadius(16)
    }
}

extension Text {
    func lineHeight(_ height: CGFloat) -> some View {
        // Fallback implementation since Text doesn't expose font metrics
        // Assuming base font size of 17 (body)
        self.lineSpacing((height - 1) * 17)
    }
}
