import Foundation

/// Queue sequencing decisions, lifted out of `PlayerFeature`'s reducer.
///
/// This is the densest branching in the app and the least visible when it goes wrong — an
/// off-by-one in the end-of-track branch means the last track of a queue silently restarts,
/// or the queue stops one short.
enum QueueMath {

    // MARK: - End of track

    enum TrackEndDecision: Equatable {
        /// Repeat-one: seek to zero and keep playing.
        case repeatCurrent
        /// Advance to the next track.
        case advance
        /// Repeat-all with no next track: wrap to index 0.
        case wrapToStart
        /// End of queue: pause and park at the end of the current track.
        case stop
    }

    /// Returns `nil` while the track is still playing — the caller then falls through to its
    /// normal per-tick work.
    ///
    /// The 1-second threshold is inherited: playback position is polled roughly twice a second,
    /// so "finished" means "within a tick of the end" rather than an exact match.
    static func decideOnTrackEnd(
        isPlaying: Bool,
        duration: TimeInterval,
        currentTime: TimeInterval,
        repeatMode: RepeatMode,
        hasNextTrack: Bool,
        queueIsEmpty: Bool
    ) -> TrackEndDecision? {
        guard isPlaying, duration > 0, (duration - currentTime) < 1.0 else { return nil }

        if repeatMode == .one { return .repeatCurrent }
        if hasNextTrack { return .advance }
        if repeatMode == .all, !queueIsEmpty { return .wrapToStart }
        return .stop
    }

    // MARK: - Previous track

    enum PreviousDecision: Equatable {
        /// Restart the current track from zero.
        case restart
        /// Step back to `index`.
        case previous(index: Int)
    }

    /// More than `restartThreshold` seconds in, "previous" restarts the current track rather
    /// than stepping back — the behaviour every music player has.
    static func decideOnPrevious(
        currentTime: TimeInterval,
        hasPreviousTrack: Bool,
        currentIndex: Int,
        restartThreshold: TimeInterval = 3
    ) -> PreviousDecision {
        if currentTime > restartThreshold { return .restart }
        guard hasPreviousTrack else { return .restart }
        return .previous(index: currentIndex - 1)
    }

    // MARK: - Repeat mode

    /// Cycles off -> all -> one -> off.
    static func nextRepeatMode(after mode: RepeatMode) -> RepeatMode {
        switch mode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    // MARK: - Shuffle

    /// Shuffles `queue` while pinning `current` to the front, so the playing track keeps playing.
    ///
    /// `shuffle` is injected purely so this is testable; production passes `shuffled()`.
    /// Returns the original queue unchanged when there is no current track, matching the
    /// existing behaviour of doing nothing in that case.
    static func shuffling(
        _ queue: [AudioFile],
        keeping current: AudioFile?,
        shuffle: ([AudioFile]) -> [AudioFile] = { $0.shuffled() }
    ) -> (queue: [AudioFile], currentIndex: Int)? {
        guard let current else { return nil }
        var rest = queue
        rest.removeAll { $0 == current }
        return ([current] + shuffle(rest), 0)
    }
}
