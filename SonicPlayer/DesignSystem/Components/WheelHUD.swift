import SwiftUI

/// The pill that states what the wheel is changing, then fades (#6).
///
/// Discrete choices belong in a sheet; continuous ones belong here.
///
/// `accessibilityHidden` because the value it shows is already `RotaryWheel`'s
/// `accessibilityValue` — announcing it twice is how a VoiceOver user ends up hearing every single
/// detent read out.
struct WheelHUD: View {

    let label: String
    let value: String

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .foregroundColor(.sonicTextSecondary)

            if !value.isEmpty {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(.sonicPrimary)
            }
        }
        .padding(.horizontal, Sizing.chipInsetH)
        .padding(.vertical, Spacing.sm)
        .background(
            Color.sonicBackground.opacity(0.94),
            in: RoundedRectangle(cornerRadius: Radius.md)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.sonicPrimary.opacity(0.3), lineWidth: Sizing.hairlineTrackHeight / 2)
        )
        .sonicShadow(Elevation.control)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
}
