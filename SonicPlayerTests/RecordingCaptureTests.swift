import Foundation
import Synchronization  // Mutex — the gain closure is @Sendable
import Testing

@testable import SonicPlayer

/// Pause, markers and input gain — the three things `DialEffect` asked for and nothing answered
/// (#75).
///
/// The polling loops follow `OpenFromFilesTests`: bounded, and they exit the moment the condition
/// holds rather than sleeping a fixed interval. A change that never arrives fails the expectation
/// below instead of passing on a timer.
@Suite(.serialized)
struct RecordingCaptureTests {

    // MARK: - Markers

    @MainActor
    @Test func aMarkerLandsAtTheElapsedTime() {
        let model = Self.makeModel()
        model.isRecording = true
        model.recordingTime = 62.4

        let added = model.addMarker()

        #expect(added)
        #expect(model.markers.times == [62.4])
    }

    /// The dial can only reach `addMarker` from the recording screen, but the view cannot be the
    /// thing that guarantees it — a chip left enabled one frame too long would file a marker against
    /// a take that has stopped.
    @MainActor
    @Test func aMarkerIsRefusedWhenNothingIsBeingCaptured() {
        let model = Self.makeModel()

        let added = model.addMarker()

        #expect(!added)
        #expect(model.markers.isEmpty)
    }

    /// Pausing freezes the clock, so every tap reports the same elapsed time and only the first can
    /// become a marker. Without `RecordingMarkers`' separation rule this is a pile of duplicates.
    @MainActor
    @Test func tappingRepeatedlyWhileTheClockIsFrozenProducesOneMarker() {
        let model = Self.makeModel()
        model.isRecording = true
        model.recordingTime = 120

        model.addMarker()
        model.addMarker()
        model.addMarker()

        #expect(model.markers.times == [120])
    }

    @MainActor
    @Test func startingATakeClearsTheMarkersOfThePreviousOne() async {
        let model = Self.makeModel()
        model.isRecording = true
        model.recordingTime = 30
        model.addMarker()
        #expect(model.markers.count == 1)

        await Self.startCapture(model)

        #expect(model.markers.isEmpty, "A new take starts with no markers, not the last one's.")
    }

    // MARK: - Pause

    @MainActor
    @Test func pausingLeavesTheTakeInProgress() {
        let model = Self.makeModel()
        model.isRecording = true

        model.togglePauseTapped()

        #expect(model.isPaused)
        #expect(model.isRecording, "Pausing does not end the take — only stopping does.")
    }

    @MainActor
    @Test func pausingIsRefusedWhenNothingIsBeingCaptured() {
        let model = Self.makeModel()

        model.togglePauseTapped()

        #expect(!model.isPaused)
    }

    @MainActor
    @Test func resumingClearsThePauseOnceTheRecorderTakesTheFileBack() async {
        let model = Self.makeModel()
        model.isRecording = true
        model.pauseTapped()

        model.resumeTapped()
        for _ in 0..<40 where model.isPaused {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(!model.isPaused)
    }

    /// The one outcome worse than a stuck pause button: a running clock over a file the recorder
    /// never took back.
    @MainActor
    @Test func aResumeTheRecorderRefusesLeavesThePauseStanding() async {
        let model = Self.makeModel(recorder: Self.recorder(resume: { false }))
        model.isRecording = true
        model.pauseTapped()

        model.resumeTapped()
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(model.isPaused, "A refused resume must not clear the flag.")
    }

    @MainActor
    @Test func stoppingClearsThePause() {
        let model = Self.makeModel()
        model.isRecording = true
        model.pauseTapped()

        model.stopRecordingTapped()

        #expect(!model.isPaused)
        #expect(!model.isRecording)
    }

    // MARK: - Input gain

    @MainActor
    @Test func gainIsRefusedOnHardwareThatHasNone() async {
        let model = Self.makeModel()
        await Self.startCapture(model)

        model.setGain(0.3)

        #expect(!model.isGainSettable)
        #expect(model.gain == 1, "Nothing to set, so nothing moves — the dial refuses the axis.")
    }

    /// It is a *system* setting, so the value the session is already on is read rather than assumed.
    @MainActor
    @Test func theStartingGainIsReadFromTheSessionRatherThanAssumed() async {
        let model = Self.makeModel(recorder: Self.recorder(
            gainSettable: { true }, inputGain: { 0.4 }
        ))

        await Self.startCapture(model)
        for _ in 0..<40 where !model.isGainSettable {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(model.isGainSettable)
        #expect(abs(model.gain - 0.4) < 1e-6)
    }

    @MainActor
    @Test func gainIsPushedAtTheSessionWhenTheHardwareHasIt() async {
        let pushed = Mutex<Float?>(nil)
        let model = Self.makeModel(recorder: Self.recorder(
            gainSettable: { true },
            inputGain: { 0.5 },
            setGain: { value in pushed.withLock { $0 = value }; return true }
        ))
        await Self.startCapture(model)
        for _ in 0..<40 where !model.isGainSettable {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        model.setGain(0.3)
        for _ in 0..<40 where pushed.withLock({ $0 }) == nil {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(abs(model.gain - 0.3) < 1e-6)
        #expect(pushed.withLock { $0 } == 0.3)
    }

    @MainActor
    @Test func gainIsClampedToTheUnitRange() async {
        let model = Self.makeModel(recorder: Self.recorder(
            gainSettable: { true }, inputGain: { 0.5 }
        ))
        await Self.startCapture(model)
        for _ in 0..<40 where !model.isGainSettable {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }

        model.setGain(4)
        #expect(model.gain == 1)

        model.setGain(-4)
        #expect(model.gain == 0)
    }

    // MARK: - Levels

    /// The dial's scrolling waveform is a window, not an ever-growing array — a 90-minute lecture at
    /// the meter's cadence would otherwise accumulate 54,000 samples behind a view showing 50.
    @Test func theLevelWindowIsFiveSecondsAtTheMeterCadence() {
        #expect(RecordingViewModel.levelWindow == 50)
        #expect(RecordingViewModel.meterInterval == .milliseconds(100))
    }

    // MARK: -

    @MainActor
    private static func makeModel(recorder: AudioRecorderClient? = nil) -> RecordingViewModel {
        var player = AudioPlayerClient.test
        player.stop = {}
        return RecordingViewModel(
            audioRecorder: recorder ?? Self.recorder(), audioPlayer: player, fileManager: .test
        )
    }

    /// Drives the real start path rather than setting `isRecording` by hand, because reading the
    /// input gain is something `recordingStarted` does — a test that skipped it would be asserting
    /// against a capture that never began.
    @MainActor
    private static func startCapture(_ model: RecordingViewModel) async {
        model.hasPermission = true
        model.startRecordingTapped()
        for _ in 0..<40 where !model.isRecording {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// `AudioRecorderClient`'s closures are `let`, so a test cannot override one on a copy the way
    /// `ShellWiringTests` does with `AudioPlayerClient`. Building the whole thing here once beats
    /// widening the shipping type to `var` for the test target's convenience.
    private static func recorder(
        resume: @escaping @Sendable () async -> Bool = { true },
        gainSettable: @escaping @Sendable () async -> Bool = { false },
        inputGain: @escaping @Sendable () async -> Float = { 1 },
        setGain: @escaping @Sendable (Float) async -> Bool = { _ in false }
    ) -> AudioRecorderClient {
        AudioRecorderClient(
            checkPermissions: { true },
            requestPermissions: { true },
            startRecording: { _ in },
            stopRecording: { nil },
            currentTime: { 0 },
            peakPower: { 0 },
            isRecording: { false },
            pauseRecording: {},
            resumeRecording: resume,
            isInputGainSettable: gainSettable,
            inputGain: inputGain,
            setInputGain: setGain
        )
    }
}
