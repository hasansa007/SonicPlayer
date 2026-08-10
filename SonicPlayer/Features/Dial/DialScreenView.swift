import SwiftUI

/// **Every screen in the dial navigator, as one view (#6).**
///
/// There are eight screens in the design and one type here, because `DialScreen` made the screens
/// *data*. Adding a ninth is a value, not a file — which is the property that lets the navigator be
/// built and tested with no SwiftUI in sight, and this half be built against fixtures with no
/// playback in sight.
///
/// The stack is the contract's, in the contract's order:
///
///     chrome     breadcrumb + status
///     content    the part that differs — a list, a player, a meter, a waveform
///     actions    a row of chips
///     ring       ticks + hub, the only input surface that matters
///     hint       one line of plain language
///
/// **It owns no state and no navigation.** Every gesture leaves as a `DialCommand`; nothing about
/// what a command *means* is decided here.
struct DialScreenView: View {

    let screen: DialScreen
    let onCommand: (DialCommand) -> Void

    var body: some View {
        ZStack {
            background

            // **The card yields; the controls do not.** Both lower bands get layout priority, so
            // when text grows the list gives up height rather than the hint losing its last words
            // or the chips being clipped. At AX5 without this the hint truncated to
            // "rotate to browse ·…", which is the one line on the screen that teaches the wheel.
            VStack(spacing: Spacing.lg) {
                stage
                    .layoutPriority(0)

                Spacer(minLength: 0)

                DialActionRow(actions: screen.actions, onCommand: onCommand)
                    .layoutPriority(1)

                dial
                    .layoutPriority(1)
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
    }

    /// **Back sits in the card's bottom-left corner, not its top-left.**
    ///
    /// It was the first thing in the header — the furthest corner of the card from the hand, and
    /// the only thing up there pressed often. Moved down it is a short reach from the wheel, and the
    /// header goes back to being what it says it is: where you are, and what is playing.
    ///
    /// Inside the card rather than loose on the screen, because it acts on the card — it pops the
    /// level the card is showing. A control floating beside the dial would read as belonging to the
    /// dial, which nudges and presses and never navigates.
    /// The header, ruled off from the content beneath it.
    ///
    /// The hairline sits on the *bottom* edge of the bar, mirroring the bottom bar's on its top
    /// edge — so the card reads as three bands: where you are, what is here, and the way back. The
    /// `VStack`'s own spacing does the separating either side, which is what keeps the two rules
    /// the same distance from the content they divide.
    private var topBar: some View {
        DialChrome(chrome: screen.chrome, onCommand: onCommand)
            .dynamicTypeSize(...Self.captionCeiling)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.sonicBorder)
                    .frame(height: Sizing.hairlineTrackHeight)
                    .offset(y: Spacing.sm)
            }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            backControl
            Spacer(minLength: 0)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.sonicBorder)
                .frame(height: Sizing.hairlineTrackHeight)
        }
    }

    private var backControl: some View {
        Button {
            onCommand(.action("back"))
        } label: {
            // **A list glyph rather than a chevron.** A chevron says only "backwards", which on a
            // stack of eight screens is a direction and not a destination. Every level below the
            // root pops to a list — the library, or home — so the icon can name where it goes
            // instead of which way. It also stops reading as the navigation bar's back button on a
            // screen that deliberately has no navigation bar.
            Image(systemName: "list.bullet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.sonicPrimary)
                // A real target, not a glyph-sized one. In the header this was caption-sized with a
                // padded hit area to compensate; it stopped being chrome when it became the control
                // you press most.
                .frame(width: Sizing.tapTarget, height: Sizing.tapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Back"))
    }

    /// The same gradient `ShellView` established for the wheel canvas: teal falling into the
    /// background, so the top of the screen is lit and the dial sits in the dark half.
    ///
    /// **Over an opaque base**, which the gradient alone is not — its top stop is 15% teal, so the
    /// whole upper half of the screen is partly transparent and takes its colour from whatever the
    /// window happens to put behind it. That is invisible in the app and glaring the moment the
    /// screen is rendered anywhere else, which is exactly how it was found.
    private var background: some View {
        ZStack {
            Color.sonicBackground

            LinearGradient(
                colors: [
                    Color.sonicPrimaryLight.opacity(Self.washTint),
                    Color.sonicBackground,
                    Color.sonicBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    /// The card. Everything above the action row lives inside it, which is what makes the dial read
    /// as the device and the content as what is on the device.
    private var stage: some View {
        VStack(spacing: Spacing.md) {
            if hasChrome { topBar }

            // **Static until it cannot be, then scrollable.**
            //
            // The dial is a fixed 236 points and does not scale, so at the accessibility text
            // sizes the content above it stops fitting — measured at AX5, where the card ran off
            // both ends of the screen and the breadcrumb was simply gone. `ViewThatFits` picks the
            // static layout whenever it fits, which is every ordinary setting, and a scroll view
            // only when the alternative is content nobody can reach.
            //
            // It also makes the card *compressible*: without a zero-minimum option in here, the
            // outer stack cannot shrink the card below its content's ideal height, which is what
            // pushed the dial off the bottom rather than squeezing the list.
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
            }

            // **A bar, not an overlay.** Sitting on top of the content it covered the last row of a
            // full list; as the stack's final element it holds its own height, so the list ends
            // above it and nothing is hidden however long the list gets.
            if screen.chrome.canGoBack { bottomBar }
        }
        .padding(Spacing.lg)
        // **Wide, but only as tall as it needs to be.** `maxHeight: .infinity` made the card fill
        // whatever was left, so a three-row library was a third of a screen of nothing under three
        // rows. The stack below still gives it every point the dial does not want, so a long list
        // grows exactly as far as it can — it just no longer *claims* the space when empty.
        .frame(maxWidth: .infinity)
        .background(Color.sonicSurface, in: RoundedRectangle(cornerRadius: Radius.stage))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.stage).strokeBorder(Color.sonicBorder)
        )
        // Content is windowed by the navigator, not scrolled here, so anything that overruns is
        // clipped rather than allowed to escape the card and collide with the action row.
        .clipShape(RoundedRectangle(cornerRadius: Radius.stage))
    }

    private var hasChrome: Bool {
        !screen.chrome.breadcrumb.isEmpty || screen.chrome.status != nil || screen.chrome.isRecording || screen.chrome.canGoBack
    }

    @ViewBuilder
    private var content: some View {
        switch screen.content {
        case .list(let list):
            // A tap on a row is the touch equal of turning to it and pressing — the same two
            // commands, in the same order, so touch and wheel stay peers rather than one being a
            // fallback for the other.
            DialListView(list: list) { index in
                let travel = index - list.highlighted
                if travel != 0 { onCommand(.tick(travel)) }
                onCommand(.press)
            }

        case .nowPlaying(let nowPlaying):
            DialNowPlayingView(nowPlaying: nowPlaying)

        case .recording(let recording):
            DialRecordingView(recording: recording)

        case .edit(let edit):
            DialEditView(edit: edit, onCommand: onCommand)

        case .message(let message):
            DialMessageView(message: message)
        }
    }

    /// The dial, and nothing else.
    ///
    /// **One component.** It briefly grew two spring-return segments beside it for volume and
    /// track; they worked and they were busy — three controls to drive one player is two too many,
    /// and the whole idea of the dial is that there is only ever one thing to touch. Those
    /// directions folded into the hub, which is now a gear stick.
    ///
    /// The caption under it is gone too. It was the only thing teaching the gestures, so its
    /// replacement is the four direction marks around the hub — smaller than a control and
    /// permanent, rather than a sentence that had to change per mode.
    private var dial: some View {
        DialRing(
            ticks: screen.ring.ticks,
            hub: screen.ring.hub,
            defersPress: screen.ring.defersPress,
            directions: screen.ring.directions,
            isLive: screen.ring.isLive,
            onCommand: onCommand
        )
        // The hint is no longer drawn, but it is still the sentence that explains the gestures —
        // and a VoiceOver user cannot see the direction marks that replaced it. So it stops being
        // a caption and becomes the dial's spoken description, which is where it was always most
        // useful.
        .accessibilityHint(Text(screen.hint))
    }

    private static let washTint: Double = 0.15

    /// How far the two persistent captions — the breadcrumb and the hint — are allowed to grow.
    ///
    /// **Not the dial's cap, and not for the dial's reason.** The dial is pinned because it is a
    /// physical control. These are pinned because they are *repeated on every screen*: uncapped at
    /// AX5 the hint alone took three lines and 230 points, which left the list it was explaining
    /// about one row tall. A caption that crowds out the thing it captions has stopped helping.
    ///
    /// Still well above the base size, and nothing is lost to VoiceOver — the hint carries an
    /// explicit `accessibilityLabel` and the chrome is one combined element, so both are read in
    /// full regardless of how large they are drawn. Everything that is *content* — rows, titles,
    /// timers, action chips — scales without a ceiling.
    private static let captionCeiling: DynamicTypeSize = .accessibility1
}
