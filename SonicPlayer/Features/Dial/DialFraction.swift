import Foundation

extension Double {

    /// A `0...1` fraction safe to multiply a width or a height by.
    ///
    /// The navigator clamps the values it publishes — `DialScreen` says so of `List.highlighted`
    /// and means it of the rest. This is the view declining to be the place where a value that
    /// slipped through becomes a negative frame, which SwiftUI turns into a runtime complaint and
    /// an unreadable screen rather than a crash you can find.
    ///
    /// Four consumers: the ring's position and level ticks, the now-playing bar, the trim handles
    /// and the recording meter's bar heights.
    var clampedFraction: Double { min(max(self, 0), 1) }
}
