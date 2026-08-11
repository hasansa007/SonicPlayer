import Foundation
import Testing

@testable import SonicPlayer

/// #70 — the migration that removes the old in-app picker's language override.
///
/// Every case here is a version of this decision that shipped or nearly shipped wrong. The one that
/// matters most is `test_aSystemChoiceMadeAfterThePickerSurvives`: both earlier attempts deleted
/// that value, which is the user's live setting, made through the very control the app now sends
/// them to.
@Suite
struct LegacyLanguageOverrideTests {

    private let legacy = LegacyLanguageOverride.legacyKey   // "appLanguage"
    private let system = LegacyLanguageOverride.systemKey   // "AppleLanguages"

    // MARK: - Nothing of ours to clean up

    /// The common case: the picker was never used, so `AppleLanguages` — if present at all — was
    /// written by iOS. #68 deleted it here regardless.
    @Test func test_aSystemOnlyChoiceIsNeverTouched() {
        #expect(LegacyLanguageOverride.keysToRemove(from: [system: ["de"]]).isEmpty)
    }

    @Test func test_anEmptyDomainRemovesNothing() {
        #expect(LegacyLanguageOverride.keysToRemove(from: [:]).isEmpty)
    }

    // MARK: - Ours, and safe to remove

    @Test func test_thePickersOwnOverrideIsRemovedWhole() {
        let keys = LegacyLanguageOverride.keysToRemove(from: [legacy: "ar", system: ["ar"]])

        #expect(keys == [legacy, system])
    }

    /// The picker's "System" row wrote the marker and *removed* `AppleLanguages`, so only the
    /// marker is left to clear.
    @Test func test_thePickersSystemRowLeavesOnlyItsMarker() {
        #expect(LegacyLanguageOverride.keysToRemove(from: [legacy: "system"]) == [legacy])
    }

    // MARK: - The case both earlier versions got wrong

    /// Used the picker at some point, then set a language in **iOS Settings**. `appLanguage` is a
    /// stale marker; `AppleLanguages` is a live choice. Deleting on the marker's *presence* — which
    /// is what #70's first attempt did — silently discards it on the first launch after upgrading,
    /// and the one-shot flag means it never comes back.
    @Test func test_aSystemChoiceMadeAfterThePickerSurvives() {
        let keys = LegacyLanguageOverride.keysToRemove(from: [legacy: "ar", system: ["de"]])

        #expect(keys == [legacy], "A value the system overwrote is the user's, not ours (#70).")
        #expect(!keys.contains(system))
    }

    /// Same shape, reached the other way: the picker chose "System" and iOS later set a language.
    @Test func test_aSystemChoiceAfterThePickerChoseSystemSurvives() {
        let keys = LegacyLanguageOverride.keysToRemove(from: [legacy: "system", system: ["ar"]])

        #expect(keys == [legacy])
    }

    // MARK: - Shapes the dictionary can actually take

    /// `AppleLanguages` is a preference *list*. The picker wrote a single element, so a longer list
    /// whose head still matches is ours — anything else is not.
    @Test func test_onlyTheHeadOfThePreferenceListIsCompared() {
        #expect(LegacyLanguageOverride.keysToRemove(from: [legacy: "ar", system: ["ar", "en"]]) == [legacy, system])
        #expect(LegacyLanguageOverride.keysToRemove(from: [legacy: "ar", system: ["en", "ar"]]) == [legacy])
    }

    @Test func test_anEmptyPreferenceListIsNotAMatch() {
        #expect(LegacyLanguageOverride.keysToRemove(from: [legacy: "ar", system: [String]()]) == [legacy])
    }

    /// Defensive: the domain is `[String: Any]`, so nothing guarantees the types.
    @Test func test_unexpectedTypesRemoveNothingUnsafe() {
        #expect(LegacyLanguageOverride.keysToRemove(from: [legacy: 42]).isEmpty)
        #expect(LegacyLanguageOverride.keysToRemove(from: [legacy: "ar", system: "ar"]) == [legacy])
    }
}
