import SwiftUI

// Type — epic #6, slice 1 (#47).
//
// **There is deliberately no parallel type scale here.** `Font.sonicBody = .subheadline` is a
// name with no value behind it: it adds a layer to read through, and it tempts the next author
// into `.system(size: 15)` when a role is missing — which is how a codebase loses Dynamic Type.
// SwiftUI's semantic styles already scale, already respect the accessibility sizes, and already
// have names. They stay, used directly. See `docs/adr/0002-design-system-foundation.md`.
//
// What is here is **a role that is a style plus a weight or a numeric treatment**, repeated across
// files. The rule was: two or more consumers, or it is written inline until a second appears.
//
// **Both survivors are down to one consumer, so both are on notice (#76).** The rule was written
// when `PlayerView` and `MiniPlayerView` supplied the second and third consumer of everything here;
// deleting them took `sonicControlGlyph` to zero — it is gone — and left these two at one apiece.
// They are kept rather than inlined because inlining edits live rendering code, which does not
// belong in a deletion. If the dial does not grow a second consumer, inline them and delete this
// file: a role with one caller is the `AudioPlaying` mistake wearing a different hat.

extension Font {

    /// The transport glyph on the dial's ring. **One consumer**, `DialRing`.
    ///
    /// Was three consumers in `PlayerView` — previous, play and next — which is what justified it.
    static let sonicTransportGlyph: Font = .title2

    /// Elapsed and remaining. Always paired with `.monospacedDigit()` so the labels do not
    /// jitter as the digits change — the pairing is the reason this is a role at all.
    ///
    /// **One consumer**, `DialNowPlayingView`. The pairing argument is the one thing here that
    /// still holds independently of the count: a bare `.caption` invites dropping the modifier.
    static let sonicTimeLabel: Font = .caption
}

// `sonicControlGlyph` stood here — skip ±, repeat, shuffle, queue and the mini-player's play/pause,
// six consumers across the two player files. All six were deleted with those files (#76), and a
// font role with no caller is exactly what the note above refuses.
//
// `DisplayFont` stood below it, holding `stateIcon` (80) and `collectionCardGlyph` (50), to be read
// through `@ScaledMetric`. Its only two consumers were `PlayerView` and `ShellView`, both deleted.
//
// The accessibility problem it described is real and is NOT solved by deleting it: fixed point
// sizes still sit inline in `RecordingView`'s successors, `OnboardingView`, `AboutView` and
// `AppView`, and every one is the same unscaled-glyph bug. Retokenise when a screen that owns them
// is worked — #50 covers About and Help.
