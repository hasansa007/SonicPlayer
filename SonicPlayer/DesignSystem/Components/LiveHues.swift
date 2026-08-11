import SwiftUI

/// The five hues the dial borrows for a value it is reporting rather than a control you press.
///
/// **They were a border that cycled while audio moved, and that border is gone.** It lived on the
/// wheel, then on the card, and it was the one thing on the screen animating forever — which made a
/// rotation during playback animate the layout and never settle. What it said, the chrome already
/// says in words.
///
/// One consumer is left, and it is the better use of them: the wheel's volume arc. A quantity drawn
/// across a sweep is what an angular gradient is actually for.
enum LiveHues {

    /// Closes the loop — the first hue repeats last so the seam does not read as a join.
    static let all: [Color] = [
        .sonicPrimary, .sonicGreen, .sonicBlue, .sonicPurple, .sonicOrange, .sonicPrimary
    ]
}
