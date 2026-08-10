import SwiftUI

/// The colours that mean *audio is moving*, and the border that cycles them.
///
/// **This was the wheel's, and it has moved to the card.** An animated rainbow on the one thing you
/// are holding competes with the thing it is drawn on — and the wheel's border has a better job
/// now: it is the volume. The card is where you look to find out what is playing, so it is where
/// "this is playing" belongs.
///
/// Extracted rather than copied because two things use these hues now. The volume arc borrows them
/// so the level and the liveness read as one system rather than two palettes that drifted apart.
enum LiveHues {

    /// Closes the loop — the first hue repeats last so the seam does not read as a join.
    static let all: [Color] = [
        .sonicPrimary, .sonicGreen, .sonicBlue, .sonicPurple, .sonicOrange, .sonicPrimary
    ]

    /// Slow enough to sit beside a whole listening session. Anything faster becomes something to
    /// look away from, which is the opposite of what an ambient status should be.
    static let spinPeriod: Double = 8
}

/// A rounded-rectangle border that cycles `LiveHues` while `isLive`, and is a plain hairline
/// otherwise.
///
/// The animation is a repeating rotation rather than a timer, so it costs nothing when it is not
/// running — and stopping is just the angle no longer being animated, not a frame loop to tear down.
struct LiveBorder: View {

    let isLive: Bool
    let cornerRadius: CGFloat

    @State private var spin: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(
                isLive
                    ? AnyShapeStyle(AngularGradient(
                        colors: LiveHues.all,
                        center: .center,
                        angle: .degrees(spin)
                      ))
                    : AnyShapeStyle(Color.sonicBorder),
                lineWidth: isLive ? Sizing.liveBorderWidth : Sizing.hairlineTrackHeight / 2
            )
            .onChange(of: isLive) { _, live in
                guard live else { return }
                startSpinning()
            }
            .onAppear {
                guard isLive else { return }
                startSpinning()
            }
    }

    private func startSpinning() {
        withAnimation(.linear(duration: LiveHues.spinPeriod).repeatForever(autoreverses: false)) {
            spin = 360
        }
    }
}
