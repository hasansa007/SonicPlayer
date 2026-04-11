import ComposableArchitecture
import SwiftUI

struct HelpView: View {
    let store: StoreOf<SettingsFeature>
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // FAQ section
                faqSection

                // Troubleshooting
                troubleshootingSection

                // Contact support
                supportSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color.sonicBackground.ignoresSafeArea())
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var faqSection: some View {
        HelpSection(
            title: "Frequently Asked Questions",
            icon: "questionmark.circle.fill",
            iconColor: .blue
        ) {
            VStack(spacing: 12) {
                FAQItem(
                    question: "How do I add audio files?",
                    answer: "In the Library tab, tap the + button and choose Import. You can import files and folders from the Files app. Supported formats: MP3, M4A, WAV."
                )

                FAQItem(
                    question: "Can I use Sonic Player offline?",
                    answer: "Yes! Sonic Player is designed to work completely offline. All your audio files are stored locally on your device."
                )

                FAQItem(
                    question: "How do I change the playback speed?",
                    answer: "In the Player view, tap the speed control to choose from 0.5× to 2.0×."
                )

                FAQItem(
                    question: "How do I change the language?",
                    answer: "Open Settings and select Language to choose your preferred language."
                )

                FAQItem(
                    question: "Can I skip forward or backward?",
                    answer: "Yes! Use the skip buttons on either side of the play button. You can customize the skip duration (15s, 30s, or 60s) in Settings."
                )

                FAQItem(
                    question: "Does it work with headphones?",
                    answer: "Absolutely! Sonic Player supports headphone controls, Bluetooth devices, and lock screen controls for seamless playback."
                )

                FAQItem(
                    question: "How do I record and edit audio?",
                    answer: "Open the Recordings tab to record audio. You can trim or delete sections of recordings in the editor."
                )
            }
        }
    }

    private var troubleshootingSection: some View {
        HelpSection(
            title: "Troubleshooting",
            icon: "wrench.and.screwdriver.fill",
            iconColor: .orange
        ) {
            VStack(spacing: 12) {
                TroubleshootItem(
                    issue: "Files not showing up",
                    solutions: [
                        "Make sure files are in MP3, M4A, or WAV format",
                        "Try importing again from Library → + → Import",
                        "Try pulling to refresh in the Library view",
                        "Restart the app"
                    ]
                )

                TroubleshootItem(
                    issue: "Audio not playing",
                    solutions: [
                        "Check device volume and mute switch",
                        "Ensure the file is not corrupted",
                        "Try playing a different file",
                        "Restart the app"
                    ]
                )

                TroubleshootItem(
                    issue: "Background playback not working",
                    solutions: [
                        "Check that Low Power Mode is not enabled",
                        "Ensure Background App Refresh is enabled for Sonic Player",
                        "Check your device's audio session settings"
                    ]
                )
            }
        }
    }

    private var supportSection: some View {
        VStack(spacing: 16) {
            Text("Still Need Help?")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.sonicTextPrimary)

            Text("We're here to help! Reach out through any of these channels:")
                .font(.subheadline)
                .foregroundColor(.sonicTextSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                SupportButton(
                    icon: "envelope.fill",
                    title: "Email Support",
                    subtitle: "hasansa007@gmail.com"
                ) {}

                SupportButton(
                    icon: "sparkles",
                    title: "Request a Feature",
                    subtitle: "Tell us what you want to see next"
                ) {
                    store.send(.requestFeatureTapped)
                }
            }
        }
        .padding(20)
        .background(Color.sonicSurface)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Help Components

struct HelpSection<Content: View>: View {
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
    }
}

struct StepCard: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Step number badge
            ZStack {
                Circle()
                    .fill(LinearGradient.sonicGradient)
                    .frame(width: 40, height: 40)

                Text("\(number)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            // Step content
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicTextPrimary)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.sonicTextSecondary)
                    .lineHeight(1.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.sonicSurface)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(question)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.sonicTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicPrimary)
                }
            }

            if isExpanded {
                Text(answer)
                    .font(.subheadline)
                    .foregroundColor(.sonicTextSecondary)
                    .lineHeight(1.6)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .padding(16)
        .background(Color.sonicSurface)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

struct TroubleshootItem: View {
    let issue: String
    let solutions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundColor(.orange)

                Text(issue)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicTextPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(solutions.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(.sonicPrimary)

                        Text(solutions[index])
                            .font(.subheadline)
                            .foregroundColor(.sonicTextSecondary)
                            .lineHeight(1.5)
                    }
                }
            }
            .padding(.leading, 8)
        }
        .padding(16)
        .background(Color.sonicSurface)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

struct SupportButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.sonicPrimary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.sonicTextPrimary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.sonicTextSecondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.sonicTextMuted)
            }
            .padding(16)
            .background(LinearGradient.sonicGradientLight)
            .cornerRadius(12)
        }
    }
}
