import Foundation
import Testing
import UIKit

@testable import SonicPlayer

/// The Home-screen quick actions — the path that kept a root `Store` alive until #19, because
/// UIKit delivers it to `AppDelegate` where there is no view and no environment.
///
/// The failure this suite exists for is not a crash. A shortcut whose `Info.plist` identifier does
/// not match the one in code still appears on the Home screen and is still tappable; it just does
/// nothing, silently, forever. Nothing else in the build compares those two strings.
@Suite(.serialized)
struct QuickActionTests {

    /// The plist is the contract iOS reads. Every type it declares must resolve to a case here.
    @Test func test_everyShortcutDeclaredInInfoPlist_resolvesToAKnownAction() throws {
        let declared = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]],
            "Info.plist declares no UIApplicationShortcutItems — the Home-screen shortcuts are gone."
        )
        #expect(!declared.isEmpty)

        for entry in declared {
            let type = try #require(entry["UIApplicationShortcutItemType"] as? String)
            #expect(
                QuickAction(rawValue: type) != nil,
                "Info.plist declares \"\(type)\", which no QuickAction case matches — that shortcut is dead."
            )
        }
    }

    /// ...and the other direction: a case with no plist entry is a shortcut that can never fire.
    @Test func test_everyAction_isDeclaredInInfoPlist() throws {
        let declared = (Bundle.main.object(forInfoDictionaryKey: "UIApplicationShortcutItems") as? [[String: Any]]) ?? []
        let types = Set(declared.compactMap { $0["UIApplicationShortcutItemType"] as? String })

        for action in QuickAction.allCases {
            #expect(types.contains(action.rawValue), "\(action) is not declared in Info.plist.")
        }
    }

    // MARK: - The delegate hop

    @MainActor
    @Test func test_theRecordShortcut_opensTheDialsRecorder() {
        let app = makeApp()

        AppDelegate().handleShortcut(shortcut(.record), target: app)

        #expect(app.dial.screen.chrome.breadcrumb == ["LIBRARY", "RECORDING"])
        #expect(!app.isImportSheetPresented)
    }

    @MainActor
    @Test func test_theImportShortcut_opensTheImportSheet() {
        let app = makeApp()

        AppDelegate().handleShortcut(shortcut(.importMedia), target: app)

        #expect(app.isImportSheetPresented)
        #expect(!app.isRecordingSheetPresented)
    }

    /// An identifier the app does not know must be ignored rather than guessed at — iOS can
    /// deliver a stale shortcut from a previous install.
    @MainActor
    @Test func test_anUnknownShortcut_doesNothing() {
        let app = makeApp()

        AppDelegate().handleShortcut(
            UIApplicationShortcutItem(type: "com.hasan.sonicplayer.nope", localizedTitle: "Nope"),
            target: app
        )

        #expect(!app.isRecordingSheetPresented)
        #expect(!app.isImportSheetPresented)
    }

    // MARK: - Helpers

    private func shortcut(_ action: QuickAction) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: action.rawValue, localizedTitle: "\(action)")
    }

    @MainActor
    private func makeApp() -> AppViewModel {
        var audioPlayer = AudioPlayerClient.test
        audioPlayer.stop = {}

        return AppViewModel(
            player: PlayerViewModel(
                audioPlayer: audioPlayer, fileManager: .test,
                artworkClient: .test, sessionStore: .inMemory()
            ),
            recording: RecordingViewModel(audioRecorder: .test, audioPlayer: audioPlayer, fileManager: .test),
            settings: SettingsViewModel(),
            filesRoot: CollectionsViewModel(currentDirectory: nil, fileManager: .test),
            onboarding: nil
        )
    }
}
