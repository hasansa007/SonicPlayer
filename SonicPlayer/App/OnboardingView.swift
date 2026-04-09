import ComposableArchitecture
import SwiftUI

struct OnboardingView: View {
    @Bindable var store: StoreOf<OnboardingFeature>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.sonicBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                pageIndicators
                    .padding(.top, 60)

                TabView(selection: $store.currentPage.sending(\.setPage)) {
                    WelcomePage().tag(0)
                    ImportPage().tag(1)
                    RecordPage().tag(2)
                    ListenPage().tag(3)
                    OrganizePage().tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

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
                RoundedRectangle(cornerRadius: 4)
                    .fill(index == store.currentPage ? Color.sonicPrimary : Color.sonicPrimary.opacity(0.25))
                    .frame(width: index == store.currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: store.currentPage)
            }
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        let isLast = store.currentPage == store.totalPages - 1
        return Button {
            if isLast {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                store.send(.getStartedTapped)
            } else {
                store.send(.nextPage)
            }
        } label: {
            Text(isLast ? "Get Started" : "Next")
                .font(.body)
                .fontWeight(.bold)
                .foregroundColor(isLast ? .white : .sonicPrimary)
                .frame(maxWidth: 260)
                .padding(.vertical, 16)
                .background(isLast ? AnyShapeStyle(Color.sonicPrimary) : AnyShapeStyle(Color.clear), in: Capsule())
                .overlay(Capsule().stroke(Color.sonicPrimary, lineWidth: isLast ? 0 : 2))
        }
        .buttonStyle(OnboardingButtonStyle())
        .animation(.easeInOut(duration: 0.3), value: store.currentPage)
    }
}

// MARK: - Button Style

struct OnboardingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Page 1: Welcome

struct WelcomePage: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("colorScheme") private var selectedScheme = AppColorScheme.system.rawValue

    private var currentScheme: AppColorScheme {
        AppColorScheme(rawValue: selectedScheme) ?? .system
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.sonicPrimary.opacity(0.15), Color.clear],
                        center: .center, startRadius: 0, endRadius: 80
                    ))
                    .frame(width: 180, height: 180)
                    .scaleEffect(appeared && !reduceMotion ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: appeared)

                OnboardingWaveform()
                    .frame(width: 120, height: 60)
            }
            .scaleEffect(appeared ? 1.0 : 0.9)
            .opacity(appeared ? 1.0 : 0)

            Text("Your audio. Your space.")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.sonicTextPrimary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 12)

            Text("Simple. Private. Always yours.")
                .font(.body).foregroundColor(.sonicTextSecondary)
                .multilineTextAlignment(.center).lineSpacing(5)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 12)

            Spacer()

            // Theme selector
            VStack(spacing: 12) {
                Text("Choose your theme")
                    .font(.subheadline)
                    .foregroundColor(.sonicTextSecondary)

                HStack(spacing: 16) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedScheme = scheme.rawValue
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: scheme.icon)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(currentScheme == scheme ? Color.sonicPrimary.opacity(0.15) : Color.sonicPrimary.opacity(0.05))
                                    )

                                Text(scheme.rawValue)
                                    .font(.caption2)
                                    .fontWeight(currentScheme == scheme ? .semibold : .regular)
                            }
                            .foregroundColor(currentScheme == scheme ? .sonicPrimary : .sonicTextSecondary)
                        }
                    }
                }
            }
            .opacity(appeared ? 1.0 : 0)

            Spacer()
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { appeared = true } }
        .preferredColorScheme(currentScheme.colorScheme)
    }
}

// MARK: - Animated Waveform

struct OnboardingWaveform: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let heights: [CGFloat] = [20, 35, 50, 60, 45, 30, 18]

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient.sonicGradient)
                    .frame(width: 8, height: animating ? heights[index] : 12)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: Double.random(in: 0.6...1.0))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Page 2: Import

struct ImportPage: View {
    @State private var appeared = false
    @State private var arrowBounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.sonicPrimary.opacity(0.1), Color.clear],
                        center: .center, startRadius: 0, endRadius: 80
                    ))
                    .frame(width: 180, height: 180)

                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.sonicPrimary)
                        .offset(y: arrowBounce ? -4 : 4)

                    // Files landing
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.sonicPrimary.opacity(0.3 + Double(i) * 0.15))
                                .frame(width: 20, height: 24)
                        }
                    }
                    .opacity(arrowBounce ? 1.0 : 0.5)
                }
            }
            .scaleEffect(appeared ? 1.0 : 0.9)
            .opacity(appeared ? 1.0 : 0)

            Text("Bring your audio in.")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.sonicTextPrimary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 12)

            Text("Import files, folders, or full playlists in seconds.")
                .font(.body).foregroundColor(.sonicTextSecondary)
                .multilineTextAlignment(.center).lineSpacing(5)
                .padding(.horizontal, 32)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 12)

            Spacer(); Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                arrowBounce = true
            }
        }
    }
}

// MARK: - Page 3: Record

struct RecordPage: View {
    @State private var appeared = false
    @State private var recording = false
    @State private var waveHeights: [CGFloat] = Array(repeating: 4, count: 9)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.red.opacity(recording ? 0.18 : 0.08), Color.clear],
                        center: .center, startRadius: 0, endRadius: 80
                    ))
                    .frame(width: 180, height: 180)

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.red.opacity(0.85), Color.red],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .frame(width: 56, height: 56)
                            .shadow(color: Color.red.opacity(recording ? 0.5 : 0.2), radius: recording ? 16 : 8)

                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    .scaleEffect(recording ? 1.08 : 1.0)

                    HStack(alignment: .center, spacing: 4) {
                        ForEach(0..<9, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red.opacity(0.7))
                                .frame(width: 4, height: waveHeights[index])
                        }
                    }
                    .frame(height: 30)
                }
            }
            .scaleEffect(appeared ? 1.0 : 0.9)
            .opacity(appeared ? 1.0 : 0)

            Text("Capture anything instantly.")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.sonicTextPrimary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 12)

            Text("Record ideas, lectures, or notes — anytime.")
                .font(.body).foregroundColor(.sonicTextSecondary)
                .multilineTextAlignment(.center).lineSpacing(5)
                .padding(.horizontal, 32)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 12)

            Spacer(); Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { recording = true }
            Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    for i in 0..<9 { waveHeights[i] = CGFloat.random(in: 4...28) }
                }
            }
        }
    }
}

// MARK: - Page 4: Listen

struct ListenPage: View {
    @State private var appeared = false
    @State private var progress: CGFloat = 0.15
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.sonicPrimary.opacity(0.1), Color.clear],
                        center: .center, startRadius: 0, endRadius: 90
                    ))
                    .frame(width: 200, height: 200)

                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.sonicPrimary)
                            .frame(width: 52, height: 52)
                            .shadow(color: Color.sonicPrimary.opacity(0.3), radius: pulsing ? 16 : 8)

                        Image(systemName: "play.fill")
                            .font(.title3).foregroundColor(.white).offset(x: 2)
                    }
                    .scaleEffect(pulsing ? 1.05 : 1.0)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.sonicPrimary.opacity(0.15)).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.sonicPrimary)
                                .frame(width: geo.size.width * progress, height: 6)
                        }
                    }
                    .frame(width: 140, height: 6)

                    Text("1.5x")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.sonicPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.sonicPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .scaleEffect(appeared ? 1.0 : 0.9)
            .opacity(appeared ? 1.0 : 0)

            Text("Listen your way.")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.sonicTextPrimary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 12)

            Text("Speed, repeat, shuffle — even in the background.")
                .font(.body).foregroundColor(.sonicTextSecondary)
                .multilineTextAlignment(.center).lineSpacing(5)
                .padding(.horizontal, 32)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 12)

            Spacer(); Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { progress = 0.85 }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulsing = true }
        }
    }
}

// MARK: - Page 5: Organize

struct OrganizePage: View {
    @State private var appeared = false
    @State private var fileSlid = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.sonicPrimary.opacity(0.1), Color.clear],
                        center: .center, startRadius: 0, endRadius: 80
                    ))
                    .frame(width: 180, height: 180)

                Image(systemName: "folder.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.sonicPrimary)

                Image(systemName: "doc.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.sonicPrimary.opacity(0.7))
                    .offset(x: fileSlid ? 0 : 50, y: fileSlid ? -5 : -30)
                    .opacity(fileSlid ? 0.8 : 0.3)
                    .shadow(color: Color.sonicPrimary.opacity(0.2), radius: fileSlid ? 4 : 0)
            }
            .scaleEffect(appeared ? 1.0 : 0.9)
            .opacity(appeared ? 1.0 : 0)

            Text("Everything in its place.")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.sonicTextPrimary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 12)

            Text("Stay organized and enjoy your audio, stress-free.")
                .font(.body).foregroundColor(.sonicTextSecondary)
                .multilineTextAlignment(.center).lineSpacing(5)
                .padding(.horizontal, 32)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 12)

            Spacer(); Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.3)) {
                fileSlid = true
            }
        }
    }
}
