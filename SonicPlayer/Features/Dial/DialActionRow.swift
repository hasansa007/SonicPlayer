import SwiftUI

/// The row of chips between the content and the dial (#6).
///
/// **These are touch targets and the dial is the wheel** — the two are equals, not a primary and a
/// fallback. The earlier prototype hung four labels off the ring's cardinal points, which capped a
/// screen at four actions and made each of them tiny; moving them here is what let `DialCommand`
/// collapse to a single `.action(id:)` case.
///
/// **Back leads, Settings trails, and the screen's own verbs sit between them.** The two controls
/// that mean the same thing everywhere never move; only the middle changes.
///
/// Both ends are drawn on every screen that has a row, **disabled where they would refuse** — no
/// Back at the library root, no Settings inside Settings. Removing them outright was tried and read
/// as a fault: a row of five where every other screen has six is a row with something missing from
/// it. What changed instead is that the wheel does not stop on a disabled chip, so the row keeps its
/// shape for the eye without costing a detent.
///
/// **It falls back to two lines rather than scrolling** when it cannot fit — which is what happens
/// at accessibility text sizes, since the glyphs scale. Scrolling was the first attempt and was
/// wrong: a chip off the right edge has nothing saying it exists, and every chip here is now a stop
/// on the wheel as well, so an invisible one is a stop nobody knows to turn to.
struct DialActionRow: View {

    let actions: [DialScreen.Action]
    let onCommand: (DialCommand) -> Void

    /// **Horizontal in portrait, vertical in landscape**, where the screen is under 400 points tall
    /// and the wheel alone is 262 of them. Stacking the row above the dial there left nothing for
    /// either — the card was crushed and the wheel ran off the bottom edge. Turned on its side the
    /// row costs width, which landscape has in abundance, and the dial keeps the size your thumb
    /// learned in portrait.
    var axis: Axis = .horizontal

    var body: some View {
        switch axis {
        case .horizontal:
            ViewThatFits(in: .horizontal) {
                oneLine
                twoLines
            }
        case .vertical:
            ViewThatFits(in: .vertical) {
                column
                pairedColumns
            }
        }
    }

    /// The same arrangement read top to bottom: Back at one end, Settings at the other, the
    /// screen's verbs between — **and the two spacers are the whole point**, exactly as in
    /// `oneLine`.
    ///
    /// Without them the column hugs its contents, so a screen with two verbs draws a short stack
    /// and a screen with four draws a tall one, and the two controls that mean the same thing
    /// everywhere are somewhere different on each. Pushed to the ends of the height the column is
    /// given, they hold still and only the middle changes — which is what portrait has always done
    /// horizontally.
    private var column: some View {
        VStack(spacing: Spacing.sm) {
            end("back")
            // `minLength` rather than zero so this still has an ideal height for `ViewThatFits` to
            // measure against — a column of pure spacers always "fits", and the two-column fallback
            // would never be reached.
            Spacer(minLength: Spacing.sm)
            ForEach(middle) { action in chip(action) }
            Spacer(minLength: Spacing.sm)
            end("settings")
        }
    }

    /// **The vertical answer to `twoLines`, and for the same reason.** Six chips down a landscape
    /// screen is about 320 points of its roughly 370, so at accessibility text sizes the column runs
    /// off the bottom. It spends width, which landscape has and portrait does not — and it keeps
    /// every chip visible, which scrolling would not: a chip nobody can see is a stop nobody knows
    /// to turn to.
    private var pairedColumns: some View {
        let half = (middle.count + 1) / 2
        return HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(spacing: Spacing.sm) {
                end("back")
                ForEach(Array(middle.prefix(half))) { chip($0) }
                Spacer(minLength: 0)
            }
            VStack(spacing: Spacing.sm) {
                Spacer(minLength: 0)
                ForEach(Array(middle.dropFirst(half))) { chip($0) }
                end("settings")
            }
        }
    }

    private var oneLine: some View {
        HStack(spacing: Spacing.sm) {
            end("back")

            Spacer(minLength: 0)

            // **What this screen does, and only this screen.** Between the two fixed ends, so the
            // controls that mean the same thing everywhere never move and the middle is free to
            // change per screen without dragging them sideways.
            ForEach(middle) { action in
                chip(action)
            }

            Spacer(minLength: 0)

            end("settings")
        }
        .padding(.horizontal, Spacing.xxs)
    }

    /// The ends keep their corners; the middle drops below them. Used only when the row genuinely
    /// cannot fit, which on a 393pt screen means accessibility text sizes.
    private var twoLines: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                end("back")
                Spacer(minLength: 0)
                end("settings")
            }
            HStack(spacing: Spacing.sm) {
                ForEach(middle) { action in chip(action) }
            }
        }
        .padding(.horizontal, Spacing.xxs)
    }

    /// One of the two fixed ends.
    ///
    /// **The navigator supplies both on every screen that has a row at all**, disabling rather than
    /// dropping the ones that would refuse — so nothing has to be reserved here and the row is the
    /// same shape everywhere by construction. The one screen with no ends is the delete guard,
    /// whose whole row is empty; a placeholder here would give it a band of height for two controls
    /// it deliberately does not have.
    @ViewBuilder
    private func end(_ id: String) -> some View {
        if let action = actions.first(where: { $0.id == id }) {
            chip(action)
        }
    }

    /// Everything that is neither of the two fixed ends.
    private var middle: [DialScreen.Action] {
        actions.filter { $0.id != "back" && $0.id != "settings" }
    }

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
            // straight sides or it reads as a circle, which is a different control.
            //
            // **`md` rather than the `xxl` this started at, because the row grew.** At 24pt of
            // horizontal padding a chip is 76 wide, and six of them — Back, Record, Import, New
            // folder, Sort, Settings — is 456 against roughly 345 of usable screen. 12pt gives 52,
            // and six of those fit with room over. It is still a capsule; it is not the bare 28pt
            // square this replaced.
            .frame(minHeight: Sizing.compactControl)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .foregroundColor(foreground(action.emphasis))
            .background(background(action.emphasis), in: Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(action.emphasis == .disabled)
        .accessibilityLabel(Self.spokenLabel(for: action.label))
        .accessibilityAddTraits(action.emphasis == .active ? [.isSelected] : [])
    }

    private func foreground(_ emphasis: DialScreen.Action.Emphasis) -> Color {
        switch emphasis {
        // White rather than `sonicTextPrimary`: both of these sit on filled teal, which stays teal
        // in light mode, so the label has to stay light too.
        case .primary, .selected: .white
        // Destructive keeps a light label for the same reason: it sits on a filled surface too,
        // just an orange one.
        case .destructive: .white
        // **The accent as ink, not as fill.** An option that is on is worth marking and is not
        // where the wheel is; giving it the glyph in teal on the ordinary surface says so without
        // borrowing the cursor's look.
        case .active: .sonicPrimary
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
        case .active: AnyShapeStyle(Color.sonicPrimary.opacity(ControlTint.on))
        case .plain, .disabled: AnyShapeStyle(Color.sonicPrimary.opacity(ControlTint.off))
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
