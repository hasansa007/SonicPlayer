import SwiftUI

/// An icon button with a guaranteed tap target (#47).
///
/// Consumers today: skip ±, repeat, shuffle and queue in `PlayerView`; previous, next and
/// play/pause in `MiniPlayerView`. Seven, across both player files.
///
/// **It exists to make an undersized control impossible.** `MiniPlayerView`'s previous and next
/// buttons were a bare `Image` with no frame — roughly 20 × 17 points of tappable area against
/// Apple's documented 44 × 44 minimum. Passing `.standard` here cannot produce that, and a
/// smaller target now requires asking for `.compact` by name, which is a decision someone has to
/// write down rather than one they can fall into.
struct IconControlButton: View {

    enum Size {
        /// 44 — the minimum, and the default for anything tappable.
        case standard
        /// 28 — the mini-player's close button. Deliberately below the minimum and deliberately
        /// hard to reach: it is destructive-adjacent (it ends the session) and sits beside the
        /// transport controls, so a large target here would cause more mistakes than it prevents.
        case compact
        /// 56 — previous / next on the full player.
        case secondary

        var side: CGFloat {
            switch self {
            case .standard: Sizing.tapTarget
            case .compact: Sizing.compactControl
            case .secondary: Sizing.secondaryControl
            }
        }
    }

    /// How the button paints behind its glyph.
    enum Style {
        /// No background — the transport controls.
        case plain
        /// A tinted rounded square that reads as on or off — repeat, shuffle, queue.
        case toggle(isOn: Bool)
    }

    let systemImage: String
    let label: Text
    var size: Size = .standard
    var style: Style = .plain
    var font: Font = .sonicControlGlyph
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(font)
                // The glyph is capped so it cannot outgrow the frame around it. Without this the
                // frame stayed 44pt while `.title3` kept scaling, and at AX5 the repeat / shuffle
                // / queue glyphs overlapped each other.
                //
                // Letting the *frame* grow instead was tried and is worse: the player's portrait
                // layout is a fixed, non-scrolling `VStack` around a 280pt artwork, so larger
                // controls push the tool row off the bottom of the screen entirely. Both states
                // are in `artifacts/after/`. Icons carry no text, so bounding them costs a
                // reader nothing — the title, the times and the queue still scale to AX5.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundColor(tint)
                .frame(width: size.side, height: size.side)
                .background(background)
        }
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var isSelected: Bool {
        if case .toggle(let isOn) = style { return isOn }
        return false
    }

    private var tint: Color {
        guard isEnabled else { return .sonicTextMuted }
        switch style {
        case .plain: return .sonicPrimary
        case .toggle(let isOn): return isOn ? .sonicPrimary : .sonicTextMuted
        }
    }

    @ViewBuilder
    private var background: some View {
        if case .toggle(let isOn) = style {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(Color.sonicPrimary.opacity(isOn ? ControlTint.on : ControlTint.off))
        }
    }
}

/// The two background tints a toggle may have.
///
/// Named because the old code used *three* values for two states: repeat and shuffle painted
/// `0.05` when off and `0.1` when on, while the queue toggle used `0.1` and `0.15` — so "off"
/// and "on" looked different depending on which control you were looking at.
enum ControlTint {
    static let off: Double = 0.05
    static let on: Double = 0.1
}

#Preview("States") {
    VStack(spacing: Spacing.xl) {
        HStack(spacing: Spacing.lg) {
            IconControlButton(systemImage: "gobackward.15", label: Text("Skip back")) {}
            IconControlButton(systemImage: "goforward.15", label: Text("Skip forward")) {}
            IconControlButton(
                systemImage: "backward.end.fill", label: Text("Previous"), size: .secondary,
                font: .sonicTransportGlyph
            ) {}
            IconControlButton(
                systemImage: "forward.end.fill", label: Text("Next"), size: .secondary,
                font: .sonicTransportGlyph, isEnabled: false
            ) {}
        }
        HStack(spacing: Spacing.lg) {
            IconControlButton(
                systemImage: "repeat", label: Text("Repeat"), style: .toggle(isOn: false)
            ) {}
            IconControlButton(
                systemImage: "shuffle", label: Text("Shuffle"), style: .toggle(isOn: true)
            ) {}
            IconControlButton(
                systemImage: "list.bullet.rectangle", label: Text("Queue"), style: .toggle(isOn: true)
            ) {}
            IconControlButton(
                systemImage: "xmark", label: Text("Close"), size: .compact, font: .caption
            ) {}
        }
    }
    .padding(Spacing.xxl)
}
