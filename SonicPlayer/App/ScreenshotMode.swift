import ComposableArchitecture
import Foundation
import SwiftUI

// MARK: - Screenshot Mode

/// Debug-only screenshot mode that reads launch arguments to navigate
/// directly to a target screen with stable demo data.
///
/// Launch arguments:
///   -screenshotMode YES
///   -screenshotScreen <screenName>
///   -screenshotUseDemoData YES
enum ScreenshotMode {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotMode")
    }

    static var targetScreen: Screen? {
        guard isEnabled,
              let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-screenshotScreen"),
              index + 1 < ProcessInfo.processInfo.arguments.count
        else { return nil }
        return Screen(rawValue: ProcessInfo.processInfo.arguments[index + 1])
    }

    enum Screen: String {
        case home
        case collections
        case player
        case recording
        case editRecording = "editRecording"
        case homeWithMiniPlayer = "homeWithMiniPlayer"
    }
}

// MARK: - Demo Data

enum ScreenshotDemoData {
    static let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    // MARK: - Collections

    static let collections: [CollectionItem] = [
        CollectionItem(
            id: documentsURL.appendingPathComponent("Podcasts"),
            url: documentsURL.appendingPathComponent("Podcasts"),
            name: "Podcasts",
            creationDate: Date().addingTimeInterval(-86400 * 14),
            itemCount: 12,
            subfolderCount: 0,
            totalDuration: 18720
        ),
        CollectionItem(
            id: documentsURL.appendingPathComponent("Interviews"),
            url: documentsURL.appendingPathComponent("Interviews"),
            name: "Interviews",
            creationDate: Date().addingTimeInterval(-86400 * 7),
            itemCount: 8,
            subfolderCount: 0,
            totalDuration: 14400
        ),
        CollectionItem(
            id: documentsURL.appendingPathComponent("Lectures"),
            url: documentsURL.appendingPathComponent("Lectures"),
            name: "Lectures",
            creationDate: Date().addingTimeInterval(-86400 * 3),
            itemCount: 5,
            subfolderCount: 2,
            totalDuration: 7200
        ),
        CollectionItem(
            id: documentsURL.appendingPathComponent("Voice Memos"),
            url: documentsURL.appendingPathComponent("Voice Memos"),
            name: "Voice Memos",
            creationDate: Date().addingTimeInterval(-86400 * 1),
            itemCount: 24,
            subfolderCount: 0,
            totalDuration: 3600
        ),
    ]

    // MARK: - Audio Files

    static let recentFiles: [AudioFile] = [
        AudioFile(
            url: documentsURL.appendingPathComponent("Deep Focus Session.mp3"),
            title: "Deep Focus Session",
            duration: 2745,
            fileSize: 6_612_000,
            format: .mp3,
            creationDate: Date().addingTimeInterval(-3600)
        ),
        AudioFile(
            url: documentsURL.appendingPathComponent("Morning Keynote.m4a"),
            title: "Morning Keynote",
            duration: 1832,
            fileSize: 4_400_000,
            format: .m4a,
            creationDate: Date().addingTimeInterval(-7200)
        ),
        AudioFile(
            url: documentsURL.appendingPathComponent("Interview with Sarah.mp3"),
            title: "Interview with Sarah",
            duration: 3654,
            fileSize: 8_770_000,
            format: .mp3,
            creationDate: Date().addingTimeInterval(-86400)
        ),
        AudioFile(
            url: documentsURL.appendingPathComponent("Product Review Notes.m4a"),
            title: "Product Review Notes",
            duration: 482,
            fileSize: 1_158_000,
            format: .m4a,
            creationDate: Date().addingTimeInterval(-86400 * 2)
        ),
        AudioFile(
            url: documentsURL.appendingPathComponent("Spanish Lesson 5.mp3"),
            title: "Spanish Lesson 5",
            duration: 1520,
            fileSize: 3_648_000,
            format: .mp3,
            creationDate: Date().addingTimeInterval(-86400 * 3)
        ),
        AudioFile(
            url: documentsURL.appendingPathComponent("Team Standup Mar 28.m4a"),
            title: "Team Standup Mar 28",
            duration: 912,
            fileSize: 2_189_000,
            format: .m4a,
            creationDate: Date().addingTimeInterval(-86400 * 4)
        ),
        AudioFile(
            url: documentsURL.appendingPathComponent("Meditation Guide.mp3"),
            title: "Meditation Guide",
            duration: 605,
            fileSize: 1_452_000,
            format: .mp3,
            creationDate: Date().addingTimeInterval(-86400 * 5)
        ),
    ]

    // MARK: - Collection Browser Files (inside "Podcasts" folder)

    static let collectionFiles: [AudioFile] = [
        AudioFile(
            url: documentsURL.appendingPathComponent("Podcasts/Tech Today Ep 42.mp3"),
            title: "Tech Today Ep 42",
            duration: 2580,
            fileSize: 6_192_000,
            format: .mp3,
            creationDate: Date().addingTimeInterval(-86400)
        ),
        AudioFile(
            url: documentsURL.appendingPathComponent("Podcasts/Design Matters.m4a"),
            title: "Design Matters",
            duration: 3120,
            fileSize: 7_488_000,
            format: .m4a,
            creationDate: Date().addingTimeInterval(-86400 * 2)
        ),
        AudioFile(
            url: documentsURL.appendingPathComponent("Podcasts/The Daily Brief.mp3"),
            title: "The Daily Brief",
            duration: 1845,
            fileSize: 4_428_000,
            format: .mp3,
            creationDate: Date().addingTimeInterval(-86400 * 3)
        ),
        AudioFile(
            url: documentsURL.appendingPathComponent("Podcasts/Code Review Live.m4a"),
            title: "Code Review Live",
            duration: 4210,
            fileSize: 10_104_000,
            format: .m4a,
            creationDate: Date().addingTimeInterval(-86400 * 5)
        ),
        AudioFile(
            url: documentsURL.appendingPathComponent("Podcasts/Startup Stories.mp3"),
            title: "Startup Stories",
            duration: 2890,
            fileSize: 6_936_000,
            format: .mp3,
            creationDate: Date().addingTimeInterval(-86400 * 7)
        ),
    ]

    // MARK: - State Builders

    static func buildAppState(for screen: ScreenshotMode.Screen) -> AppFeature.State {
        var state = AppFeature.State()
        // Onboarding is skipped in screenshot mode by OnboardingViewModel.ifNeeded()

        switch screen {
        case .home:
            populateHome(&state)

        case .homeWithMiniPlayer:
            populateHome(&state)
            populateMiniPlayer(&state)

        case .collections:
            populateHome(&state)
            populateCollectionsBrowser(&state)

        case .player:
            populateHome(&state)
            populateFullPlayer(&state)

        case .recording, .editRecording:
            // Recording/edit states are handled via sheets after launch
            populateHome(&state)
        }

        return state
    }

    // MARK: - State Population

    private static func populateHome(_ state: inout AppFeature.State) {
        state.home.recentFiles = recentFiles

        // Build filesystem items from collections + recent files
        let folderItems: [FileSystemItem] = collections.map { .folder($0) }
        let fileItems: [FileSystemItem] = recentFiles.prefix(5).map { .file($0) }
        state.filesRoot.items = folderItems + fileItems

        // Build collection cards
        var cards: IdentifiedArrayOf<CollectionItemCardFeature.State> = []
        for collection in collections {
            cards.append(CollectionItemCardFeature.State(folder: collection))
        }
        state.filesRoot.collectionCards = cards

        // Build file rows
        var rows: IdentifiedArrayOf<FileRowFeature.State> = []
        for file in recentFiles.prefix(5) {
            var row = FileRowFeature.State(file: file)
            row.creationDate = file.creationDate
            rows.append(row)
        }
        state.filesRoot.fileRows = rows
    }

    private static func populateMiniPlayer(_ state: inout AppFeature.State) {
        let track = recentFiles[0]
        state.player.currentTrack = track
        state.player.isPlaying = true
        state.player.isExpanded = false
        state.player.duration = track.duration
        state.player.currentTime = 847 // ~14 min into the track
        state.player.queue = [track] + Array(recentFiles.dropFirst().prefix(3))
        state.player.currentIndex = 0

        state.home.lastPlayedTrack = track
        state.home.isPlaying = true
        state.home.playbackProgress = 847 / track.duration
    }

    private static func populateCollectionsBrowser(_ state: inout AppFeature.State) {
        // Push a collections view onto the navigation stack showing "Podcasts" folder
        var collectionsState = CollectionsFeature.State(
            currentDirectory: documentsURL.appendingPathComponent("Podcasts")
        )

        // Nested subfolders
        let subCollections: [CollectionItem] = [
            CollectionItem(
                id: documentsURL.appendingPathComponent("Podcasts/Favorites"),
                url: documentsURL.appendingPathComponent("Podcasts/Favorites"),
                name: "Favorites",
                creationDate: Date().addingTimeInterval(-86400 * 10),
                itemCount: 3,
                subfolderCount: 0,
                totalDuration: 5400
            ),
            CollectionItem(
                id: documentsURL.appendingPathComponent("Podcasts/Archive"),
                url: documentsURL.appendingPathComponent("Podcasts/Archive"),
                name: "Archive",
                creationDate: Date().addingTimeInterval(-86400 * 20),
                itemCount: 15,
                subfolderCount: 0,
                totalDuration: 28800
            ),
        ]

        let folderItems: [FileSystemItem] = subCollections.map { .folder($0) }
        let fileItems: [FileSystemItem] = collectionFiles.map { .file($0) }
        collectionsState.items = folderItems + fileItems

        // Build child states
        var cards: IdentifiedArrayOf<CollectionItemCardFeature.State> = []
        for sub in subCollections {
            cards.append(CollectionItemCardFeature.State(folder: sub))
        }
        collectionsState.collectionCards = cards

        var rows: IdentifiedArrayOf<FileRowFeature.State> = []
        for file in collectionFiles {
            var row = FileRowFeature.State(file: file)
            row.creationDate = file.creationDate
            rows.append(row)
        }
        collectionsState.fileRows = rows

        state.filesPath.append(collectionsState)
    }

    private static func populateFullPlayer(_ state: inout AppFeature.State) {
        let track = recentFiles[0]
        state.player.currentTrack = track
        state.player.isPlaying = true
        state.player.isExpanded = true
        state.player.duration = track.duration
        state.player.currentTime = 1234
        state.player.queue = Array(recentFiles.prefix(5))
        state.player.currentIndex = 0
    }
}
