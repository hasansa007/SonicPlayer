import Foundation

/// The playback seam, as a protocol (#44).
///
/// The same bargain as `FileManaging`: `AudioPlayerClient` **conforms** rather than being
/// replaced, so `.live` and `.test` stay `AudioPlayerClient` values, every `client.stop = { … }`
/// line across the test target keeps compiling, and `.test` keeps reporting an issue for any
/// closure a path reaches without stubbing — behaviour a hand-written mock class would have had
/// to reimplement fifteen times over.
///
/// **The method names deliberately differ from the client's stored properties.** A stored
/// `var pause` and a `func pause()` cannot coexist on one type, so each requirement reads as an
/// interface (`pausePlayback()`) and the conformance below forwards to the closure. That rename
/// is what `ClientProtocolConformanceTests` exists to police: nothing in the type system stops
/// `pausePlayback()` from forwarding to `stop`.
///
/// **Nothing in the app calls this yet**, and that is the honest state of it. The protocol is
/// declared now because #44 pairs it with `FileManaging` as the two boundaries the StudyHub epics
/// will need — #7 and #9 are where a second implementation arrives. If those epics change shape
/// and it never gets one, this is the first thing to delete; `ARCHITECTURE.md` says the same
/// about `PlaybackRepository`.
protocol AudioPlaying: Sendable {
    func prepareToPlay(_ url: URL) async throws
    func startPlayback(of url: URL) async throws
    func pausePlayback() async
    func resumePlayback() async
    func stopPlayback() async
    func seekToTime(_ time: TimeInterval) async
    func changeRate(to rate: Float) async
    func changeVolume(to volume: Float) async
    func skipAhead(by interval: TimeInterval) async
    func skipBack(by interval: TimeInterval) async
    func refreshNowPlaying() async
    func assignRemoteHandlers(nextTrack: @escaping () -> Void, previousTrack: @escaping () -> Void)
    func elapsedTime() async -> TimeInterval
    func trackDuration() async -> TimeInterval
    func playbackIsActive() async -> Bool
    func timeStream() async -> AsyncStream<TimeInterval>
}

extension AudioPlayerClient: AudioPlaying {
    func prepareToPlay(_ url: URL) async throws { try await prepare(url) }
    func startPlayback(of url: URL) async throws { try await play(url) }
    func pausePlayback() async { await pause() }
    func resumePlayback() async { await resume() }
    func stopPlayback() async { await stop() }
    func seekToTime(_ time: TimeInterval) async { await seek(time) }
    func changeRate(to rate: Float) async { await setRate(rate) }
    func changeVolume(to volume: Float) async { await setVolume(volume) }
    func skipAhead(by interval: TimeInterval) async { await skipForward(interval) }
    func skipBack(by interval: TimeInterval) async { await skipBackward(interval) }
    func refreshNowPlaying() async { await updateNowPlaying() }
    func assignRemoteHandlers(nextTrack: @escaping () -> Void, previousTrack: @escaping () -> Void) {
        setRemoteHandlers(nextTrack, previousTrack)
    }
    func elapsedTime() async -> TimeInterval { await currentTime() }
    func trackDuration() async -> TimeInterval { await duration() }
    func playbackIsActive() async -> Bool { await isPlaying() }
    func timeStream() async -> AsyncStream<TimeInterval> { await timeUpdates() }
}
