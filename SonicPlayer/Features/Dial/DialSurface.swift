import SwiftUI

/// The one filled teal surface in the dial navigator.
///
/// Two consumers, which is what earns it a name: the highlighted row in a list, and a primary or
/// selected chip in the action row. They are deliberately the same fill — a screen has exactly one
/// thing the dial is pointing at and one thing the finger is expected to press, and drawing them
/// alike is what makes "the highlight and the action agree" legible at a glance.
///
/// It is not `LinearGradient.sonicGradient`, which runs top-leading to bottom-trailing and starts
/// dark. These surfaces are wide and short, so the sweep runs along them and starts light, matching
/// the design. It lives here rather than in `Utilities/Theme.swift` because it has no consumer
/// outside the dial yet; move it there when one appears.
enum DialSurface {

    static let fill = LinearGradient(
        colors: [Color.sonicPrimaryLight, Color.sonicPrimaryDark],
        startPoint: .leading,
        endPoint: .trailing
    )
}
