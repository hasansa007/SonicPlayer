import SwiftUI

struct OnboardingView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ZStack {
            Color.sonicBackground.ignoresSafeArea()

            // **The app's own layout: card above, wheel below** (#102). The page dots are gone with
            // the Next button — the ring's thumb marks the position, so a second progress indicator
            // says the same thing twice.
            VStack(spacing: Spacing.lg) {
                TabView(selection: $viewModel.currentPage) {
                    WelcomePage().tag(0)
                    DialPage().tag(1)
                    NudgePage().tag(2)
                    RecordPage().tag(3)
                    ChipsPage().tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // **The same card the dial draws on** (#102). The first run should look like the
                // app it is introducing, so the content sits where content sits and the wheel sits
                // where the wheel sits.
                .dialCard()

                actionDial
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xxxl)
        }
    }

    // MARK: - The wheel

    /// **The wheel is the Next button** (#102).
    ///
    /// The capsule that stood here said "Next", and five taps later the user met a control they had
    /// never seen. Driving onboarding with the real `DialRing` teaches turning and pressing by
    /// spending them on the only thing there is to do — and the ticks double as the progress the page
    /// dots used to carry.
    private var actionDial: some View {
        let isLast = viewModel.currentPage == viewModel.totalPages - 1
        return DialRing(
            ticks: .browse(thumb: Double(viewModel.currentPage) / Double(max(viewModel.totalPages - 1, 1))),
            // Uppercased here, not in the catalogue: the caps are the hub's style, and a second
            // all-caps key is the same word twice — which is exactly what string-symbol generation
            // refused to compile.
            hub: .label(isLast ? String(localized: "Start").uppercased()
                               : String(localized: "Next").uppercased()),
            onCommand: { command in
                switch command {
                case .press:
                    isLast ? viewModel.getStartedTapped() : viewModel.nextPage()
                case .tick(let detents):
                    // Turning walks the pages, so the first thing the wheel ever does is the thing
                    // it does everywhere else.
                    let target = viewModel.currentPage + (detents > 0 ? 1 : -1)
                    viewModel.setPage(max(0, min(viewModel.totalPages - 1, target)))
                default:
                    break
                }
            }
        )
        .frame(width: Sizing.dialDiameter, height: Sizing.dialDiameter)
    }
}

// MARK: - One page, five times

/// **The scaffold every first-run page shares** (#102).
///
/// Each page used to be its own `VStack` repeating the same seven things — the glow, the enter
/// animation, the title, the body, the two `Spacer()`s and the numbers between them — retyped in
/// full. Five copies of one layout is five places for it to drift, and it had: one page drew a
/// 200pt glow where the others drew 180, and one set its body copy at a different width.
///
/// **The strings are localised here, at the literal.** `String(localized:)` is what the extractor
/// reads; the render is `Text(verbatim:)` precisely *because* the value arriving is already
/// localised, which is the distinction #50 was opened for and #65 paid for again.
private struct OnboardingPage<Art: View, Footer: View>: View {
    let title: String
    let message: String
    @ViewBuilder var art: () -> Art
    @ViewBuilder var footer: () -> Footer

    @State private var appeared = false

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            art()
                .scaleEffect(appeared ? 1 : OnboardingArt.enterScale)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: Spacing.xxl) {
                Text(verbatim: title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.sonicTextPrimary)
                    .multilineTextAlignment(.center)

                Text(verbatim: message)
                    .font(.body)
                    .foregroundColor(.sonicTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(OnboardingArt.bodyLineSpacing)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : OnboardingArt.enterOffset)

            footer()
                .opacity(appeared ? 1 : 0)

            Spacer()
        }
        .onAppear { withAnimation(Motion.onboardingEnter) { appeared = true } }
    }
}

extension OnboardingPage where Footer == EmptyView {
    init(title: String, message: String, @ViewBuilder art: @escaping () -> Art) {
        self.init(title: title, message: message, art: art, footer: { EmptyView() })
    }
}

/// The radial wash behind every illustration. One size, so paging does not twitch.
private struct ArtGlow<Content: View>: View {
    var tint: Color = .sonicPrimary
    var opacity: Double = 0.1
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [tint.opacity(opacity), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: OnboardingArt.glowFade
                ))
                .frame(width: OnboardingArt.glow, height: OnboardingArt.glow)

            content()
        }
    }
}

// MARK: - Page 1: Welcome

struct WelcomePage: View {
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("colorScheme") private var selectedScheme = AppColorScheme.system.rawValue

    private var currentScheme: AppColorScheme {
        AppColorScheme(rawValue: selectedScheme) ?? .system
    }

    var body: some View {
        OnboardingPage(
            title: String(localized: "Your audio. Your space."),
            message: String(localized: "Turn the wheel below. It is the whole app."),
            art: {
                ArtGlow(opacity: 0.15) {
                    OnboardingWaveform()
                        .frame(width: OnboardingArt.waveform.width, height: OnboardingArt.waveform.height)
                }
                .scaleEffect(breathing && !reduceMotion ? 1.1 : 1)
                .animation(Motion.onboardingBreathe, value: breathing)
                .onAppear { breathing = true }
            },
            footer: { themePicker }
        )
        .preferredColorScheme(currentScheme.colorScheme)
    }

    private var themePicker: some View {
        VStack(spacing: Spacing.md) {
            Text("Choose your theme")
                .font(.subheadline)
                .foregroundColor(.sonicTextSecondary)

            HStack(spacing: Spacing.lg) {
                ForEach(AppColorScheme.allCases) { scheme in
                    Button {
                        withAnimation(Motion.selectionMode) { selectedScheme = scheme.rawValue }
                    } label: {
                        VStack(spacing: Spacing.xs) {
                            Image(systemName: scheme.icon)
                                .font(.title3)
                                .frame(width: Sizing.tapTarget, height: Sizing.tapTarget)
                                .background(
                                    Circle().fill(
                                        Color.sonicPrimary.opacity(currentScheme == scheme ? 0.15 : 0.05)
                                    )
                                )

                            // Already localised — `rawValue` is the stored key, not a label (#102).
                            Text(verbatim: scheme.label)
                                .font(.caption2)
                                .fontWeight(currentScheme == scheme ? .semibold : .regular)
                        }
                        .foregroundColor(currentScheme == scheme ? .sonicPrimary : .sonicTextSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Animated Waveform

struct OnboardingWaveform: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let heights: [CGFloat] = [20, 35, 50, 60, 45, 30, 18]

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.xs) {
            ForEach(heights.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(LinearGradient.sonicGradient)
                    .frame(
                        width: OnboardingArt.waveBar,
                        height: animating ? heights[index] : OnboardingArt.waveBarRest
                    )
                    .animation(reduceMotion ? nil : Motion.waveformBar(index: index), value: animating)
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Page 2: One dial

/// **The art moves the highlight, because that is what turning does** (#102).
///
/// This page drew a download arrow and three landing file cards, under copy that used to read
/// "Bring your audio in." The copy is now about the dial, and an import arrow beside it illustrates
/// a different sentence — the picture argues with the words, and the picture wins.
struct DialPage: View {
    @State private var highlighted = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rows = 3

    var body: some View {
        OnboardingPage(
            title: String(localized: "Everything is one dial."),
            message: String(localized: "Turn to move through your library, press the centre to play what you land on.")
        ) {
            ArtGlow {
                VStack(spacing: Spacing.sm) {
                    ForEach(0..<Self.rows, id: \.self) { row in
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .fill(Color.sonicPrimary.opacity(row == highlighted ? 0.9 : 0.2))
                            .frame(
                                width: OnboardingArt.listRow.width,
                                height: OnboardingArt.listRow.height
                            )
                    }
                }
            }
            .task {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(900))
                    withAnimation(Motion.selection) {
                        highlighted = (highlighted + 1) % Self.rows
                    }
                }
            }
        }
    }
}

// MARK: - Page 3: The nudge

struct NudgePage: View {
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingPage(
            title: String(localized: "Push the centre for the rest."),
            message: String(localized: "Up to edit, down to delete, left to file, right to share. Rest your thumb and each one says its name.")
        ) {
            ArtGlow {
                ZStack {
                    Circle()
                        .fill(Color.sonicPrimary)
                        .frame(width: OnboardingArt.disc, height: OnboardingArt.disc)
                        .shadow(color: Color.sonicPrimary.opacity(0.3), radius: pulsing ? 16 : 8)
                        .scaleEffect(pulsing ? 1.05 : 1)

                    // The four directions, laid out as the thumb meets them.
                    ForEach(Array(NudgeMark.all.enumerated()), id: \.offset) { _, mark in
                        Image(systemName: mark.glyph)
                            .font(.caption)
                            .foregroundColor(.sonicPrimary)
                            .offset(x: mark.offset.width, y: mark.offset.height)
                    }
                }
            }
            // **Implicit, scoped to `pulsing`.** As `withAnimation(Motion.onboardingLoop) { … }` in
            // `onAppear` this repeatForever curve also caught the scaffold's `appeared` opacity,
            // set in the same frame — so the entire page faded in and out for ever, and a
            // screenshot caught whatever point of the pulse it happened to land on.
            .animation(reduceMotion ? nil : Motion.onboardingLoop, value: pulsing)
            .onAppear { pulsing = true }
        }
    }

    /// The legend around the hub. A table rather than four hand-placed glyphs, so the four agree.
    private struct NudgeMark {
        let glyph: String
        let offset: CGSize

        static let all: [NudgeMark] = {
            let reach = OnboardingArt.disc
            return [
                NudgeMark(glyph: "scissors", offset: CGSize(width: 0, height: -reach)),
                NudgeMark(glyph: "trash", offset: CGSize(width: 0, height: reach)),
                NudgeMark(glyph: "folder", offset: CGSize(width: -reach, height: 0)),
                NudgeMark(glyph: "square.and.arrow.up", offset: CGSize(width: reach, height: 0)),
            ]
        }()
    }
}

// MARK: - Page 4: Record and trim

struct RecordPage: View {
    @State private var recording = false
    @State private var levels: [CGFloat] = Array(repeating: OnboardingArt.levelBar, count: 9)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingPage(
            title: String(localized: "Record and trim on the same wheel."),
            message: String(localized: "The ring shows the level as you record, and moves the handles when you cut.")
        ) {
            ArtGlow(tint: .red, opacity: recording ? 0.18 : 0.08) {
                VStack(spacing: Spacing.lg) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.red.opacity(0.85), Color.red],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: OnboardingArt.disc, height: OnboardingArt.disc)
                            .shadow(color: Color.red.opacity(recording ? 0.5 : 0.2), radius: recording ? 16 : 8)

                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    .scaleEffect(recording ? 1.08 : 1)

                    HStack(alignment: .center, spacing: OnboardingArt.levelBar) {
                        ForEach(levels.indices, id: \.self) { index in
                            RoundedRectangle(cornerRadius: Radius.hairline)
                                .fill(Color.red.opacity(0.7))
                                .frame(width: OnboardingArt.levelBar, height: levels[index])
                        }
                    }
                    .frame(height: OnboardingArt.levelRow)
                }
            }
            .animation(reduceMotion ? nil : Motion.onboardingLoop, value: recording)
            .task {
                guard !reduceMotion else { return }
                recording = true
                // An owned loop rather than a `Timer` — the old one was never invalidated, so it
                // went on firing and writing @State after the carousel was dismissed.
                while !Task.isCancelled {
                    withAnimation(Motion.selection) {
                        levels = levels.map { _ in
                            .random(in: OnboardingArt.levelBar...OnboardingArt.levelPeak)
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
        }
    }
}

// MARK: - Page 5: The buttons under the card

/// **The chips the copy names, in the order the wheel reaches them** (#102).
///
/// A folder with a file sliding into it illustrated "Everything in its place." — the sentence this
/// page used to carry. It now says what is past the last row, so the art is that row, with the
/// highlight walking off the end of the list and onto it.
struct ChipsPage: View {
    @State private var reached = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The real row, in `DialNavigator.chipIDs` order — the one list the ring walks.
    private static let glyphs = ["mic.fill", "square.and.arrow.down", "folder.badge.plus", "arrow.up.arrow.down"]

    var body: some View {
        OnboardingPage(
            title: String(localized: "Turn past the last row."),
            message: String(localized: "Record, Import, folders and sort are waiting there — on every screen.")
        ) {
            ArtGlow {
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(Self.glyphs.enumerated()), id: \.offset) { index, glyph in
                        Image(systemName: glyph)
                            .font(.caption)
                            .foregroundColor(index == 0 && reached ? .white : .sonicPrimary)
                            .frame(width: OnboardingArt.chip, height: OnboardingArt.chip)
                            .background(
                                Circle().fill(
                                    Color.sonicPrimary.opacity(index == 0 && reached ? 0.9 : 0.12)
                                )
                            )
                    }
                }
            }
            .animation(reduceMotion ? nil : Motion.onboardingLoop.delay(0.3), value: reached)
            .onAppear { reached = true }
        }
    }
}
