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

    /// **A glyph in a circle where the action has one, a word in a capsule where it does not.**
    ///
    /// The words were the original design and they cost a band of the card's height on every
    /// screen: five chips across a phone wrapped to two lines at ordinary text sizes in Arabic, and
    /// at AX3 in English. A symbol says `Back` in the space the word `‹ Back` needed for its
    /// chevron alone.
    ///
    /// The label has not gone anywhere — it is the accessibility label, so nothing is lost to
    /// VoiceOver, and a chip with no icon still draws it. That fallback is not decorative: an
    /// action whose meaning has no honest symbol should say so in words rather than pick a vague
    /// one, which is how a glyph row turns into a guessing game.
    private func chip(_ action: DialScreen.Action) -> some View {
        Button {
            onCommand(.action(action.id))
        } label: {
            Group {
                if let symbol = DialIcon.systemImage(for: action.icon) {
                    Image(systemName: symbol)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        // A fixed square under the padding, so every glyph chip is the same
                        // capsule whatever its symbol is wide — `repeat.1` is noticeably wider
                        // than `shuffle`, and a row of different-sized pills reads as a mistake.
                        .frame(width: Sizing.compactControl)
                } else {
                    Text(action.label)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
            }
            // **The padding is the chip.** The glyph version first shipped as a bare 28pt square,
            // which made a control that is pressed constantly smaller than the 44 points Apple
            // documents as the minimum — and read as an icon someone had forgotten to style rather
            // than as a button. Shared by both forms so a mixed row lines up.
            //
            // Wider than it is tall on purpose: a capsule whose ends are a semicircle needs visible
            // straight sides or it reads as a circle, which is a different control. `xxl` against
            // `sm` is what gives it those sides at a 28pt glyph.
            .frame(minHeight: Sizing.compactControl)
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.sm)
            .foregroundColor(foreground(action.emphasis))
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
        // Destructive keeps a light label for the same reason: it sits on a filled surface too,
        // just an orange one.
        case .destructive: .white
        case .plain: .sonicTextPrimary
        case .disabled: .sonicTextMuted
        }
    }

    /// `AnyShapeStyle` rather than `some View`, because `.background(_:in:)` fills a shape with a
    /// *style* — the erasure is the price of choosing between a gradient and a colour.
    private func background(_ emphasis: DialScreen.Action.Emphasis) -> AnyShapeStyle {
        switch emphasis {
        case .primary, .selected: AnyShapeStyle(DialSurface.fill)
        // Filled, like `.primary`, but never the accent. "The thing this screen expects" and "the
        // thing you cannot take back" must not be the same colour — `Record` and `Delete` are both
        // the obvious action on their screen, and only one is recoverable.
        case .destructive: AnyShapeStyle(Color.sonicOrange)
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
