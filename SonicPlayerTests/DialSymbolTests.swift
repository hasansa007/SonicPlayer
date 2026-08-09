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

    @Test func everyDirectionMarkResolves() {
        for direction in DialRing.directions {
            #expect(
                UIImage(systemName: direction.glyph) != nil,
                "no SF Symbol named \(direction.glyph)"
            )
        }
    }

    @Test func everyIconRoleResolves() {
        for icon in DialScreen.Icon.allDialCases {
            guard let symbol = DialIcon.systemImage(for: icon) else { continue }
            #expect(UIImage(systemName: symbol) != nil, "\(icon) maps to a missing symbol: \(symbol)")
        }
    }
}

private extension DialScreen.Icon {
    /// The contract's `Icon` is not `CaseIterable` — it does not need to be for its own sake, and
    /// adding the conformance to the shared file to serve one test would be the test leaking into
    /// the design. Listed here instead, where forgetting to add a case costs only this test.
    static let allDialCases: [DialScreen.Icon] = [
        .playlist, .recording, .session, .podcast, .stats,
        .marker, .share, .export, .rename, .delete, .add, .none
    ]
}
