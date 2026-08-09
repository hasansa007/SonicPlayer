import SwiftUI

/// The dial: a ticked ring around a hub, and the whole of the dial navigator's input surface (#6).
///
/// **It owns no app state and knows nothing about playback, files or recording.** It renders a
/// `DialScreen.Ring` and emits `DialCommand`, which is what lets one component be a list's scroll,
/// a seek control and a live input-level meter without learning what any of those are.
///
/// The three tick modes are the reason it is one component rather than three. `browse` lights the
/// tick under the thumb, `position` fills proportionally so the ring doubles as a progress readout,
/// and `level` turns the ring into a meter — which is the idea that gives the wheel a job during
/// recording, the one activity it otherwise has none.
///
/// **Pinned to `.leftToRight`, deliberately**, following `RotaryWheel` and `PlayerView:319`: a
/// rotation points at the direction the *media* travels, not the direction text is read. Clockwise
/// is forward in Arabic too. `ScrubGeometry` records the measurement that makes this free — a
/// `DragGesture`'s `location.x` is not mirrored, so `atan2` already yields a physical angle.
struct DialRing: View {

    let ticks: DialScreen.Ticks
    let hub: DialScreen.Hub
    let onCommand: (DialCommand) -> Void

    /// A reference box rather than `@State var tracker = RotaryTracker()`. The tracker is a gesture
    /// accumulator nothing renders, so storing it through `@State` would invalidate this view on
    /// every touch move — up to 120 body evaluations a second — for a value no pixel depends on.
    /// `thumbAngle` below *is* `@State`, precisely because it is drawn.
    @State private var tracker = DialTrackerBox()
    @State private var thumbAngle: Double?

    // Hub press bookkeeping. Discrete events, so `@State` costs nothing here.
    @State private var isHubPressed = false
    @State private var didHold = false
    @State private var holdTask: Task<Void, Never>?
    @State private var lastPressAt: Date?

    /// 36 ticks, one every 10°. A count, not a dimension — it never becomes a layout token because
    /// nothing else in the app can share it.
    private static let tickCount = 36

    /// The level meter does not use the whole ring. It runs from 9 o'clock clockwise through the
    /// top, which puts the loud end where the thumb naturally rests and leaves the bottom of the
    /// ring — the part nearest the hand — unlit and therefore unread.
    private static let meterStart = 27
    private static let meterSpan = 17
    /// The last three ticks of the meter are the clip zone, drawn in red.
    private static let meterClipZone = 3

    /// How much of the ring the thumb's glow covers, as a fraction of the circle. Read twice — the
    /// trim, and the rotation that centres it under the thumb — so it is named once.
    private static let glowFraction: CGFloat = 0.08

    /// The plate's highlight, off-centre so the ring reads as lit from above-left rather than flat.
    private static let plateHighlight = UnitPoint(x: 0.38, y: 0.3)

    private static let dimTick: Double = 0.18
    private static let neighbourTick: Double = 0.4
    private static let plateTint: Double = 0.12

    var body: some View {
        ZStack {
            plate
            tickMarks
            thumbGlow
            hubView
        }
        .frame(width: Sizing.dialDiameter, height: Sizing.dialDiameter)
        // **The dial does not scale with Dynamic Type, and this is what enforces it.**
        //
        // Pinning the diameter is not enough: the hub's glyph is drawn with a Dynamic Type font, so
        // at AX5 it bursts its circle — the bug `RotaryWheel` already records. Capping the type
        // size inside the dial says the intended thing: this is a physical control, and one that
        // changes shape between accessibility settings is worse than one that stays put. Everything
        // above the dial scales normally.
        //
        // Nothing accessible is lost. The hub keeps its label and carries the adjustable action, so
        // VoiceOver turns the dial a detent at a time without needing it larger — and without
        // needing the rotation gesture, which VoiceOver cannot perform.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .environment(\.layoutDirection, .leftToRight)
        .gesture(turn)
        .onDisappear { holdTask?.cancel() }
    }

    // MARK: - Ring

    private var plate: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.sonicPrimary.opacity(Self.plateTint), Color.sonicSurface],
                    center: Self.plateHighlight,
                    startRadius: 0,
                    endRadius: Sizing.dialDiameter
                )
            )
            .overlay(
                Circle().strokeBorder(Color.sonicBorder, lineWidth: Sizing.hairlineTrackHeight / 2)
            )
            .sonicShadow(Elevation.artwork)
            .accessibilityHidden(true)
    }

    private var tickMarks: some View {
        ForEach(0 ..< Self.tickCount, id: \.self) { index in
            Capsule()
                .fill(tickColor(at: index))
                .frame(width: Sizing.hairlineTrackHeight, height: Sizing.dialTick)
                .offset(y: -(Sizing.dialDiameter / 2 - Spacing.sm - Sizing.dialTick / 2))
                .rotationEffect(.degrees(Double(index) / Double(Self.tickCount) * 360))
        }
        .animation(Motion.detent, value: ticks)
        .accessibilityHidden(true)
    }

    /// A short arc under the thumb, drawn in every tick mode.
    ///
    /// It is the only part of the dial that is view-local state, and it earns that: the ticks
    /// redraw when the navigator sends a new `DialScreen`, which is a round trip, and a control
    /// with no response until the round trip lands feels broken rather than lagged.
    @ViewBuilder
    private var thumbGlow: some View {
        if let thumbAngle {
            Circle()
                .trim(from: 0, to: Self.glowFraction)
                .stroke(
                    Color.sonicPrimary,
                    style: StrokeStyle(lineWidth: Sizing.wheelArcWidth, lineCap: .round)
                )
                // `trim` starts at 12 o'clock and `atan2` reports 0° at 3 o'clock, so the arc is
                // rotated back a quarter turn — then back again by half its own length, so it sits
                // centred under the thumb rather than trailing it.
                .rotationEffect(.degrees(thumbAngle - 90 - Self.glowFraction * 180))
                .padding(Spacing.xs)
                .animation(Motion.detent, value: thumbAngle)
                .accessibilityHidden(true)
        }
    }

    private func tickColor(at index: Int) -> Color {
        switch ticks {
        case .browse(let thumb):
            guard let thumb else { return dim }
            let lit = Int((thumb * Double(Self.tickCount)).rounded()) % Self.tickCount
            switch Self.ringDistance(index, lit, of: Self.tickCount) {
            // The contract says the thumb lights *one* tick. The neighbours are lit at a fraction
            // rather than fully — that is an antialiasing skirt on a 10° step, not a second tick.
            case 0: return .sonicPrimary
            case 1: return Color.sonicPrimary.opacity(Self.neighbourTick)
            default: return dim
            }

        case .position(let fraction):
            return Double(index) < fraction * Double(Self.tickCount) ? .sonicPrimary : dim

        case .level(let level):
            let offset = (index - Self.meterStart + Self.tickCount) % Self.tickCount
            guard offset < Self.meterSpan else { return dim }
            guard Double(offset) < level * Double(Self.meterSpan) else { return dim }
            return offset >= Self.meterSpan - Self.meterClipZone ? .red : .sonicPrimary
        }
    }

    private var dim: Color { Color.sonicTextSecondary.opacity(Self.dimTick) }

    /// Ticks either side of the seam are neighbours: 35 and 0 are one step apart, not 35.
    private static func ringDistance(_ a: Int, _ b: Int, of count: Int) -> Int {
        let raw = abs(a - b)
        return min(raw, count - raw)
    }

    // MARK: - Hub

    private var hubView: some View {
        ZStack {
            // `sonicBackground` rather than `sonicSurface`, so the hub reads as sunk into the
            // plate rather than sitting on it. The edge is at 0.35 for the reason `RotaryWheel`
            // records against its ring: `sonicBackground` is near-white in light mode, where a
            // fifth-opacity teal hairline is effectively invisible and the hub disappears into
            // the plate. The shadow is what gives it a lit edge in both.
            Circle()
                .fill(Color.sonicBackground)
                .overlay(Circle().fill(hubTint))
                .overlay(
                    Circle().strokeBorder(
                        Color.sonicPrimary.opacity(Self.hubEdge),
                        lineWidth: Sizing.hairlineTrackHeight / 2
                    )
                )
                .frame(width: Sizing.dialHub, height: Sizing.dialHub)
                .sonicShadow(Elevation.control)

            hubContent
        }
        .scaleEffect(isHubPressed ? Self.pressedScale : 1)
        .animation(Motion.press, value: isHubPressed)
        .contentShape(Circle())
        .gesture(hubPress)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(hubLabel)
        // The press is a raw drag, which VoiceOver cannot perform, so activation is wired
        // explicitly. Without this the hub is announced and then does nothing.
        .accessibilityAction { onCommand(.press) }
        // The adjustable behaviour hangs off the hub because it is the element VoiceOver reliably
        // lands on. A swipe up or down is one detent — the dial's full precision, no gesture.
        // Double-press and hold are deliberately *not* here: both are shortcuts, and the contract
        // requires each to have a visible partner in the action row, which VoiceOver reaches.
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCommand(.tick(1))
            case .decrement: onCommand(.tick(-1))
            @unknown default: break
            }
        }
    }

    private static let pressedScale: CGFloat = 0.96
    private static let hubEdge: Double = 0.35

    @ViewBuilder
    private var hubContent: some View {
        switch hub {
        case .label(let word):
            Text(word)
                .font(.caption2)
                .fontWeight(.semibold)
                .tracking(DialFont.breadcrumbTracking)
                .foregroundColor(.sonicPrimary)

        case .glyph(let systemImage):
            Image(systemName: systemImage)
                .font(.sonicTransportGlyph)
                .foregroundColor(.sonicPrimary)

        case .recordDot:
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Color.red)
                .frame(width: Sizing.dialRecordDot, height: Sizing.dialRecordDot)
        }
    }

    private var hubTint: Color {
        if case .recordDot = hub { return Color.red.opacity(Self.plateTint) }
        return .clear
    }

    /// The hub's spoken name.
    ///
    /// `.label` already carries a word, so it is used verbatim. `.glyph` does not — an SF Symbol
    /// name is not a sentence — so the two the navigator actually sends are mapped and anything
    /// else falls back to the neutral verb every hub performs.
    private var hubLabel: Text {
        switch hub {
        case .label(let word):
            return Text(word)
        case .glyph(let systemImage):
            switch systemImage {
            case "pause.fill": return Text("Pause")
            case "play.fill": return Text("Play")
            default: return Text("Select")
            }
        case .recordDot:
            return Text("Stop recording")
        }
    }

    // MARK: - The turn

    private var turn: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let centre = CGPoint(x: Sizing.dialDiameter / 2, y: Sizing.dialDiameter / 2)
                if thumbAngle == nil, !tracker.value.began(at: value.startLocation, centre: centre) {
                    return
                }
                let step = tracker.value.moved(
                    to: value.location,
                    centre: centre,
                    at: value.time.timeIntervalSinceReferenceDate
                )
                thumbAngle = Self.degrees(of: value.location, centre: centre)
                guard step.detents != 0 else { return }
                onCommand(.tick(step.detents * step.multiplier))
            }
            .onEnded { _ in
                tracker.value.ended()
                thumbAngle = nil
            }
    }

    private static func degrees(of point: CGPoint, centre: CGPoint) -> Double {
        atan2(Double(point.y - centre.y), Double(point.x - centre.x)) * 180 / .pi
    }

    // MARK: - The press

    /// A raw drag rather than a `Button`, because the hub has to tell three gestures apart and a
    /// `Button` fires its action on release even after a long press.
    private var hubPress: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isHubPressed else { return }
                isHubPressed = true
                didHold = false
                holdTask = Task {
                    try? await Task.sleep(for: .seconds(DialCommand.holdDuration))
                    guard !Task.isCancelled else { return }
                    didHold = true
                    onCommand(.hold)
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                holdTask = nil
                isHubPressed = false
                guard !didHold else { return }
                registerPress()
            }
    }

    /// **The press fires immediately and a double-press escalates it.**
    ///
    /// The alternative is to hold every press for `doublePressWindow` to find out whether a second
    /// one is coming, which puts 300ms of lag on the single most-used gesture in the app to serve
    /// the rarest. So `.press` goes out on the first release, and a second release inside the
    /// window sends `.doublePress` rather than another `.press`.
    ///
    /// The navigator therefore sees `press` then `doublePress`, and must read the second as
    /// *escalate what the first did* — on 1b, open the recording, then open its editor. That reads
    /// the same way the gesture feels. **Flagged to the navigator's author: if `doublePress` is
    /// expected to arrive alone, this is the half that has to change.**
    private func registerPress() {
        let now = Date()
        if let lastPressAt, now.timeIntervalSince(lastPressAt) <= DialCommand.doublePressWindow {
            self.lastPressAt = nil
            onCommand(.doublePress)
        } else {
            lastPressAt = now
            onCommand(.press)
        }
    }
}

/// See `DialRing.tracker`. Exists only so gesture accumulation does not redraw the view.
@MainActor
private final class DialTrackerBox {
    var value = RotaryTracker()
}
