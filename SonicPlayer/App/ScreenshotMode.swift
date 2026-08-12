import Foundation
import SwiftUI

// MARK: - Screenshot Mode

/// Debug-only screenshot mode that reads launch arguments to navigate
/// directly to a target screen with stable demo data.
///
/// Launch arguments:
///   -screenshotMode                    presence is the switch; any value is ignored
///   -screenshotScreen <screenName>     one of `Screen` below
///   -screenshotPage <n>                onboarding only — which page to land on
///
/// **`-screenshotUseDemoData` is gone from here because nothing ever read it.** Both capture
/// scripts passed it and this list promised it worked; the seeding is unconditional in
/// `seedViewModels`. An argument documented as a switch that is not one is worse than an
/// undocumented one, because the next person turns it off and nothing changes.
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

    /// Which onboarding page to land on, for `-screenshotScreen onboarding`. Defaults to the first.
    static var page: Int {
        guard isEnabled,
              let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-screenshotPage"),
              index + 1 < ProcessInfo.processInfo.arguments.count
        else { return 0 }
        return Int(ProcessInfo.processInfo.arguments[index + 1]) ?? 0
    }

    /// **Named for dial routes, because that is what the app has.**
    ///
    /// This listed `collections`, `editRecording` and `homeWithMiniPlayer`, and by the time anyone
    /// looked, four of the six rendered the dial regardless — the screens they named had stopped
    /// being reachable one at a time and nothing here noticed. A screenshot target aimed at code
    /// that cannot be shown is worse than a missing one: it produces an image, and the image is of
    /// something else.
    enum Screen: String {
        /// The file list, which is the root — there is no screen above it.
        ///
        /// **`home` is gone rather than aliased to this.** It named the Listen-or-Record fork, and
        /// the fork was deleted when the library became the root (#6). Kept as a synonym it would
        /// have gone on producing an image of the library under a name that promises a chooser —
        /// which is the exact defect the note above this enum records, preserved by kindness.
        case library
        case player
        case recording
        /// The trim editor, on the highlighted recording.
        case edit
        /// The settings list, reached by its chip the way every screen reaches it.
        case settings

        /// **The first run, which every other target deliberately skips** (#102).
        ///
        /// Onboarding is the one screen that cannot be reached twice: `ifNeeded` returns `nil` for
        /// good the moment it is completed, so seeing page 4 meant deleting the app or editing code
        /// — and during #102 it meant a temporary launch argument that had to be remembered out
        /// again before committing. Pair it with `-screenshotPage` to land on one page.
        case onboarding

        // The player's three non-happy states (#6). They exist here because epic #6 requires every
        // screen to have designed empty, loading and error states — and a state nobody can put on
        // screen is a state nobody checks. These are the only way to see them without editing code.
        case playerEmpty = "playerEmpty"
        case playerLoading = "playerLoading"
        case playerError = "playerError"
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

    static let allFiles: [AudioFile] = [
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
    //
    // `buildAppState` is gone with #18: `AppFeature.State` is three sheet flags now, and every
    // screen's demo data lives on a view model. `AppView` calls `seedViewModels` instead.

}

// MARK: - Seeding the view models

extension ScreenshotDemoData {

    /// Player and Home are `@Observable` view models rather than reducer state (#15, #16), so
    /// `buildAppState` cannot reach them. `AppView` calls this instead.
    ///
    /// Miss it and every screenshot run renders an empty Home and a dead player — the same class
    /// of break as the onboarding skip that moved in #14.
    @MainActor
    static func seedViewModels(
        player: PlayerViewModel,
        home: HomeViewModel,
        filesRoot: CollectionsViewModel,
        for screen: ScreenshotMode.Screen
    ) {
        home.allFiles = allFiles
        filesRoot.seed(items: collections.map { .folder($0) } + allFiles.prefix(5).map { .file($0) })

        switch screen {
        case .player:
            let track = allFiles[0]
            player.currentTrack = track
            player.isPlaying = true
            player.isExpanded = true
            player.duration = track.duration
            player.currentTime = 1234
            player.queue = Array(allFiles.prefix(5))
            player.currentIndex = 0

        // The three states, each pinned to the exact condition the view branches on.

        case .playerEmpty:
            player.isExpanded = true

        case .playerLoading:
            // "Loading" is not "no track": `loadTrack` sets both in the same breath, and the view
            // gates on a zero duration so the state stays off screen during a track *switch*.
            player.currentTrack = allFiles[0]
            player.isExpanded = true
            player.isLoadingTrack = true
            player.duration = 0

        case .playerError:
            player.isExpanded = true
            player.openError = String(
                localized: "The file could not be read. It may have been moved or deleted."
            )

        case .library, .recording, .edit, .settings, .onboarding:
            break
        }
    }
}
