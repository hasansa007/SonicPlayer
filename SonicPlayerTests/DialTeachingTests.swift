import Foundation
import Testing

@testable import SonicPlayer

/// **What the dial says about itself, and when (#6).**
///
/// The wheel is the only way to operate this app, and for a while the only thing explaining it was
/// one line of prose under it — which grew to three clauses trying to cover a turn, a press, a hold
/// and four nudges, and was then removed for being the longest text on the screen. Removing it left
/// a control with no explanation at all: four glyphs saying a stick moves, and nothing saying what
/// a push does or that the wheel carries on past the last row.
///
/// The answer is not one sentence but three facts, each said where and when it is true:
///
///     at rest         the turn and the press — the part that is true whether or not you touch it
///     thumb on hub    the four nudges, by name, drawn on the marks themselves
///     on the last row that turning continues into the chips
///
/// This suite is the first two thirds of that — the third is a `@State` reveal inside `DialRing`
/// with no logic behind it. **What is testable here is the contract**: that the caption stops where
/// the nudges begin, that the nudges carry drawable names, and that the announcement appears on
/// exactly one row.
@Suite
struct DialTeachingTests {

    // MARK: - The caption stops where the nudges begin

    /// The caption used to end with `"· nudge to trim, move, delete or share"`, which is
    /// `ring.directions` written a second time in prose. Two statements of one fact drift; this
    /// pins that there is now one.
    @Test func theCaptionNamesTheTurnAndThePressAndNothingElse() {
        let library = DialSample.inRecordings().screen
        #expect(library.hint == "rotate to scroll · press to play")

        var playing = DialSample.navigator()
        _ = playing.receive(.hold)
        #expect(playing.screen.hint == "rotate to seek · press to pause")
    }

    @Test func noCaptionMentionsANudge() {
        let screens: [DialScreen] = [
            DialSample.inRecordings().screen,
            DialSample.whileRecording().screen,
            DialSample.whileEditing().screen,
            DialSample.inRecordings(recordingCount: 0).screen
        ]

        for screen in screens {
            #expect(!screen.hint.contains("nudge"), "\(screen.hint)")
            #expect(!screen.hint.contains(" up to "), "\(screen.hint)")
            #expect(!screen.hint.contains(" right to "), "\(screen.hint)")
        }
    }

    // MARK: - The nudges carry names that fit

    /// **A `Direction.label` is drawn now, not merely spoken.** They were sentences —
    /// `"Move to folder"`, `"Preview selection"` — for as long as nothing read them: the marks are
    /// `accessibilityHidden` and no view touched the field, so its only consumer was a test.
    ///
    /// The left and right names sit in the annulus between the hub and the ticks, which is 65
    /// points wide. Two words is the ceiling and one is the norm, so this pins the length rather
    /// than each string — a new verb should fail this without anyone having to remember why.
    @Test func everyNudgeNameIsShortEnoughToDraw() {
        let navigators: [DialNavigator] = [
            DialSample.inRecordings(),
            DialSample.whileRecording(),
            DialSample.whileEditing(),
            playingNavigator()
        ]

        for navigator in navigators {
            guard let directions = navigator.screen.ring.directions else { continue }
            for name in names(of: directions) {
                #expect(name.split(separator: " ").count <= 2, "\(name) is a sentence, not a name")
                #expect(!name.isEmpty)
            }
        }
    }

    /// The two axes are not equally tight, and only one of them is the constraint: up and down have
    /// the plate's whole width, left and right have the annulus. `Volume down` is the longest name
    /// in the app and it is a vertical one, which is why it survives.
    @Test func theHorizontalNudgesAreTheOnesKeptToOneWord() {
        var navigator = playingNavigator()
        _ = navigator.receive(.hold)
        let directions = navigator.screen.ring.directions

        #expect(directions?.left?.label == "Previous")
        #expect(directions?.right?.label == "Next")
        #expect(directions?.up?.label == "Volume up")
        #expect(directions?.down?.label == "Volume down")
    }

    // MARK: - The chips announce themselves, once

    /// **The wheel does not stop at the last row, and nothing on screen said so.** A list that has
    /// run out looks exactly like a wheel that has run out. The chips were made ring stops so no
    /// control could be drawn and unreachable; an affordance nobody finds is that same defect one
    /// step further along.
    @Test func theLastRowIsWhereTheChipsAnnounceThemselves() {
        var navigator = DialSample.inRecordings(recordingCount: 3)

        #expect(!navigator.screen.chipsAreNext, "row 0 of 3")
        _ = navigator.receive(.tick(1))
        #expect(!navigator.screen.chipsAreNext, "row 1 of 3")
        _ = navigator.receive(.tick(1))
        #expect(navigator.screen.chipsAreNext, "the last row, and Back is one detent away")
    }

    /// Once it has happened it is no longer next, so the line goes as the highlight arrives.
    @Test func itStopsTheMomentTheWheelIsActuallyOnAChip() {
        var navigator = DialSample.inRecordings(recordingCount: 3)
        _ = navigator.receive(.tick(2))
        #expect(navigator.screen.chipsAreNext)

        _ = navigator.receive(.tick(1))

        #expect(navigator.highlightedChipID == "back")
        #expect(!navigator.screen.chipsAreNext)
    }

    /// **An empty list has no last row**, so it says nothing — the highlight opens on the first
    /// chip there and the announcement would be about somewhere it already is.
    @Test func anEmptyListAnnouncesNothing() {
        #expect(!DialSample.inRecordings(recordingCount: 0).screen.chipsAreNext)
    }

    /// The three screens the wheel does not scroll bind it to seek, gain and trim, so their chips
    /// are touch-only — there is no turning that reaches them and nothing to announce.
    @Test func theScreensTheWheelDoesNotScrollAnnounceNothing() {
        #expect(!DialSample.whileRecording().screen.chipsAreNext)
        #expect(!DialSample.whileEditing().screen.chipsAreNext)

        var playing = playingNavigator()
        _ = playing.receive(.hold)
        #expect(!playing.screen.chipsAreNext)
    }

    // MARK: - Fixtures

    private func playingNavigator() -> DialNavigator {
        DialSample.navigator()
    }

    private func names(of directions: DialScreen.Directions) -> [String] {
        [directions.up, directions.down, directions.left, directions.right]
            .compactMap { $0?.label }
    }
}
