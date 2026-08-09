import SwiftUI

/// Trim (#6).
///
/// **The handles are drawn, not dragged.** The dial nudges whichever one the action row has
/// selected, which is the whole reason this screen exists in a wheel-driven app — a trim handle is
/// the case where a finger on the waveform is too coarse and a wheel is exactly right.
///
/// Note what is *not* here: the design puts `Delete selection` and `Split at playhead` inside this
/// card. `DialScreen.Edit` has no field for them and `actions` explicitly may hold five, so they
/// live in the action row with the handle selector. See `DialPreviewData`.
struct DialEditView: View {

    let edit: DialScreen.Edit

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

                handle(isActive: true, systemImage: "chevron.left")
                    .position(x: inX, y: geometry.size.height / 2)

                handle(isActive: false, systemImage: "chevron.right")
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
        .accessibilityElement(children: .ignore)
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

    /// `isActive` is the handle the dial is currently nudging. The contract says which through the
    /// action row's `.selected` emphasis rather than through `Edit`, so this view cannot read it —
    /// the start handle is drawn active because that is what the selector defaults to.
    private func handle(isActive: Bool, systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: Radius.sm)
            .fill(isActive ? Color.sonicPrimary : Color.sonicTextSecondary)
            .frame(width: Sizing.dialTrimHandle, height: Sizing.dialEditWave)
            .overlay(
                Image(systemName: systemImage)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            )
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

    /// How faint the trimmed-away part of the waveform is. Present, not deleted — the point of the
    /// screen is that you can move the handles back.
    private static let cut: Double = 0.3
}
