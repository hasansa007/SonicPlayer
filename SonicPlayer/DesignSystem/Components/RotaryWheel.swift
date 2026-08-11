import SwiftUI

/// The ring, its four tap targets, the hub, and the lit arc (#6).
///
/// **It owns no app state and knows nothing about playback.** It emits `WheelCommand` and that is
/// all — which is what lets slices 2 and 3 point it at a menu and a trim editor unchanged.
///
/// **Pinned to `.leftToRight`, deliberately.** `PlayerView.swift:319` pins transport for the same
/// reason: these controls point at the direction the *media* travels, not the direction text is
/// read. Pinning also removes any question of whether a rotation transform mirrors — a question
/// that produced two wrong bug reports in this repo (#54, #63) before anyone measured it. The drag
/// maths needs no help either way: `ScrubGeometry` records that a `DragGesture`'s `location.x` is
/// **not** mirrored, so `atan2` already yields a physical angle.
struct RotaryWheel: View {

    let hubLabel: String
    let isPlaying: Bool
    let onCommand: (WheelCommand) -> Void

    /// A reference box rather than `@State var tracker = RotaryTracker()`.
    ///
    /// The tracker is a gesture accumulator that nothing renders, so writing it through `@State`
    /// would invalidate this view on every touch move — up to 120 body evaluations a second — to
    /// store a value no pixel depends on. `thumbAngle` below is `@State` precisely because it *is*
    /// drawn.
    @State private var tracker = TrackerBox()
    @State private var thumbAngle: Double?

    private var diameter: CGFloat { Sizing.wheelDiameter }

    /// How much of the ring the lit arc covers, as a fraction of the whole circle. Read twice — the
    /// trim itself, and the rotation that centres it under the thumb — so it is named once.
    private static let arcFraction: CGFloat = 0.08

    var body: some View {
        ZStack {
            ring
            targets
            hub
        }
        .frame(width: diameter, height: diameter)
        // **The wheel does not scale with Dynamic Type, and this is what enforces it.**
        //
        // Pinning `Sizing.wheelDiameter` was not enough: the glyphs are drawn with
        // `.sonicControlGlyph`, which *is* a Dynamic Type font, so at AX5 the transport arrows grew
        // outside the ring and the hub's bars burst their circle. Capping the type size inside the
        // wheel says the intended thing — this is a physical control, and a control that changes
        // shape between accessibility settings is worse than one that stays put. Everything above
        // the wheel scales normally.
        //
        // Accessibility is not lost by this: every target keeps its label, and the hub carries the
        // adjustable action, so VoiceOver drives the whole wheel without needing it to be larger.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .environment(\.layoutDirection, .leftToRight)
        .gesture(turn)
    }

    // MARK: - Pieces

    private var ring: some View {
        ZStack {
            // 0.35, not the 0.2 the dark mockups used. `sonicBackground` is near-white in light
            // mode, where a fifth-opacity teal hairline is effectively invisible — the ring read
            // as absent on the first device build.
            Circle()
                .strokeBorder(Color.sonicPrimary.opacity(0.35), lineWidth: Sizing.hairlineTrackHeight)

            if let thumbAngle {
                Circle()
                    .trim(from: 0, to: Self.arcFraction)
                    .stroke(
                        Color.sonicPrimary,
                        style: StrokeStyle(lineWidth: Sizing.wheelArcWidth, lineCap: .round)
                    )
                    // `trim` starts at 12 o'clock and `atan2` reports 0° at 3 o'clock, so the arc
                    // is rotated back a quarter turn — then back again by half its own length, so
                    // it sits centred under the thumb rather than trailing it.
                    .rotationEffect(.degrees(thumbAngle - 90 - Self.arcFraction * 180))
                    .animation(Motion.detent, value: thumbAngle)
            }
        }
        .accessibilityHidden(true)
    }

    /// The four taps. Separate labelled elements, so VoiceOver reaches the whole app without the
    /// rotation gesture — which it cannot perform.
    private var targets: some View {
        ZStack {
            target("chevron.up", Text("Back"), at: .top) { onCommand(.back) }
            target("backward.end.fill", Text("Previous track"), at: .leading) {
                onCommand(.transport(.previous))
            }
            target("forward.end.fill", Text("Next track"), at: .trailing) {
                onCommand(.transport(.next))
            }
            target("line.3.horizontal", Text("Menu"), at: .bottom) { onCommand(.menu) }
        }
    }

    private func target(
        _ systemImage: String,
        _ label: Text,
        at edge: Alignment,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.sonicControlGlyph)
                .foregroundColor(.sonicTextSecondary)
                .frame(width: Sizing.compactControl, height: Sizing.compactControl)
        }
        .accessibilityLabel(label)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge)
        .padding(Spacing.sm)
    }

    private var hub: some View {
        Button {
            onCommand(.select)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.sonicSurface)
                    .frame(width: Sizing.wheelHub, height: Sizing.wheelHub)
                    .sonicShadow(Elevation.control)

                Text(hubLabel)
                    .font(.sonicControlGlyph)
                    .foregroundColor(.sonicPrimary)
            }
        }
        .accessibilityLabel(Text(isPlaying ? "Pause" : "Play"))
        // The adjustable behaviour hangs off the hub because it is the element VoiceOver reliably
        // lands on. A swipe up or down is one detent — the wheel's full precision, no gesture.
        .accessibilityValue(Text(hubLabel))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCommand(.tick(1))
            case .decrement: onCommand(.tick(-1))
            @unknown default: break
            }
        }
    }

    // MARK: - The turn

    private var turn: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let centre = CGPoint(x: diameter / 2, y: diameter / 2)
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
}

/// See `RotaryWheel.tracker`. Exists only so gesture accumulation does not redraw the view.
@MainActor
private final class TrackerBox {
    var value = RotaryTracker()
}
