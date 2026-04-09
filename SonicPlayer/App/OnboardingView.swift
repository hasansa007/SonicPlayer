import ComposableArchitecture
import SwiftUI

struct OnboardingView: View {
    @Bindable var store: StoreOf<OnboardingFeature>

    var body: some View {
        ZStack {
            Color.sonicBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page indicators
                pageIndicators
                    .padding(.top, 60)

                // Pages
                Group {
                    switch store.currentPage {
                    case 0: welcomePage
                    case 1: organizePage
                    case 2: listenPage
                    default: privatePage
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.easeInOut(duration: 0.3), value: store.currentPage)

                // Button
                actionButton
                    .padding(.horizontal, 40)
                    .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Page Indicators

    private var pageIndicators: some View {
        HStack(spacing: 8) {
            ForEach(0..<store.totalPages, id: \.self) { index in
                if index == store.currentPage {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.sonicPrimary)
                        .frame(width: 22, height: 8)
                } else {
                    Circle()
                        .fill(Color.sonicPrimary.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.currentPage)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        onboardingPage(
            icon: "waveform.circle.fill",
            iconSize: 72,
            useGradient: true,
            title: "Welcome to Sonic Player",
            subtitle: "Your personal audio library — simple, private, and always offline."
        )
    }

    private var organizePage: some View {
        onboardingPage(
            icon: "square.grid.2x2.fill",
            iconSize: 60,
            useGradient: false,
            title: "Organize Your Audio",
            subtitle: "Create collections, import files from other apps, or record new audio — all in one place."
        )
    }

    private var listenPage: some View {
        onboardingPage(
            icon: "headphones",
            iconSize: 60,
            useGradient: false,
            title: "Powerful Playback",
            subtitle: "Queue tracks, adjust speed, repeat & shuffle — with background audio and lock screen controls."
        )
    }

    private var privatePage: some View {
        onboardingPage(
            icon: "lock.shield.fill",
            iconSize: 60,
            useGradient: false,
            title: "Private & Offline",
            subtitle: "No accounts, no ads, no tracking. Your audio stays on your device."
        )
    }

    // MARK: - Reusable Page

    private func onboardingPage(icon: String, iconSize: CGFloat, useGradient: Bool, title: String, subtitle: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon with background circle
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.sonicPrimary.opacity(0.12), Color.sonicPrimary.opacity(0.02)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)

                if useGradient {
                    Image(systemName: icon)
                        .font(.system(size: iconSize))
                        .foregroundStyle(LinearGradient.sonicGradient)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: iconSize))
                        .foregroundColor(.sonicPrimary)
                }
            }

            // Title
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.sonicTextPrimary)
                .multilineTextAlignment(.center)

            // Subtitle
            Text(subtitle)
                .font(.body)
                .foregroundColor(.sonicTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Group {
            if store.currentPage == store.totalPages - 1 {
                // Get Started (filled)
                Button {
                    store.send(.getStartedTapped)
                } label: {
                    Text("Get Started")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 16)
                        .background(Color.sonicPrimary, in: Capsule())
                }
            } else {
                // Next (outlined)
                Button {
                    store.send(.nextPage)
                } label: {
                    Text("Next")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.sonicPrimary)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .stroke(Color.sonicPrimary, lineWidth: 2)
                        )
                }
            }
        }
    }
}
