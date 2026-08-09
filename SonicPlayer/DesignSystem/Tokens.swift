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
    /// 18 — a card sheet rising over the canvas. Larger than `lg` because the surface is larger.
    static let sheet: CGFloat = 18
    /// 24 — the dial navigator's stage: the card holding a whole screen's content. Larger than
    /// `sheet` for the reason `sheet` is larger than `lg` — the surface is larger again.
    static let stage: CGFloat = 24
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
    /// 130 — a collection card. Fixed so a grid row stays level whether a folder's name wraps to
    /// one line or two.
    static let collectionCard: CGFloat = 130
    /// 64 — one `SonicRow`. Home reserves this per row because its list is inside a fixed-height
    /// frame with scrolling disabled, so it has to know the height in advance.
    static let rowHeight: CGFloat = 64

    // The rotary wheel. **None of these scale with Dynamic Type**, and that is the point: the wheel
    // is a physical control, and one that moves under the thumb between accessibility settings is
    // worse than one that stays put. Everything *above* it scales normally.

    /// 168 — the wheel's outer diameter.
    static let wheelDiameter: CGFloat = 168
    /// 70 — the hub, which is the contextual primary action.
    static let wheelHub: CGFloat = 70
    /// 200 — the band at the bottom of the canvas the wheel owns. Nothing is drawn over it, except
    /// while capturing audio, which is the one stated exception in the design.
    static let wheelZone: CGFloat = 200
    /// 3 — the lit arc that tracks the thumb. Thicker than the ring it sits on, so it reads as a
    /// highlight rather than as a thicker section of the same line.
    static let wheelArcWidth: CGFloat = 3

    // The dial navigator (#6). **Same rule as the wheel above — none of these scale with Dynamic
    // Type.** They are larger than the wheel's because the dial is not a control on one screen: it
    // is the navigation model, present on all eight, and the thumb rests on it for the whole
    // session rather than reaching for it occasionally.

    /// 236 — the dial's outer diameter. Around 60% of a compact screen's width, which is what puts
    /// the whole ring inside a thumb's arc without the hand moving.
    static let dialDiameter: CGFloat = 236
    /// 92 — the hub, which is always the commit. Its radius comfortably clears
    /// `RotaryTracker.deadZoneRadius`, so a press can never be read as the start of a turn.
    static let dialHub: CGFloat = 92
    /// 12 — one tick mark's length. Its width is `hairlineTrackHeight`, shared with the scrubber's.
    static let dialTick: CGFloat = 12
    /// 26 — the record dot at the hub's centre while capturing.
    static let dialRecordDot: CGFloat = 26
    /// 5 — the now-playing progress bar. Thinner than `trackHeight` because nothing drags it: the
    /// ring is the seek control here and the bar is a readout.
    static let dialTrack: CGFloat = 5
    /// 4 — one bar of the live recording waveform.
    static let dialWaveBar: CGFloat = 4
    /// 70 — the live recording waveform's height.
    static let dialWave: CGFloat = 70
    /// 110 — the trim editor's waveform. Taller than the live one because handles have to be
    /// grabbable inside it.
    static let dialEditWave: CGFloat = 110
    /// 20 — one trim handle's width.
    static let dialTrimHandle: CGFloat = 20
    /// 52 — the icon tile on a prominent choice row, where a screen offers two options rather than
    /// a list of many.
    static let dialChoiceTile: CGFloat = 52
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
    /// Not a depth — a legibility aid. A white glyph drawn straight onto a collection card can
    /// land on the pale end of that card's gradient and disappear; this keeps its edge.
    static let glyphContrast = Shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 0)
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

    /// A row or card acknowledging that it has been picked. Faster than `press` because it is
    /// confirming a state change rather than a touch.
    static let selection: Animation = .easeInOut(duration: 0.15)
    /// Entering or leaving selection mode, which moves the whole toolbar and every row's inset.
    static let selectionMode: Animation = .easeInOut(duration: 0.2)

    /// The wheel's lit arc catching up to the thumb. Shorter than `scrub` because the arc chases a
    /// finger that is still moving — anything slower reads as lag rather than as smoothing.
    static let detent: Animation = .linear(duration: 0.06)
    /// The transient value pill arriving and leaving.
    static let hudFade: Animation = .easeOut(duration: 0.25)

    /// The capture indicator's breathing dot. 1.4s round trip — slow enough to read as breathing
    /// rather than as an alarm, which matters because it is on screen for the whole recording.
    static let recordPulse: Animation = .easeInOut(duration: 0.7).repeatForever(autoreverses: true)

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

/// Point sizes the dial navigator draws numerals at, plus the one tracking value its chrome needs.
///
/// These exist for the same reason `DisplayFont` does — **a `.system(size:)` is the same number of
/// points at every accessibility setting** — and carry the same obligation: read each one through
/// `@ScaledMetric`, never inline.
///
/// ```swift
/// @ScaledMetric(relativeTo: .largeTitle) private var elapsed = DialFont.elapsed
/// ```
///
/// They are here rather than beside `DisplayFont` in `Typography.swift` only because the dial's UI
/// half was built on a branch that owns `Tokens.swift` and not that file. They are the same idea
/// and should be folded in when the two land together.
///
/// No semantic style reaches these sizes: `.largeTitle` is 34pt and the running timer is half again
/// that. That is the whole justification for a fixed size — a role a scale does not cover.
enum DialFont {

    /// 46 — now playing's elapsed time, the largest thing on that screen.
    static let elapsed: CGFloat = 46
    /// 54 — the recording timer. Larger than `elapsed` because on that screen it is the only
    /// readout, and it is read from arm's length.
    static let timer: CGFloat = 54
    /// 26 — the tenths beside the timer, roughly half it, so the two read as one number.
    static let fraction: CGFloat = 26
    /// 1.5 — letter spacing on a breadcrumb. Set in caps at caption size, it needs the air.
    static let breadcrumbTracking: CGFloat = 1.5
}
