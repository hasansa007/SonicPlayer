import Foundation

/// Which of the old language keys this app may delete, given what is actually persisted (#70).
///
/// Extracted because the decision has been wrong twice. #68 deleted `AppleLanguages`
/// unconditionally, which wiped a language the user had set in iOS Settings — that key is the
/// system's too, not this app's alone. #70's first attempt keyed on whether `appLanguage` existed,
/// which is stale evidence: it proves the removed picker fired *once, ever*, and says nothing about
/// what `AppleLanguages` holds **now**. Both versions were plausible and both destroyed a live user
/// setting.
///
/// Sitting in the view layer it was unreachable by any test, so each wrong version had to be caught
/// by review. Here it is arithmetic over a dictionary, and every case below is a test.
enum LegacyLanguageOverride {

    /// Written only by the removed in-app picker. Dead state in every case.
    static let legacyKey = "appLanguage"

    /// **Shared with the system.** iOS's per-app *Preferred Language* writes the same key, so it is
    /// only ever ours to delete while it still holds what the picker put there.
    static let systemKey = "AppleLanguages"

    /// The keys that may be removed. Empty when there is nothing of this app's to clean up.
    ///
    /// - Parameter persisted: the app's **persistent** domain. Not `object(forKey:)`, which
    ///   searches `NSArgumentDomain` first and would let a launch argument conjure a key that is
    ///   not on disk — this app already takes launch arguments for screenshots.
    static func keysToRemove(from persisted: [String: Any]) -> Set<String> {
        guard let written = persisted[legacyKey] as? String else {
            // No picker value ever written, so whatever is in `AppleLanguages` is the system's.
            return []
        }

        guard (persisted[systemKey] as? [String])?.first == written else {
            // Either the picker chose "system" (which removed the key), or something has since
            // overwritten it — and the only other writer is iOS's own per-app control. That value
            // is the user's current choice and survives; the stale marker does not.
            return [legacyKey]
        }

        return [legacyKey, systemKey]
    }
}
