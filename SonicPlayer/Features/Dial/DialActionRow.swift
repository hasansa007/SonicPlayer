import SwiftUI

/// The row of chips between the content and the dial (#6).
///
/// **These are touch targets and the dial is the wheel** — the two are equals, not a primary and a
/// fallback. The earlier prototype hung four labels off the ring's cardinal points, which capped a
/// screen at four actions and made each of them tiny; moving them here is what let `DialCommand`
/// collapse to a single `.action(id:)` case.
///
/// **The row wraps to two lines rather than scrolling**, so a screen may carry two chips or five
/// without the layout deciding which. The trim editor is the five.
///
/// Scrolling was the first attempt and was wrong: chips four and five sat off the right edge with
/// nothing saying they existed, on the one screen that needs all five reachable. A second line
/// costs 30 points and shows everything. The horizontal scroll survives only as the last resort
/// for a chip so long that even half a row cannot hold it.
struct DialActionRow: View {

    let actions: [DialScreen.Action]
    let onCommand: (DialCommand) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips(actions)
            wrapped
            ScrollView(.horizontal) { chips(actions) }
                .scrollIndicators(.hidden)
        }
    }

    /// Split down the middle with the remainder on the first line, which keeps the heavier row on
    /// top and reads as one block rather than as a row and an afterthought.
    private var wrapped: some View {
        let split = (actions.count + 1) / 2
        return VStack(spacing: Spacing.sm) {
            chips(Array(actions.prefix(split)))
            chips(Array(actions.dropFirst(split)))
        }
    }

    private func chips(_ actions: [DialScreen.Action]) -> some View {
        HStack(spacing: Spacing.sm) {
            ForEach(actions) { action in
                chip(action)
            }
        }
        .padding(.horizontal, Spacing.xxs)
    }

    private func chip(_ action: DialScreen.Action) -> some View {
        Button {
            onCommand(.action(action.id))
        } label: {
            Text(action.label)
                .font(.footnote)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundColor(foreground(action.emphasis))
                .padding(.horizontal, Sizing.chipInsetH)
                .padding(.vertical, Spacing.sm)
                .background(background(action.emphasis), in: Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(action.emphasis == .disabled)
        .accessibilityLabel(Self.spokenLabel(for: action.label))
        .accessibilityAddTraits(action.emphasis == .selected ? [.isSelected] : [])
    }

    private func foreground(_ emphasis: DialScreen.Action.Emphasis) -> Color {
        switch emphasis {
        // White rather than `sonicTextPrimary`: both of these sit on filled teal, which stays teal
        // in light mode, so the label has to stay light too.
        case .primary, .selected: .white
        case .plain: .sonicTextPrimary
        case .disabled: .sonicTextMuted
        }
    }

    /// `AnyShapeStyle` rather than `some View`, because `.background(_:in:)` fills a shape with a
    /// *style* — the erasure is the price of choosing between a gradient and a colour.
    private func background(_ emphasis: DialScreen.Action.Emphasis) -> AnyShapeStyle {
        switch emphasis {
        case .primary, .selected: AnyShapeStyle(DialSurface.fill)
        case .plain, .disabled: AnyShapeStyle(Color.sonicPrimary.opacity(ControlTint.on))
        }
    }

    /// What VoiceOver says, which is not always what is drawn.
    ///
    /// A chip's label is navigator content and the design puts glyphs inside it — `‹ Back`,
    /// `＋ Marker`, `•••`. Read literally those become "left-pointing angle quotation mark, Back",
    /// which is noise, and `•••` becomes nothing usable at all. Stripping the decoration here is
    /// the smallest fix; the alternative is a field on `DialScreen.Action` the contract does not
    /// have, and the design's glyphs are decoration in every case so far.
    private static func spokenLabel(for label: String) -> Text {
        let stripped = label
            .trimmingCharacters(in: CharacterSet(charactersIn: "‹›＋+•·▸▶●◀ "))
        return stripped.isEmpty ? Text("More options") : Text(stripped)
    }
}
