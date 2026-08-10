import SwiftUI

/// Trim (#6).
///
/// **The handles are dragged as well as nudged, and tapping one chooses it.** This used to say "the
/// handles are drawn, not dragged" — the wheel was the only way to move them, and which one it
/// moved was chosen by a chip in the action row. Two problems came out of that. The chips were a
/// control for something you were already looking at, and the view could not read the selection at
/// all, so it drew the *start* handle active whichever one you had chosen.
///
/// Now the finger does the coarse move and the wheel does the fine one, which is the pairing this
/// screen wanted all along: drag a handle roughly into place, then turn for the last tenth of a
/// second. Dragging selects, so the wheel picks up whichever one you just released.
struct DialEditView: View {

    let edit: DialScreen.Edit
    var onCommand: (DialCommand) -> Void = { _ in }

    /// Which handle the finger currently owns. `nil` between gestures — the wheel's selection is
    /// `edit.activeHandle`, which the navigator owns and this only mirrors while dragging.
    @State private var dragging: DialScreen.Handle?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Spacer(minLength: 0)

            header
            waveform
            scale

            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(edit.title)
                .font(.headline)
                .foregroundColor(.sonicTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Spacing.sm)

            HStack(spacing: Spacing.xs) {
                Text("Keeping")
                    .foregroundColor(.sonicTextMuted)
                Text(edit.keeping)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(.sonicPrimary)
            }
            .font(.caption)
        }
        .accessibilityElement(children: .combine)
    }

    private var waveform: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let inX = edit.inFraction.clampedFraction * width
            let outX = edit.outFraction.clampedFraction * width

            ZStack(alignment: .leading) {
                bars

                // The kept region: a lid and a floor rather than a fill, so the bars inside stay
                // readable. A tint alone washed them out at every opacity worth having.
                Rectangle()
                    .fill(Color.sonicPrimary.opacity(ControlTint.off))
                    .overlay(alignment: .top) { edge }
                    .overlay(alignment: .bottom) { edge }
                    .frame(width: max(0, outX - inX))
                    .offset(x: inX)

                handle(.start, systemImage: "chevron.left", width: width)
                    .position(x: inX, y: geometry.size.height / 2)

                handle(.end, systemImage: "chevron.right", width: width)
                    .position(x: outX, y: geometry.size.height / 2)

                if let playhead = edit.playheadFraction {
                    Rectangle()
                        .fill(Color.sonicTextPrimary)
                        .frame(width: Sizing.hairlineTrackHeight / 2)
                        .offset(x: playhead.clampedFraction * width)
                }
            }
        }
        .frame(height: Sizing.dialEditWave)
        .coordinateSpace(name: Self.waveSpace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Trim region"))
        .accessibilityValue(Text(edit.keeping))
    }

    private var edge: some View {
        Rectangle()
            .fill(Color.sonicPrimary)
            .frame(height: Sizing.hairlineTrackHeight)
    }

    private var bars: some View {
        HStack(alignment: .center, spacing: 1) {
            ForEach(Array(edit.waveform.enumerated()), id: \.offset) { index, level in
                let position = Double(index) / Double(max(1, edit.waveform.count - 1))
                let isKept = position >= edit.inFraction && position <= edit.outFraction

                Capsule()
                    .fill(isKept ? Color.sonicPrimary : Color.sonicTextSecondary.opacity(Self.cut))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: max(Radius.hairline, level.clampedFraction * Sizing.dialEditWave)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One handle: filled when it is the one the wheel will nudge, and both tappable and draggable.
    ///
    /// **The touch target is wider than the bar.** `Sizing.dialTrimHandle` is a few points across so
    /// the waveform stays readable through it, and a few points is not something a thumb can find.
    /// The `contentShape` widens what responds without widening what is drawn.
    private func handle(
        _ which: DialScreen.Handle, systemImage: String, width: CGFloat
    ) -> some View {
        let isActive = (dragging ?? edit.activeHandle) == which

        return RoundedRectangle(cornerRadius: Radius.sm)
            .fill(isActive ? Color.sonicPrimary : Color.sonicTextSecondary)
            .frame(width: Sizing.dialTrimHandle, height: Sizing.dialEditWave)
            .overlay(
                Image(systemName: systemImage)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            )
            .contentShape(Rectangle().size(width: Sizing.tapTarget, height: Sizing.dialEditWave))
            .gesture(
                // **Named space, not the default.** The handle is `.position`-ed, so a gesture in
                // its own coordinates reports where the finger is *within the handle* — a few
                // points wide, and identical wherever on the waveform it sits. Every drag would
                // read as "near zero" and the handle would jump to the start.
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.waveSpace))
                    .onChanged { value in
                        dragging = which
                        onCommand(.dragTrim(handle: which, fraction: value.location.x / max(1, width)))
                    }
                    .onEnded { _ in dragging = nil }
            )
            .accessibilityElement()
            .accessibilityLabel(Text(which == .start ? "Start handle" : "End handle"))
            .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var scale: some View {
        HStack(spacing: 0) {
            ForEach(Array(edit.scale.enumerated()), id: \.offset) { index, label in
                if index > 0 { Spacer(minLength: Spacing.xs) }
                Text(label)
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundColor(.sonicTextMuted)
        .accessibilityElement(children: .combine)
    }

    /// The waveform's own coordinate space, so a drag on a positioned handle reports where the
    /// finger is along the *waveform* rather than within the handle.
    private static let waveSpace = "dialTrimWave"

    /// How faint the trimmed-away part of the waveform is. Present, not deleted — the point of the
    /// screen is that you can move the handles back.
    private static let cut: Double = 0.3
}
