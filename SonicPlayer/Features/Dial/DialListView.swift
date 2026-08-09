import SwiftUI

/// A highlighted row in a vertical list — the dial's fundamental gesture, and therefore four of the
/// eight screens (#6).
///
/// **It does not scroll.** The navigator hands over the rows that fit and moves `highlighted`
/// within them; windowing a long list is a decision, and decisions are not made here. A scroll view
/// would also give the finger a second way to move the highlight, which is the thing this
/// navigation model is trying not to have.
///
/// **The navigator says whether the rows are cards.** This used to be `rows.count <= 2`, decided
/// here, on the reasoning that the count is the only available signal for "a choice between two
/// things" versus "a list to scroll". It was the wrong signal: the library home is two rows when
/// nothing is loaded and three when something is, so the entire screen changed shape the moment
/// playback started — see `DialScreen.List.isProminent`.
struct DialListView: View {

    let list: DialScreen.List
    /// The rows are inert; the dial moves the highlight and the hub opens it. A tap is the touch
    /// equal of pressing the hub on that row, which is what keeps the two input surfaces peers.
    let onSelect: (Int) -> Void

    private var isProminent: Bool { list.isProminent }

    /// Whether rows without an icon still hold the leading column open.
    ///
    /// `DialScreen.Icon` has a `.none` case and the item-actions screen uses it, so a list can be
    /// part-iconned. Letting those rows close the column ragged-edges the titles against their
    /// neighbours; reserving it for everyone in a list where *anything* has an icon keeps one left
    /// margin, and costs nothing in a list where nothing does.
    private var reservesIconColumn: Bool {
        list.rows.contains { DialIcon.systemImage(for: $0.icon) != nil }
    }

    /// What the rows below act on.
    ///
    /// Without it the actions screen is five verbs and no object — "Delete" with nothing saying
    /// *what*. It is deliberately not a row: it cannot be highlighted and pressing the hub never
    /// selects it, so it reads as a heading rather than as a sixth choice.
    private func subjectHeader(_ subject: DialScreen.List.Subject) -> some View {
        HStack(spacing: Spacing.md) {
            if let symbol = DialIcon.systemImage(for: subject.icon) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundColor(.sonicPrimary)
                    .frame(width: Sizing.compactControl, height: Sizing.compactControl)
                    .background(
                        Color.sonicPrimary.opacity(ControlTint.on),
                        in: RoundedRectangle(cornerRadius: Radius.sm)
                    )
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(subject.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.sonicTextPrimary)
                    .lineLimit(1)

                if let detail = subject.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.sonicTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    var body: some View {
        VStack(spacing: isProminent ? Spacing.md : Spacing.xxs) {
            if let subject = list.subject {
                subjectHeader(subject)
            }

            ForEach(Array(list.rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    onSelect(index)
                } label: {
                    DialRowView(
                        row: row,
                        isHighlighted: index == list.highlighted,
                        isProminent: isProminent,
                        reservesIconColumn: reservesIconColumn
                    )
                }
                .buttonStyle(.plain)
            }

            // The cards sat between two of these and were therefore *centred* in whatever height
            // the card gave them — which is where the empty band above and below them came from.
            // A menu of two or three things should hug; only a list needs a floor to push `1 of 12`
            // down to.
            if !isProminent { Spacer(minLength: 0) }

            if let position = list.position {
                Text(position)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.sonicTextMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One row. Split out because the highlighted and plain forms differ in five properties at once,
/// and a chain of ternaries inside the list was unreadable by the third.
private struct DialRowView: View {

    let row: DialScreen.List.Row
    let isHighlighted: Bool
    let isProminent: Bool
    let reservesIconColumn: Bool

    private var isDestructive: Bool { DialIcon.isDestructive(row.icon) }

    var body: some View {
        HStack(spacing: Spacing.md) {
            icon

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                // Two lines and tail truncation, **not** the middle truncation `SonicRow` uses.
                // That mode is right for a filename, where the extension is the informative end;
                // here it turned "Recordings" into "R…gs" at AX5. A second line costs nothing at
                // ordinary sizes, where these titles are one line anyway.
                Text(row.title)
                    .font(titleFont)
                    .fontWeight(isProminent ? .bold : (isHighlighted ? .semibold : .regular))
                    .foregroundColor(titleColor)
                    .lineLimit(2)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(isProminent ? .subheadline : .caption)
                        .foregroundColor(secondaryColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.sm)

            if let trailing = row.trailing {
                Text(trailing)
                    .font(isProminent ? .subheadline : .caption)
                    .monospacedDigit()
                    .foregroundColor(secondaryColor)
            }

            // Drawn for every card that goes somewhere, not just the highlighted one — it is a
            // property of the destination, and a chevron that appears as the highlight arrives
            // would read as part of the selection rather than as what the row is.
            if isProminent && row.opensSomewhere {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(isHighlighted ? secondaryColor : .sonicTextMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, isProminent ? Spacing.lg : Spacing.md)
        .padding(.vertical, isProminent ? Spacing.lg : Spacing.md)
        .background(background)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? [.isSelected] : [])
    }

    @ViewBuilder
    private var icon: some View {
        if let systemImage = DialIcon.systemImage(for: row.icon) {
            if isProminent {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundColor(isHighlighted ? .white : .sonicPrimary)
                    .frame(width: Sizing.dialChoiceTile, height: Sizing.dialChoiceTile)
                    .background(
                        Color.white.opacity(isHighlighted ? ControlTint.on : 0),
                        in: RoundedRectangle(cornerRadius: Radius.lg)
                    )
                    .background(
                        Color.sonicPrimary.opacity(isHighlighted ? 0 : ControlTint.on),
                        in: RoundedRectangle(cornerRadius: Radius.lg)
                    )
                    .accessibilityHidden(true)
            } else {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundColor(iconColor)
                    .frame(width: Spacing.xxl)
                    .accessibilityHidden(true)
            }
        } else if reservesIconColumn && !isProminent {
            Color.clear.frame(width: Spacing.xxl, height: 0)
        }
    }

    @ViewBuilder
    private var background: some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: isProminent ? Radius.sheet : Radius.md)
                .fill(DialSurface.fill)
                .sonicShadow(Elevation.control)
        } else if isProminent {
            // A prominent row that is not highlighted still needs an edge, or the chooser reads as
            // one card and an orphaned label.
            RoundedRectangle(cornerRadius: Radius.sheet)
                .fill(Color.sonicPrimary.opacity(ControlTint.off))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sheet)
                        .strokeBorder(Color.sonicBorder)
                )
        }
    }

    private var titleFont: Font { isProminent ? .title3 : .body }

    private var titleColor: Color {
        if isHighlighted { return .white }
        if isDestructive { return .red }
        return .sonicTextPrimary
    }

    private var iconColor: Color {
        if isHighlighted { return .white }
        if isDestructive { return .red }
        return .sonicTextSecondary
    }

    private var secondaryColor: Color {
        isHighlighted ? Color.white.opacity(Self.onFillSecondary) : .sonicTextSecondary
    }

    private static let onFillSecondary: Double = 0.75
}
