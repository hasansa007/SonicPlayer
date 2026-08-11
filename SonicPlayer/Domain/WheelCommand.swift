import Foundation

/// Everything the wheel can say (#6).
///
/// The view knows only these. It does not know what seeking is — which is what lets the same
/// component drive Now Playing, a menu and the trim editor without ever growing a mode flag.
enum WheelCommand: Equatable {
    /// Signed detents, already multiplied by the caller's acceleration.
    case tick(Int)
    case select
    case back
    case menu
    case transport(Transport)

    enum Transport: Equatable {
        case previous
        case next
        case playPause
    }
}

/// Where a command lands.
///
/// Slice 1 carries only the Now Playing cases. `.menu` and `.trim` arrive with slices 2 and 3, and
/// the reason this is an enum rather than a boolean is that they will.
enum WheelFocus: Equatable {
    case nowPlaying(Axis)

    enum Axis: Equatable {
        case seek
        case volume
        case speed
    }

    /// What the wheel does when nothing has claimed it.
    static let `default` = WheelFocus.nowPlaying(.seek)
}
