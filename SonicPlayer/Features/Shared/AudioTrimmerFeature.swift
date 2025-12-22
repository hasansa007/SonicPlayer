import AVFoundation
import ComposableArchitecture
import Foundation

@Reducer
struct AudioTrimmerFeature {
    @ObservableState
    struct State: Equatable {
        let audioFile: AudioFile
        var duration: TimeInterval
        var trimStart: TimeInterval = 0
        var trimEnd: TimeInterval
        var currentTime: TimeInterval = 0
        var isPlaying: Bool = false
        var isTrimming: Bool = false

        init(audioFile: AudioFile) {
            self.audioFile = audioFile
            self.duration = audioFile.duration
            self.trimEnd = audioFile.duration
        }

        var trimDuration: TimeInterval {
            trimEnd - trimStart
        }

        var timeRangeText: String {
            "\(formatTime(trimStart)) - \(formatTime(trimEnd))"
        }

        private func formatTime(_ time: TimeInterval) -> String {
            let minutes = Int(time) / 60
            let seconds = Int(time) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    enum Action {
        case onAppear
        case cancelTapped
        case applyTapped
        case trimTapped
        case deleteTapped
        case playPauseTapped
        case skipBackward
        case skipForward
        case seek(TimeInterval)
        case setTrimStart(TimeInterval)
        case setTrimEnd(TimeInterval)
        case timeUpdate(TimeInterval)
        case trimCompleted(Result<URL, Error>)
        case delegate(Delegate)

        enum Delegate {
            case dismiss
            case trimApplied
        }
    }

    @Dependency(\.audioTrimmer) var audioTrimmer
    @Dependency(\.continuousClock) var clock

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .none

            case .cancelTapped:
                return .send(.delegate(.dismiss))

            case .applyTapped:
                state.isTrimming = true
                let url = state.audioFile.url
                let start = state.trimStart
                let end = state.trimEnd

                return .run { send in
                    await send(.trimCompleted(
                        Result {
                            try await audioTrimmer.trimAudio(url, start, end)
                        }
                    ))
                }

            case .trimTapped:
                // Move playhead to trim start
                state.currentTime = state.trimStart
                return .none

            case .deleteTapped:
                // Delete the portion outside trim range
                // For now, just apply the trim (same as Apply)
                return .send(.applyTapped)

            case .playPauseTapped:
                state.isPlaying.toggle()
                // TODO: Integrate with audio player
                return .none

            case .skipBackward:
                state.currentTime = max(0, state.currentTime - 15)
                return .none

            case .skipForward:
                state.currentTime = min(state.duration, state.currentTime + 15)
                return .none

            case let .seek(time):
                state.currentTime = max(0, min(state.duration, time))
                return .none

            case let .setTrimStart(time):
                state.trimStart = max(0, min(time, state.trimEnd - 0.1))
                return .none

            case let .setTrimEnd(time):
                state.trimEnd = max(state.trimStart + 0.1, min(time, state.duration))
                return .none

            case let .timeUpdate(time):
                state.currentTime = time
                return .none

            case .trimCompleted(.success):
                state.isTrimming = false
                return .send(.delegate(.trimApplied))

            case let .trimCompleted(.failure(error)):
                state.isTrimming = false
                // TODO: Show error alert
                print("Trim failed: \(error.localizedDescription)")
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
