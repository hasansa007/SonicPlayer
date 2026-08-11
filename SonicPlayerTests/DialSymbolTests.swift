import Foundation
import Testing
import UIKit

@testable import SonicPlayer

/// Every SF Symbol the dial names actually exists.
///
/// **A misspelled symbol renders as nothing at all** — no compile error, no crash, just a blank
/// where an icon should be. That is invisible in a diff and invisible in a screenshot of a screen
/// you did not happen to open, which is exactly how the gear stick's volume marks could have
/// shipped unlabelled.
@Suite
struct DialSymbolTests {

    @Test func everyHubGlyphResolves() {
        for symbol in DialScreen.Hub.allDialGlyphs {
            #expect(UIImage(systemName: symbol) != nil, "no SF Symbol named \(symbol)")
        }
    }

    @Test func everyIconRoleResolves() {
        for icon in DialScreen.Icon.allDialCases {
            guard let symbol = DialIcon.systemImage(for: icon) else { continue }
            #expect(UIImage(systemName: symbol) != nil, "\(icon) maps to a missing symbol: \(symbol)")
        }
    }
}

private extension DialScreen.Hub {
    /// The raw SF Symbol names the navigator can put in the hub.
    ///
    /// `Hub.glyph` carries a **string** rather than an `Icon`, so `DialIcon` never sees these and
    /// `everyIconRoleResolves` cannot reach them. They are the one remaining place a misspelling
    /// renders as an empty hub. Direction marks used to be that place too; since the gear stick
    /// they resolve through `DialIcon.systemImage(for:)` and are covered by the icon test instead.
    ///
    /// Listed by hand for the same reason `allDialCases` is: forgetting to add one costs only
    /// this test.
    static let allDialGlyphs: [String] = ["play.fill", "pause.fill"]
}

private extension DialScreen.Icon {
    /// The contract's `Icon` is not `CaseIterable` — it does not need to be for its own sake, and
    /// adding the conformance to the shared file to serve one test would be the test leaking into
    /// the design. Listed here instead, where forgetting to add a case costs only this test.
    static let allDialCases: [DialScreen.Icon] = [
        .playlist, .recording, .session, .podcast, .stats, .marker, .importFile, .library,
        .volumeUp, .volumeDown, .previous, .next, .pause, .play, .trim, .more,
        .share, .export, .rename, .delete, .add, .none
    ]
}
