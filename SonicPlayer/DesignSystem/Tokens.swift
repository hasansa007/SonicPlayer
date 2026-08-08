import SwiftUI

// Design tokens — epic #6, slice 1 (#47).
//
// Static `let` constants on caseless `enum` namespaces, matching how `ColorPalette` exposes
// colour. No `@Environment`, no `@Entry`: nothing overrides a token at runtime, so paying a
// environment read at every call site would buy theme-swapping the app has never wanted.
//
// **Every value here was already in the player.** The set is a grep of `PlayerView` and
// `MiniPlayerView`, not a scale designed in the abstract — which is why adopting it changes no
// pixels. `ColorPalette.swift` and `Theme.swift` deliberately stay in `Utilities/`; see
// `docs/adr/0002-design-system-foundation.md`.

/// The 4-point spacing scale.
enum Spacing {
    /// 2 — a title and its subtitle.
    static let xxs: CGFloat = 2
    /// 4
    static let xs: CGFloat = 4
    /// 8 — the default gap inside a component.
    static let sm: CGFloat = 8
    /// 12 — the default gap between components in a row.
    static let md: CGFloat = 12
    /// 16 — a screen's horizontal inset on compact width.
    static let lg: CGFloat = 16
    /// 20 — between sections.
    static let xl: CGFloat = 20
    /// 24 — the player's horizontal inset.
    static let xxl: CGFloat = 24
    /// 40 — a screen's bottom inset, and the widest gap in a transport row.
    static let xxxl: CGFloat = 40
}

/// Corner radii, paired with size: the larger the surface, the larger the radius.
enum Radius {
    /// 3 — the grabber and the waveform bars.
    static let hairline: CGFloat = 3
    /// 4 — the scrub track.
    static let xs: CGFloat = 4
    /// 8 — chips, toggles, thumbnails.
    static let sm: CGFloat = 8
    /// 12 — collapsed artwork.
    static let md: CGFloat = 12
    /// 16 — full-size artwork.
    static let lg: CGFloat = 16
}

/// Control and artwork dimensions.
///
/// `tapTarget` is 44 because that is Apple's documented minimum — several buttons in the old
/// player were smaller than it, which `IconControlButton` now makes impossible.
enum Sizing {
    /// 44 × 44 — the smallest a control may be.
    static let tapTarget: CGFloat = 44
    /// 28 — the mini-player's close button.
    static let compactControl: CGFloat = 28
    /// 56 — previous / next.
    static let secondaryControl: CGFloat = 56
    /// 64 — play / pause, the one primary action on the screen.
    static let playButton: CGFloat = 64
    /// 40 — the mini-player thumbnail.
    static let thumbnail: CGFloat = 40
    /// 80 — artwork with the queue open.
    static let artworkCollapsed: CGFloat = 80
    /// 120 — artwork in landscape.
    static let artworkCompact: CGFloat = 120
    /// 280 — artwork at rest.
    static let artworkFull: CGFloat = 280
    /// 8 — the scrub track.
    static let trackHeight: CGFloat = 8
    /// 2 — the mini-player's progress hairline.
    static let hairlineTrackHeight: CGFloat = 2
    /// 36 × 5 — the sheet grabber.
    static let grabber = CGSize(width: 36, height: 5)

    // Two component insets that are off the 4-point scale and stay that way. Snapping them would
    // have been tidier arithmetic and an unrequested visual change on the epic's first PR.
    // Neither is a gap *between* things — both are insets *within* one component, which is why
    // they live here and not in `Spacing`.

    /// 10 — the mini-player row's vertical inset. Sets the bar's height together with
    /// `thumbnail`; this bar sits above every screen, so its height is a fixture.
    static let barRowInsetV: CGFloat = 10
    /// 14 — a text chip's horizontal inset. Vertical stays on the scale at `Spacing.sm`.
    static let chipInsetH: CGFloat = 14
    /// 260 — the landscape artwork column. Fixed rather than proportional so the controls beside
    /// it do not reflow as the title wraps.
    static let landscapeColumn: CGFloat = 260
    /// 200 — the height an empty queue holds open, so the panel does not collapse to nothing.
    static let queuePlaceholder: CGFloat = 200
    /// 2 — the play triangle's optical correction. Its visual centre sits left of its bounding
    /// box's; the pause bars' does not, so only one glyph is nudged.
    static let playGlyphOpticalOffset: CGFloat = 2
    /// 28 — one line of the track title. Reserved explicitly because `ScrollingText` lives in a
    /// `GeometryReader`, which has no intrinsic height to offer.
    static let titleLine: CGFloat = 28
}

/// A shadow, as one value rather than four loose arguments at the call site.
struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

/// The three depths anything in this app casts.
enum Elevation {
    /// Artwork — the only thing on the player that floats.
    static let artwork = Shadow(color: Color.sonicPrimary.opacity(0.2), radius: 16, x: 0, y: 8)
    /// The primary transport button.
    static let control = Shadow(color: Color.sonicPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
    /// A bar pinned above content, casting *upward*.
    static let bar = Shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
}

extension View {
    /// The one way to cast a shadow. A raw `.shadow(color:radius:x:y:)` in a screen is what this
    /// replaces — `scripts/lint-magic-numbers.sh` flags any that come back.
    func sonicShadow(_ shadow: Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

/// Motion, named for what it describes rather than for its curve, so the same gesture cannot
/// acquire two different durations in two files.
enum Motion {
    /// Following a finger. Short enough that the bar does not lag the touch.
    static let scrub: Animation = .linear(duration: 0.1)
    /// The mini-player's progress hairline, which nothing is dragging.
    static let miniProgress: Animation = .linear(duration: 0.3)
    /// Revealing or hiding a panel within a screen.
    static let panel: Animation = .spring(response: 0.4, dampingFraction: 0.8)
    /// A control acknowledging a press.
    static let press: Animation = .easeInOut(duration: 0.1)
    /// Something settling after it stops.
    static let settle: Animation = .easeOut(duration: 0.3)

    /// The playing-waveform bars. `index` staggers them so they do not pulse in unison.
    ///
    /// A fixed table rather than `Double.random(in: 0.3...0.6)`, which the old
    /// `PlayerWaveformView` evaluated *inside* `body` — so any unrelated player state change
    /// re-rolled the duration and restarted the animation mid-pulse.
    static func waveformBar(index: Int) -> Animation {
        let durations: [Double] = [0.42, 0.55, 0.34, 0.48, 0.38]
        return .easeInOut(duration: durations[index % durations.count])
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.1)
    }
}
