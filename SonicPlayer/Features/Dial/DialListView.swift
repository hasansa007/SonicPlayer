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

    /// **The list follows the highlight, and the finger cannot move it.**
    ///
    /// The comment above says the navigator hands over the rows that fit — and nothing ever did.
    /// With six recordings the stack simply overflowed the card, so turning the wheel walked the
    /// highlight off the bottom edge and the screen stopped agreeing with the ring.
    ///
    /// A `ScrollView` with scrolling **disabled** is what squares that with "it does not scroll":
    /// the point of the rule was never that content cannot move, it was that a drag must not become
    /// a second way to change the selection. Here the wheel remains the only thing that moves the
    /// highlight, and the view merely keeps it in sight.
    var body: some View {
        if isProminent { cards } else { rows }
    }

    /// **Two tiles side by side, filling the card.**
    ///
    /// They were full-width rows stacked vertically, which left most of the card empty below them —
    /// two rows of content in a space built for a list. Side by side they use the width they were
    /// wasting and the height they were leaving behind, and the menu reads as a choice between two
    /// things rather than the top of a list that stops after two.
    private var cards: some View {
        HStack(spacing: Spacing.md) {
            ForEach(Array(list.rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    onSelect(index)
                } label: {
                    DialCardView(row: row, isHighlighted: index == list.highlighted)
                }
                .buttonStyle(.plain)
            }
        }
        // **Fills the height, tiles centred in it.** The tiles are square, so left to hug they made
        // this card far shorter than every other screen's — and the dial, a fixed 236 points under a
        // flexible spacer, moved with it. Taking the full height keeps the wheel in the same place
        // on every screen, which is the one thing on this layout the thumb learns by position rather
        // than by looking.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var rows: some View {
        VStack(spacing: Spacing.xxs) {
            // **Pinned rows sit outside the scroller entirely.** Import is row 0 of a list that can
            // be hundreds long, so on any real library it left the screen on the second turn — an
            // "always available" row that was available right up until you went looking for it.
            //
            // Same absolute indices either side of the split, which is what `pinnedRows` being a
            // count rather than a separate row buys: the highlight can rest here and nothing has to
            // renumber.
            ForEach(Array(list.rows.prefix(list.pinnedRows).enumerated()), id: \.element.id) { index, row in
                rowButton(row, at: index)
            }

            scrollingRows
        }
    }

    private var scrollingRows: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: Spacing.xxs) {
                    if let subject = list.subject {
                        subjectHeader(subject)
                    }

                    ForEach(Array(list.rows.enumerated().dropFirst(list.pinnedRows)), id: \.element.id) { index, row in
                        rowButton(row, at: index)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollDisabled(true)
            // Bounded, so there is something to scroll within. Sized to its content, a `ScrollView`
            // is just a `VStack` that overflows — which is how the highlight walked off the bottom.
            .frame(maxHeight: .infinity)
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: list.highlighted) { _, index in
                // A pinned row has no id in this scroller, so scrolling to it would do nothing at
                // best. It is already on screen — that is the point of pinning it.
                guard index >= list.pinnedRows else { return }
                withAnimation(Motion.settle) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func rowButton(_ row: DialScreen.List.Row, at index: Int) -> some View {
        Button {
            onSelect(index)
        } label: {
            DialRowView(
                row: row,
                isHighlighted: index == list.highlighted,
                isProminent: false,
                reservesIconColumn: reservesIconColumn
            )
        }
        .buttonStyle(.plain)
    }
}

/// One tile on a top-level menu: icon above, title and second line below, filling its half of the
/// card. Separate from `DialRowView` rather than another flag on it — a tile stacks vertically and
/// a row runs horizontally, so almost nothing but the colours was shared.
private struct DialCardView: View {

    let row: DialScreen.List.Row
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let systemImage = DialIcon.systemImage(for: row.icon) {
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
            }

            Spacer(minLength: 0)

            Text(row.title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(isHighlighted ? .white : .sonicTextPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = row.subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(isHighlighted ? Color.white.opacity(0.75) : .sonicTextSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let trailing = row.trailing {
                Text(trailing)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(isHighlighted ? Color.white.opacity(0.75) : .sonicTextMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // **Square.** Two tiles side by side each take half the width, so a 1:1 ratio makes the pair
        // as tall as one is wide and the card sizes itself off them rather than the other way round.
        .aspectRatio(1, contentMode: .fit)
        .padding(Spacing.lg)
        .background(background)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? [.isSelected] : [])
    }

    @ViewBuilder
    private var background: some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: Radius.sheet)
                .fill(DialSurface.fill)
                .sonicShadow(Elevation.control)
        } else {
            RoundedRectangle(cornerRadius: Radius.sheet)
                .fill(Color.sonicPrimary.opacity(ControlTint.off))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sheet)
                        .strokeBorder(Color.sonicBorder)
                )
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

    /// **The filled gradient is a card's, and a tint is a list's.**
    ///
    /// Both are the same thing — the wheel's cursor, the row the hub is about to act on — but they
    /// were drawn identically and that made them read differently. On a menu of two or three
    /// destinations the fill *is* the offer. On a menu of verbs it made the first row look like the
    /// recommended one: `Rename` arrived at the top of the actions list and immediately read as a
    /// primary button, when all it had done was be row 0.
    ///
    /// Flattening it entirely was the other option and is worse — a list you turn through with no
    /// cursor has nothing saying where the press will land.
    @ViewBuilder
    private var background: some View {
        if isHighlighted && isProminent {
            RoundedRectangle(cornerRadius: Radius.sheet)
                .fill(DialSurface.fill)
                .sonicShadow(Elevation.control)
        } else if isHighlighted {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.sonicPrimary.opacity(ControlTint.on))
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

    // **Destructive now outranks highlighted**, which is the other half of the same change: on the
    // old filled row `Delete` went white like everything else, so the one row you most want to look
    // dangerous lost its colour exactly when the thumb was on it. Over a tint it stays red.

    private var titleColor: Color {
        if isDestructive { return .red }
        if isHighlighted && isProminent { return .white }
        return .sonicTextPrimary
    }

    private var iconColor: Color {
        if isDestructive { return .red }
        if isHighlighted && isProminent { return .white }
        return isHighlighted ? .sonicTextPrimary : .sonicTextSecondary
    }

    private var secondaryColor: Color {
        isHighlighted && isProminent
            ? Color.white.opacity(Self.onFillSecondary)
            : .sonicTextSecondary
    }

    private static let onFillSecondary: Double = 0.75
}
