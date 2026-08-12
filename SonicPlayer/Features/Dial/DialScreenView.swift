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

    /// The level the wheel's border is reporting, and whether it is reporting at all.
    ///
    /// Held here rather than in the contract because it is *presentation timing*: the navigator
    /// knows the volume and has no business knowing how long a transient lingers.
    @State private var shownVolume: Double?
    @State private var hideTask: Task<Void, Never>?

    /// **`.compact` here is landscape on a phone**, whatever the width class says — a 393×852 phone
    /// turned sideways is `.compact` vertically and `.regular` horizontally on the larger models,
    /// so height is the axis that answers "is the screen short now".
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let screen: DialScreen
    let onCommand: (DialCommand) -> Void

    var body: some View {
        ZStack {
            background

            Group {
                if verticalSizeClass == .compact {
                    sideBySide
                } else {
                    stacked
                }
            }
            // **Rotation is a swap, not something to animate through.** Both layouts contain
            // `ViewThatFits`, and an implicit animation in flight when the size class changes makes
            // them measure a geometry that is still moving — each frame a different candidate fits,
            // choosing it changes the size, and the new size chooses the other one. The screen
            // never settles. Cutting the animation on this one value leaves every other animation
            // on the screen alone.
            .animation(nil, value: verticalSizeClass)
        }
    }

    /// Portrait: the card, then the controls beneath it.
    ///
    /// **The card yields; the controls do not.** Every band below the card gets layout priority, so
    /// when text grows the list gives up height rather than the caption losing its last words or
    /// the chips being clipped. At AX5 without this the caption truncated to "rotate to browse ·…"
    /// — and it is shorter now precisely so that there is less of it to lose.
    private var stacked: some View {
        VStack(spacing: Spacing.lg) {
            // **One card height on every screen** (#6). It was content-sized with a `Spacer`
            // taking the slack, so a folder holding one recording drew a card two rows tall and a
            // full library drew one eight rows tall — and the wheel moved with them. The wheel's
            // position is the one thing on this layout the thumb learns without looking, so a card
            // that resizes per screen costs more than the empty space it saves.
            //
            // The empty space is the known trade, and it is why this was reverted once: a short
            // list leaves a surface with nothing on it. That is the better of the two, because the
            // alternative puts the same emptiness *between* the card and the controls, where it
            // reads as a gap rather than as a card.
            stage
                .frame(maxHeight: .infinity)
                .layoutPriority(0)

            controls
                .layoutPriority(1)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.top, Spacing.lg)
        // **The wheel sits well clear of the bottom edge**, which is a screen inset rather than
        // a gap between two things. The caption below it and this together lift the dial about
        // fifty points into the thumb's arc; the card gives up that height, which is the trade
        // taken knowingly — the wheel is what the hand is on for the whole session and the card
        // is what it looks at between turns.
        .padding(.bottom, Spacing.xxxl)
    }

    /// Landscape: the card on the leading side, the wheel and its chips on the trailing one.
    ///
    /// **Stacked, the dial does not fit.** It is a fixed 262 points and does not scale, and a
    /// landscape phone is about 390 tall — so the wheel, the chips and the caption alone are more
    /// than the screen, and the card was squeezed to a strip before anything else gave.
    ///
    /// Side by side each half gets the axis it needs: the card is tall-and-narrow work, the wheel
    /// is a fixed square. **Trailing rather than leading**, and deliberately not mirrored in
    /// Arabic — the wheel goes where the hand holding the phone is, which is the right side for the
    /// same reason it is at the bottom in portrait. `DialRing` already pins itself to
    /// `.leftToRight` for the neighbouring reason: a rotation points the way the media travels,
    /// not the way text is read.
    private var sideBySide: some View {
        // **Wider gaps than portrait uses between its bands, because these are not bands.** Stacked,
        // the card, the chips and the wheel are one column read top to bottom and a component gap
        // is right. Across, they are three separate things the eye moves between and the hand
        // reaches for in turn — at `lg` the chip column touched both its neighbours and read as
        // part of whichever it was nearer.
        HStack(spacing: Spacing.xxxl) {
            // **As tall as the wheel and as wide as what is left.** Its height is content-driven in
            // portrait, where the list is the long axis; here the long axis is across, so a card
            // that grows past the dial makes the two halves of the screen disagree about where the
            // middle is. Squaring it against the dial is what lets the eye read them as one object.
            stage
                .frame(maxWidth: .infinity)
                .frame(height: Sizing.dialDiameter)

            // **The controls turn from a column into a row, and the wheel keeps its size.** Stacked,
            // the chips, the dial and the caption come to about 370 points against roughly 340 of
            // landscape screen — so something had to give, and shrinking the dial would have made
            // the one control the whole app is built on a different size depending on which way the
            // phone is held. Laid out across, only the dial's own 262 is on the vertical axis.
            //
            // Both columns take their natural width and the card takes the rest — without
            // `fixedSize` the dial's column bargains for space it does not need and leaves the card
            // a strip with a gap beside it.
            // **`horizontal: true` only, and the `vertical: false` is load-bearing.** A bare
            // `fixedSize()` proposes an unspecified height, and the row's own
            // `ViewThatFits(in: .vertical)` cannot decide which candidate fits against a height
            // nobody has named — so it re-measures, the measurement changes what it reports, and
            // the layout never settles. Pinning only the width leaves the container's height
            // proposal intact, which is the input that question needs.
            DialActionRow(actions: screen.actions, onCommand: onCommand, axis: .vertical)
                .fixedSize(horizontal: true, vertical: false)

            VStack(spacing: Spacing.sm) {
                // Pointing at the column, which is where the chips are from here. In portrait they
                // are the row below and it points down at them.
                chipsAheadLine(pointing: "chevron.left")
                    .opacity(screen.chipsAreNext ? 1 : 0)
                    .animation(Motion.selection, value: screen.chipsAreNext)
                dial
                caption
            }
            .frame(width: Sizing.dialDiameter)
        }
        .environment(\.layoutDirection, .leftToRight)
        // **20 on three edges; the trailing one keeps its 24.**
        //
        // Landscape had 24 horizontal and 16 vertical, and the card is pinned to the wheel's height
        // — so every point the frame did not use showed up as a band of nothing around a card that
        // cannot grow into it. Tightening the leading edge and both verticals to a single 20 closes
        // that without moving the wheel, which keeps its own inset on the trailing side.
        .padding(.leading, Spacing.xl)
        .padding(.trailing, Spacing.xxl)
        .padding(.vertical, Spacing.xl)
        // **After the padding, deliberately.** The chip column pushes Back and Settings to the ends
        // of whatever height it is given, so the height has to be the screen's rather than the
        // tallest sibling's — otherwise the two controls that never move would move by however much
        // the caption beside them happened to wrap. Applied before the padding this would ask for
        // the full height and then add 32 to it, which overflows.
        .frame(maxHeight: .infinity)
    }

    /// The chips, the wheel and the caption — one band, in the same order whichever way the phone
    /// is held, so that what the thumb has learned survives a rotation.
    private var controls: some View {
        VStack(spacing: Spacing.lg) {
            chipBand
            dial
            caption
        }
    }

    /// The announcement and the chips it announces, as one band.
    ///
    /// They belong together: a line about the controls below it wants to arrive *next to* what it
    /// announces, not a full gap away.
    ///
    /// **Its space is held whether or not it is there.** Inserted and removed, it moved every band
    /// below it by its own height as the wheel crossed the last row — so the card resized under the
    /// thumb at the exact moment the line was asking you to keep turning. Reserved and faded, the
    /// layout is identical on every row and only the ink changes.
    ///
    /// Landscape does not use this: a 28-character sentence does not fit above a 52-point column,
    /// so there it sits above the dial and points sideways at the chips instead.
    private var chipBand: some View {
        VStack(spacing: Spacing.xs) {
            chipsAheadLine(pointing: "chevron.down")
                .opacity(screen.chipsAreNext ? 1 : 0)
                .animation(Motion.selection, value: screen.chipsAreNext)
            DialActionRow(actions: screen.actions, onCommand: onCommand)
        }
    }

    /// The header, ruled off from the content beneath it: where you are, and what is playing.
    ///
    /// **Back is not in here and is not in the card at all.** It was the first thing in this row,
    /// then a control in a bar along the card's foot, and it is a chip again — the card carried two
    /// control surfaces for a while, a bar inside it and the chip row twenty points below, both
    /// reaching for the same thumb.
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

    /// Which row the wheel is resting on, when the content is a list. `nil` for every other screen,
    /// which is what keeps the scroll-follow above inert on Now Playing, the recorder and the editor.
    private var highlightedRow: Int? {
        if case .list(let list) = screen.content { return list.highlighted }
        return nil
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
                // **The scroll view that actually scrolls, so the reader belongs here (#91).**
                //
                // `DialListView` used to carry its own, with the `scrollTo` on it. Once the rows
                // overran the card this branch was chosen, the inner view was handed unbounded
                // height, and it therefore always fitted — so its `scrollTo` was a no-op while the
                // clipping happened out here. Turning the wheel moved a highlight nobody could see.
                ScrollViewReader { proxy in
                    ScrollView {
                        content
                    }
                    .onChange(of: highlightedRow) { _, index in
                        guard let index else { return }
                        withAnimation(Motion.settle) { proxy.scrollTo(index, anchor: .center) }
                    }
                    // `onChange` cannot fire for a screen that ARRIVES with its highlight already
                    // deep in the list — a restored session, or Settings reached with About selected.
                    .task(id: highlightedRow) {
                        guard let index = highlightedRow else { return }
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        // **Wide, but only as tall as it needs to be.** `maxHeight: .infinity` made the card fill
        // whatever was left, so a three-row library was a third of a screen of nothing under three
        // rows. The stack below still gives it every point the dial does not want, so a long list
        // grows exactly as far as it can — it just no longer *claims* the space when empty.
        // **maxHeight belongs HERE, before the background.** Applied to `stage` from outside it
        // stretched the layout slot and left the drawn card at its content height, centred in a
        // taller invisible frame — which looks exactly like no change at all. The background is
        // attached on the next line, so whatever this frame reports is the card you see.
        //
        // `alignment: .top` so a short list stays at the top of the card rather than floating in
        // the middle of it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.sonicSurface, in: RoundedRectangle(cornerRadius: Radius.stage))
        // **The card's border no longer cycles while audio moves.** It was the wheel's, moved here,
        // and it was the one thing on the screen animating forever — which is what made a rotation
        // during playback animate the whole layout and never settle. What it said, the chrome
        // already says in words: `02:53 ▸ playing`, on every screen you can still be browsing from.
        .overlay(
            RoundedRectangle(cornerRadius: Radius.stage)
                .strokeBorder(Color.sonicBorder, lineWidth: Sizing.hairlineTrackHeight / 2)
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

    /// **The one thing nothing on screen admitted: the wheel does not stop at the last row.**
    ///
    /// Shown only where it is about to be true, which is what keeps it from being a fifth permanent
    /// caption. A list that has run out looks exactly like a wheel that has run out, and the chips
    /// became ring stops precisely so that no control on this screen could be drawn and unreachable
    /// — an affordance nobody finds is the same defect one step further along.
    private func chipsAheadLine(pointing glyph: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text("keep turning for the buttons")
            Image(systemName: glyph)
        }
        .font(.caption2)
        .foregroundColor(.sonicTextSecondary)
        .dynamicTypeSize(...Self.captionCeiling)
        // It describes the row below it, which VoiceOver reaches by swiping rather than by turning
        // — and its space is held on every row, so it must not be announced on the rows where it is
        // invisible.
        .accessibilityHidden(true)
    }

    /// **The caption is drawn again, and it is shorter than the one that was removed.**
    ///
    /// It went because it was the only thing teaching the gestures and it had grown to three
    /// clauses to do it — long enough that at AX5 it took a third of the screen from the list it was
    /// explaining. The four direction marks replaced it, and they are a legend: they say a stick
    /// moves without saying what a push does, and nothing at all said what the *wheel* does.
    ///
    /// So the sentence is split rather than restored. The always-true half — turn, press — is here;
    /// the four directions are names on the marks themselves, drawn while a thumb rests on the hub.
    private var caption: some View {
        Text(screen.hint)
            .font(.caption)
            .foregroundColor(.sonicTextSecondary)
            .multilineTextAlignment(.center)
            .dynamicTypeSize(...Self.captionCeiling)
            // Spoken by the dial, in full and with the nudges named — see `spokenHint`. Read here
            // as well it would be said twice, the second time without them.
            .accessibilityHidden(true)
    }

    /// The dial, and nothing else.
    ///
    /// **One component.** It briefly grew two spring-return segments beside it for volume and
    /// track; they worked and they were busy — three controls to drive one player is two too many,
    /// and the whole idea of the dial is that there is only ever one thing to touch. Those
    /// directions folded into the hub, which is now a gear stick.
    ///
    /// The caption under it is back and shorter, and the four direction marks now say their own
    /// names — see `caption` and `DialRing.directionMarks`.
    private var dial: some View {
        DialRing(
            ticks: screen.ring.ticks,
            hub: screen.ring.hub,
            defersPress: screen.ring.defersPress,
            directions: screen.ring.directions,
            volume: shownVolume,
            onCommand: onCommand
        )
        .accessibilityHint(spokenHint)
        // **Hidden until it has something to say.** Drawn permanently the arc was a second coloured
        // ring competing with the card's live border for the same glance, on a screen where the
        // thing you are looking at is what is playing. The question it answers — did that do
        // anything? — is only ever asked in the second after a nudge.
        .onChange(of: currentVolume) { _, level in
            guard let level else { return }
            shownVolume = level
            hideTask?.cancel()
            hideTask = Task {
                try? await Task.sleep(for: .seconds(Self.volumeLinger))
                guard !Task.isCancelled else { return }
                shownVolume = nil
            }
        }
        .onDisappear { hideTask?.cancel() }
    }

    /// The caption plus the four nudges, which is the whole sentence the hint used to be.
    ///
    /// **Composed rather than stored.** The nudge clause was prose in the navigator — "nudge to
    /// trim, move, delete or share" — beside a `Directions` value naming the same four things, so
    /// the sentence and the control could disagree and once did. Reading the names off the control
    /// makes that impossible, and it is the only way a VoiceOver user learns the stick at all: the
    /// marks are decoration to VoiceOver, and the reveal that teaches everyone else needs a thumb
    /// resting on a hub, which is not a gesture VoiceOver can make.
    private var spokenHint: Text {
        let names = [
            screen.ring.directions?.up,
            screen.ring.directions?.down,
            screen.ring.directions?.left,
            screen.ring.directions?.right
        ].compactMap { $0?.label }

        guard !names.isEmpty else { return Text(screen.hint) }
        return Text("\(screen.hint) · push the hub for \(names.joined(separator: ", "))")
    }

    /// The volume this screen is currently reporting, or `nil` where volume is not on show.
    ///
    /// `onChange` needs an `Equatable` to watch, and watching the whole screen would fire the pill
    /// on every tick of the clock.
    private var currentVolume: Double? {
        guard case .nowPlaying(let playing) = screen.content else { return nil }
        return playing.volume
    }

    /// How long the volume arc stays after the last nudge. Long enough that a run of nudges reads
    /// as one gesture rather than a flicker, short enough to be gone before you look away.
    private static let volumeLinger: Double = 1.5

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
