import SwiftUI

/// A spring-return three-position switch, horizontal or vertical (#6).
///
/// **Momentary, not stable.** The knob rests in the centre and springs back the instant you let go,
/// because these are things you *do* rather than places you *are* — a switch that stayed at one end
/// would be claiming a state the app does not have. Three positions; only the centre is somewhere
/// it stays.
///
/// Two of these plus the wheel is the whole control cluster:
///
///     ┌───────────────┐
///     │  ◀   |   ▶    │   track — horizontal, above
///     └───────────────┘
///     ┌───┐  ╭─────────╮
///     │ + │  │         │
///     │ ─ │  │  seek   │   volume — vertical, beside
///     └───┘  ╰─────────╯
///
/// **This is what let the big wheel stop having modes.** Volume and track-stepping were two thirds
/// of a mode selector, which made "what does the wheel do right now" a question the user had to
/// hold. Giving each its own surface removes the question rather than answering it faster.
///
/// A segment also has no radius, which is why it beats a second small wheel here:
/// `RotaryTracker.deadZoneRadius` is 34pt, so any wheel under ~100pt across is almost entirely dead
/// zone and does not turn at all.
///
/// Both ends are plain tap targets as well as drag targets, so it works with no slide at all —
/// which is what keeps it usable under VoiceOver and for anyone who never discovers the gesture.
struct DialTriState: View {

    enum Axis: Equatable {
        /// Left decreases, right increases. Never mirrors under RTL: these point at the direction
        /// the *media* travels, the same reason `PlayerView`'s transport row is pinned.
        case horizontal
        /// **Up increases.** The screen's y grows downward, so the gesture maths inverts — which is
        /// the one place this component has to think, and it does it in `commit` rather than
        /// leaving each caller to remember.
        case vertical
    }

    let axis: Axis
    let decreaseImage: String
    let increaseImage: String
    let decreaseLabel: Text
    let increaseLabel: Text
    let onDecrease: () -> Void
    let onIncrease: () -> Void
    var isEnabled: Bool = true

    @State private var offset: CGFloat = 0

    /// How far the knob travels before the gesture counts. Short enough to feel light, long enough
    /// that a thumb resting on the control does not fire it.
    private static let commitThreshold: CGFloat = 14

    private var isHorizontal: Bool { axis == .horizontal }
    private var length: CGFloat { Sizing.dialSegmentLength }
    private var breadth: CGFloat { Sizing.dialSegmentBreadth }

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.sonicPrimary.opacity(ControlTint.on))

            // The increase end comes first vertically, because up means more.
            stack {
                end(isHorizontal ? decreaseImage : increaseImage,
                    isHorizontal ? decreaseLabel : increaseLabel,
                    isHorizontal ? onDecrease : onIncrease)
                end(isHorizontal ? increaseImage : decreaseImage,
                    isHorizontal ? increaseLabel : decreaseLabel,
                    isHorizontal ? onIncrease : onDecrease)
            }

            Capsule()
                .fill(DialSurface.fill)
                .frame(
                    width: isHorizontal ? breadth : breadth - Spacing.sm,
                    height: isHorizontal ? breadth - Spacing.sm : breadth
                )
                .offset(x: isHorizontal ? offset : 0, y: isHorizontal ? 0 : offset)
                .allowsHitTesting(false)
                .opacity(isEnabled ? 1 : ControlTint.on)
        }
        .frame(
            width: isHorizontal ? length : breadth,
            height: isHorizontal ? breadth : length
        )
        .environment(\.layoutDirection, .leftToRight)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .gesture(slide)
        .animation(Motion.settle, value: offset)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func stack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if isHorizontal {
            HStack(spacing: 0, content: content)
        } else {
            VStack(spacing: 0, content: content)
        }
    }

    private func end(_ systemImage: String, _ label: Text, _ action: @escaping () -> Void) -> some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundColor(isEnabled ? .sonicTextSecondary : .sonicTextMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private var slide: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard isEnabled else { return }
                let travel = isHorizontal ? value.translation.width : value.translation.height
                offset = min(max(-Sizing.dialSegmentTravel, travel), Sizing.dialSegmentTravel)
            }
            .onEnded { _ in
                let settled = offset
                offset = 0
                guard isEnabled, abs(settled) >= Self.commitThreshold else { return }
                commit(settled)
            }
    }

    /// Horizontal: right increases. Vertical: **up** increases, and up is a *negative* offset,
    /// which is the inversion that lives here so no caller has to remember it.
    private func commit(_ settled: CGFloat) {
        let increasing = isHorizontal ? settled > 0 : settled < 0
        increasing ? onIncrease() : onDecrease()
    }
}

extension DialTriState {

    /// Previous / next track.
    static func track(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) -> DialTriState {
        DialTriState(
            axis: .horizontal,
            decreaseImage: "backward.end.fill",
            increaseImage: "forward.end.fill",
            decreaseLabel: Text("Previous track"),
            increaseLabel: Text("Next track"),
            onDecrease: onPrevious,
            onIncrease: onNext
        )
    }

    /// Volume down / up. Moves the app's own output level — iOS does not let an app set *system*
    /// volume, so this will not move the ringer HUD or agree with the hardware buttons.
    static func volume(onDown: @escaping () -> Void, onUp: @escaping () -> Void) -> DialTriState {
        DialTriState(
            axis: .vertical,
            decreaseImage: "speaker.fill",
            increaseImage: "speaker.wave.2.fill",
            decreaseLabel: Text("Volume down"),
            increaseLabel: Text("Volume up"),
            onDecrease: onDown,
            onIncrease: onUp
        )
    }
}
