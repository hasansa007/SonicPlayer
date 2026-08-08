import SwiftUI

// Type — epic #6, slice 1 (#47).
//
// **There is deliberately no parallel type scale here.** `Font.sonicBody = .subheadline` is a
// name with no value behind it: it adds a layer to read through, and it tempts the next author
// into `.system(size: 15)` when a role is missing — which is how a codebase loses Dynamic Type.
// SwiftUI's semantic styles already scale, already respect the accessibility sizes, and already
// have names. They stay, used directly. See `docs/adr/0002-design-system-foundation.md`.
//
// What is here is the two things a bare semantic style cannot express:
//
// 1. **Roles that are a style *plus* a weight or a numeric treatment**, repeated across files.
//    Each one below has two or more consumers in `PlayerView` + `MiniPlayerView` today. A role
//    with one consumer is not here — it is written inline until a second appears.
// 2. **Fixed display sizes**, which do not scale at all and are the real accessibility gap.

extension Font {

    /// Previous / play / next. Three consumers in `PlayerView`.
    static let sonicTransportGlyph: Font = .title2

    /// Skip ±, repeat, shuffle, queue, and the mini-player's play/pause. Six consumers across
    /// the two player files.
    static let sonicControlGlyph: Font = .title3

    /// Elapsed and remaining. Always paired with `.monospacedDigit()` so the labels do not
    /// jitter as the digits change — the pairing is the reason this is a role at all.
    static let sonicTimeLabel: Font = .caption
}

/// Point sizes that are genuinely fixed, and therefore genuinely broken under Dynamic Type.
///
/// A `.system(size: 80)` icon is the same 80 points at every accessibility setting, so a user at
/// AX5 gets scaled body text beside an unscaled glyph. These constants exist to be read through
/// `@ScaledMetric`, which is what actually fixes it:
///
/// ```swift
/// @ScaledMetric(relativeTo: .largeTitle) private var stateIcon = DisplayFont.stateIcon
/// ```
///
/// **Only sizes slice 1 consumes are listed.** The app has twelve more fixed sizes — five in
/// `RecordingView`, three in `OnboardingView`, and one each in `AboutView`, `CollectionsView`,
/// `CollectionsSection` and `AppView` — and every one of them is the same accessibility bug.
/// They are not tokenised here because slices #49–#51 own those screens, and a token with no
/// consumer is the mistake `AudioPlaying` already made.
enum DisplayFont {

    /// 80 — the icon on an empty or error state. `EmptyStateView` defaults to 72; the player
    /// has always passed 80 explicitly, and that is the value kept.
    static let stateIcon: CGFloat = 80
}
