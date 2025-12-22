import ComposableArchitecture

private enum AudioPreviewPlayerKey: DependencyKey {
    static let liveValue: AudioPlayerClient = .liveValue
    static let testValue: AudioPlayerClient = .testValue
}

extension DependencyValues {
    var audioPreviewPlayer: AudioPlayerClient {
        get { self[AudioPreviewPlayerKey.self] }
        set { self[AudioPreviewPlayerKey.self] = newValue }
    }
}
