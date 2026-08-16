import Foundation
import Testing

@testable import SonicPlayer

/// **The price of duplicating the queue contract across two targets, paid here.**
///
/// `SonicPlayerShare` cannot see the app's sources — a synchronized file group excludes files, it
/// does not share them — so `ShareInboxLayout` restates what `ShareInbox` declares. That is a
/// deliberate choice over hand-maintained multi-target membership in `project.pbxproj`, and it is
/// only defensible because this suite makes drift impossible to ship.
///
/// **What a silent disagreement costs:** the extension writes into a container the app never reads,
/// and every shared file vanishes. No crash, no error, no log — the share sheet says it worked and
/// the library stays empty. Nothing else in the system would catch it, because both halves are
/// individually correct.
///
/// These read source and plists as **text**, which is unusual and is the point: the extension's
/// symbols are not linkable from here, so the only thing both targets demonstrably agree on is the
/// bytes on disk.
@Suite("The two targets agree about the share queue")
struct ShareInboxLayoutAgreementTests {

    /// The repo root, derived from this file's own location at compile time.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SonicPlayerTests/
        .deletingLastPathComponent()   // repo root

    private static func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot.appending(path: relativePath), encoding: .utf8)
    }

    private static func literal(_ constant: String, in source: String) -> String? {
        let pattern = #"static let \#(constant)\s*=\s*"([^"]*)""#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: source, range: NSRange(source.startIndex..., in: source)
            ),
            let range = Range(match.range(at: 1), in: source)
        else { return nil }
        return String(source[range])
    }

    // MARK: - The constants

    @Test func theExtensionRestatesEveryQueueConstantExactly() throws {
        let extensionSource = try Self.source("SonicPlayerShare/ShareInboxLayout.swift")

        let expected: [(name: String, appValue: String)] = [
            ("appGroupIdentifier", ShareInbox.appGroupIdentifier),
            ("inboxDirectoryName", ShareInbox.inboxDirectoryName),
            ("manifestFileName", ShareInbox.manifestFileName),
            ("partialPrefix", ShareInbox.partialPrefix),
        ]

        for (name, appValue) in expected {
            let extensionValue = Self.literal(name, in: extensionSource)
            #expect(
                extensionValue != nil,
                "ShareInboxLayout has no `static let \(name)`. The app declares it as \(appValue)."
            )
            #expect(
                extensionValue == appValue,
                "\(name) disagrees — app: \(appValue), extension: \(extensionValue ?? "nil"). Make both match; do not relax this test."
            )
        }
    }

    /// The batch name is built by both sides and must be parsed by one of them.
    @Test func bothSidesBuildTheSameBatchName() throws {
        let extensionSource = try Self.source("SonicPlayerShare/ShareInboxLayout.swift")
        let prefix = Self.literal("partialPrefix", in: extensionSource)

        #expect(prefix == ShareInbox.partialPrefix)
        #expect(
            extensionSource.contains(#""\(partialPrefix)partial-\(id)""#),
            "The extension must build the batch name the same way ShareInbox.partialBatchName does; the app's drain refuses anything dot-prefixed and accepts everything else."
        )
    }

    // MARK: - The entitlements

    /// Belt and braces on the constant above: the identifier can be right in both sources and still
    /// be absent from an entitlements file, in which case the container simply does not exist.
    @Test func bothEntitlementsNameTheSameAppGroup() throws {
        for path in [
            "SonicPlayer/SonicPlayer.entitlements",
            "SonicPlayerShare/SonicPlayerShare.entitlements",
        ] {
            let data = try Data(contentsOf: Self.repoRoot.appending(path: path))
            let plist = try PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any]
            let groups = plist?["com.apple.security.application-groups"] as? [String]

            #expect(
                groups?.contains(ShareInbox.appGroupIdentifier) == true,
                "\(path) does not declare \(ShareInbox.appGroupIdentifier). Without it on BOTH targets the extension writes where the app cannot read."
            )
        }
    }

    // MARK: - The accepted formats

    /// The extension filters at copy time using its own list, because the activation rule fires on
    /// *any* audio attachment and a mixed share hands over everything. A list narrower than the
    /// library's silently drops formats the app would have accepted.
    @Test func theExtensionAcceptsExactlyWhatTheLibraryDoes() throws {
        let extensionSource = try Self.source("SonicPlayerShare/ShareInboxLayout.swift")

        guard
            let start = extensionSource.range(of: "audioExtensions: Set<String> = ["),
            let end = extensionSource.range(of: "]", range: start.upperBound..<extensionSource.endIndex)
        else {
            Issue.record("Could not find ShareInboxLayout.audioExtensions to compare.")
            return
        }

        let body = extensionSource[start.upperBound..<end.lowerBound]
        let found = Set(
            body.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\""))) }
                .filter { !$0.isEmpty }
        )

        #expect(
            found == ImportFilter.audioExtensions,
            "The extension's accepted formats differ from ImportFilter's. Only in the extension: \(found.subtracting(ImportFilter.audioExtensions)). Only in the library: \(ImportFilter.audioExtensions.subtracting(found))."
        )
    }
}
