import Foundation
import Testing

@testable import SonicPlayer

/// The seam #75's persistence decision will land on, and the one rule it already has to get right.
@Suite
struct MarkerRegistryTests {

    private static let recording = URL(fileURLWithPath: "/Recordings/Lecture.m4a")

    @MainActor
    @Test func aRecordingWithNothingFiledHasNoMarkers() {
        let registry = MarkerRegistry()

        #expect(registry.markers(for: Self.recording).isEmpty)
    }

    @MainActor
    @Test func markersComeBackUnderTheNameTheyWereFiledAgainst() {
        let registry = MarkerRegistry()

        registry.set(RecordingMarkers(times: [30, 90]), for: Self.recording)

        #expect(registry.markers(for: Self.recording).times == [30, 90])
    }

    @MainActor
    @Test func aDifferentRecordingDoesNotSeeThem() {
        let registry = MarkerRegistry()
        registry.set(RecordingMarkers(times: [30]), for: Self.recording)

        let other = registry.markers(for: URL(fileURLWithPath: "/Recordings/Other.m4a"))

        #expect(other.isEmpty)
    }

    /// **The correctness rule, not a tidiness one.** Delete a recording and record another, and
    /// `UniqueNameResolver` is free to hand out the same name again — at which point the new take
    /// would inherit the dead one's markers and the editor would snap to points that were never in
    /// the audio.
    @MainActor
    @Test func forgettingAPathStopsTheNextRecordingInheritingItsMarkers() {
        let registry = MarkerRegistry()
        registry.set(RecordingMarkers(times: [30, 90]), for: Self.recording)

        registry.forget(Self.recording)

        #expect(registry.markers(for: Self.recording).isEmpty)
    }

    /// Filing an empty set is how a take with no markers reports itself, and it must not leave an
    /// entry behind that a later `forget` has to clean up.
    @MainActor
    @Test func filingAnEmptySetStoresNothing() {
        let registry = MarkerRegistry()
        registry.set(RecordingMarkers(times: [30]), for: Self.recording)

        registry.set(RecordingMarkers(), for: Self.recording)

        #expect(registry.markers(for: Self.recording).isEmpty)
    }
}
