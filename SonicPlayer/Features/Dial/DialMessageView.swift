import SwiftUI

/// The empty state (#6).
///
/// Written here rather than reaching for `EmptyStateView`, and the difference is the point: the
/// dashed ring is a picture of the dial, and the body copy's job is to say what pressing it will
/// do. An empty state in this navigation model is not "there is nothing here" — it is the one
/// place the wheel has to teach itself.
struct DialMessageView: View {

    let message: DialScreen.Message

    @ScaledMetric(relativeTo: .largeTitle) private var badge = Sizing.artworkCollapsed

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 0)

            if let systemImage = DialIcon.systemImage(for: message.icon) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundColor(.sonicPrimary)
                    .frame(width: badge, height: badge)
                    .background(
                        Circle().strokeBorder(
                            Color.sonicPrimary.opacity(Self.ring),
                            style: StrokeStyle(
                                lineWidth: Sizing.hairlineTrackHeight,
                                dash: [Spacing.sm]
                            )
                        )
                    )
                    .accessibilityHidden(true)
            }

            VStack(spacing: Spacing.xs) {
                Text(message.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.sonicTextPrimary)

                Text(message.body)
                    .font(.subheadline)
                    .foregroundColor(.sonicTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
    }

    private static let ring: Double = 0.35
}
