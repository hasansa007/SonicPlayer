import Foundation
import Testing

@testable import SonicPlayer

/// About and How it works, as values (#50).
///
/// **This is what making them dial screens buys.** They were two `ScrollView`s of hand-built cards —
/// 607 lines and ten one-off components — and nothing about them could be asserted without rendering
/// a view. As routes over `InfoContent` the whole of both screens is checkable here.
@Suite
struct InfoScreenTests {

    private func inSettings() -> DialNavigator {
        var navigator = DialSample.navigator()
        _ = navigator.receive(.action("settings"))
        return navigator
    }

    /// The row index has to match `DialSetting.allCases`, which is what the press reads.
    private func open(_ setting: DialSetting, from navigator: inout DialNavigator) {
        let index = DialSetting.allCases.firstIndex(of: setting)!
        _ = navigator.receive(.tick(index))
        _ = navigator.receive(.press)
    }

    @Test func theAboutRowOpensAScreenRatherThanASheet() {
        var navigator = inSettings()
        open(.about, from: &navigator)

        #expect(navigator.route == .about)
        guard case .list(let list) = navigator.screen.content else {
            Issue.record("About should be a list, got \(navigator.screen.content)")
            return
        }
        #expect(list.rows.count == InfoContent.about.count)
        #expect(navigator.screen.chrome.breadcrumb.last == "ABOUT")
    }

    /// **The version is the one thing the old screen said that the rewrite dropped.** It was a
    /// `Text` under the app name; the chrome's status line is the dial's equivalent, and nothing put
    /// it there until it was noticed on a build.
    @Test func aboutStatesTheAppVersion() {
        var navigator = inSettings()
        open(.about, from: &navigator)

        #expect(navigator.screen.chrome.status == InfoContent.version)
        #expect(navigator.screen.chrome.status?.isEmpty == false, "the bundle should yield a version")
    }

    @Test func theHelpRowOpensHowItWorks() {
        var navigator = inSettings()
        open(.help, from: &navigator)

        #expect(navigator.route == .help)
        #expect(navigator.screen.chrome.breadcrumb.last == "HOW IT WORKS")
    }

    /// **The paragraph gets its own screen.** This is the argument for the whole shape: the dial is
    /// poor at prose in a row and fine at prose on a screen.
    @Test func pressingAQuestionOpensItsAnswer() {
        var navigator = inSettings()
        open(.help, from: &navigator)
        _ = navigator.receive(.tick(4))          // "How do I trim a recording?"
        let entry = InfoContent.help[4]

        _ = navigator.receive(.press)

        #expect(navigator.route == .infoDetail(id: entry.id, inHelp: true))
        guard case .message(let message) = navigator.screen.content else {
            Issue.record("an answer should be a message, got \(navigator.screen.content)")
            return
        }
        #expect(message.title == entry.title)
        #expect(message.body == entry.body)
    }

    /// **The route carries the id, not the index.** Reordering the list must not point a detail at
    /// the wrong entry — the offset bug this codebase has paid for twice.
    @Test func theDetailRouteIsKeyedByIdNotPosition() {
        var navigator = inSettings()
        open(.about, from: &navigator)
        _ = navigator.receive(.tick(3))
        _ = navigator.receive(.press)

        guard case .infoDetail(let id, let inHelp) = navigator.route else {
            Issue.record("expected a detail route, got \(navigator.route)")
            return
        }
        #expect(id == InfoContent.about[3].id)
        #expect(!inHelp)
    }

    @Test func theDetailHubGoesBack() {
        var navigator = inSettings()
        open(.help, from: &navigator)
        _ = navigator.receive(.press)
        #expect(navigator.screen.ring.hub == .label("BACK"))

        _ = navigator.receive(.press)

        #expect(navigator.route == .help, "the hub on a detail returns to its list")
    }

    /// Every entry has to survive the round trip, or a row opens an empty screen.
    @Test func everyEntryResolvesFromItsId() {
        for entry in InfoContent.about {
            #expect(InfoContent.entry(entry.id, in: InfoContent.about)?.title == entry.title)
        }
        for entry in InfoContent.help {
            #expect(InfoContent.entry(entry.id, in: InfoContent.help)?.title == entry.title)
        }
    }

    /// **The copy describes the app that exists.** The shipped Help was a manual for the one the dial
    /// replaced, which is the half of this issue a restyle would not have touched.
    @Test func noAnswerMentionsAScreenTheAppNoLongerHas() {
        let gone = ["tab", "+ button", "Player view", "skip buttons", "pull to refresh", "Recordings tab"]
        for entry in InfoContent.help + InfoContent.about {
            for phrase in gone {
                #expect(!entry.body.localizedCaseInsensitiveContains(phrase),
                        "\(entry.id) still mentions \"\(phrase)\"")
            }
        }
    }
}

/// The Settings chip inside the settings path (#50).
@Suite
struct SettingsChipTests {

    private func inSettings() -> DialNavigator {
        var navigator = DialSample.navigator()
        _ = navigator.receive(.action("settings"))
        return navigator
    }

    @Test func theSettingsChipIsDeadOnTheSettingsScreen() {
        #expect(!inSettings().isChipEnabled("settings"))
    }

    /// **The regression this fixes.** About and How it works are pushed on top of Settings, and the
    /// rule asked only about the current route — so the chip came back to life one level down and
    /// would have stacked a second Settings on top of the one you were already inside.
    @Test func theSettingsChipStaysDeadInsideAboutAndHelp() {
        for setting in [DialSetting.about, .help] {
            var navigator = inSettings()
            let index = DialSetting.allCases.firstIndex(of: setting)!
            _ = navigator.receive(.tick(index))
            _ = navigator.receive(.press)

            #expect(!navigator.isChipEnabled("settings"), "\(setting) is inside the settings path")

            _ = navigator.receive(.press)   // and on the detail screen below it
            #expect(!navigator.isChipEnabled("settings"))
        }
    }

    /// The complement — it is alive everywhere else, or the rule would be a different bug.
    @Test func theSettingsChipIsAliveInTheLibrary() {
        #expect(DialSample.navigator().isChipEnabled("settings"))
    }
}
