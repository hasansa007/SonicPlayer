import Foundation
import Synchronization
import Testing

@testable import SonicPlayer

/// Every requirement of `AudioPlaying` and `FileManaging` forwards to the closure it names (#44).
///
/// Both protocols are thin: each requirement calls exactly one stored closure on the client. The
/// forwards are also **renamed** — a stored `var getMetadata` and a `func getMetadata(…)` cannot
/// coexist on one type — so a requirement and the closure it wraps never share a name, and the
/// compiler cannot catch a forward wired to the wrong member. `pausePlayback()` calling `stop`
/// would compile and ship.
///
/// That matters more here than it usually would, because most of these requirements have no
/// caller yet: `LivePlaybackRepository` uses `metadata(for:)` and nothing else in the app touches
/// either protocol. Until #7 and #9 give them consumers, this file is the only thing holding them
/// to their contract — and the only thing keeping the forwards from being dead code.
///
/// The shape of every case: take a `.test` client, replace exactly **one** closure with a flag,
/// then call through the protocol. `AudioPlayerClient.test` reports on every unstubbed closure, so
/// a forward that reaches the wrong member fails twice over — once as an unimplemented report,
/// once as the flag that never flipped.
@Suite
struct ClientProtocolConformanceTests {

    // MARK: - AudioPlaying

    @Test func test_everyAudioPlayingRequirement_forwardsToTheClosureItNames() async {
        let url = URL(fileURLWithPath: "/Docs/Lecture 3.mp3")

        let cases: [Forward<any AudioPlaying>] = [
            Forward("prepareToPlay", { flag in
                player { $0.prepare = { _ in flag.fire() } }
            }, { try? await $0.prepareToPlay(url) }),

            Forward("startPlayback", { flag in
                player { $0.play = { _ in flag.fire() } }
            }, { try? await $0.startPlayback(of: url) }),

            Forward("pausePlayback", { flag in
                player { $0.pause = { flag.fire() } }
            }, { await $0.pausePlayback() }),

            Forward("resumePlayback", { flag in
                player { $0.resume = { flag.fire() } }
            }, { await $0.resumePlayback() }),

            Forward("stopPlayback", { flag in
                player { $0.stop = { flag.fire() } }
            }, { await $0.stopPlayback() }),

            Forward("seekToTime", { flag in
                player { $0.seek = { _ in flag.fire() } }
            }, { await $0.seekToTime(12) }),

            Forward("changeRate", { flag in
                player { $0.setRate = { _ in flag.fire() } }
            }, { await $0.changeRate(to: 1.5) }),

            Forward("skipAhead", { flag in
                player { $0.skipForward = { _ in flag.fire() } }
            }, { await $0.skipAhead(by: 15) }),

            Forward("skipBack", { flag in
                player { $0.skipBackward = { _ in flag.fire() } }
            }, { await $0.skipBack(by: 15) }),

            Forward("refreshNowPlaying", { flag in
                player { $0.updateNowPlaying = { flag.fire() } }
            }, { await $0.refreshNowPlaying() }),

            Forward("assignRemoteHandlers", { flag in
                player { $0.setRemoteHandlers = { _, _ in flag.fire() } }
            }, { $0.assignRemoteHandlers(nextTrack: {}, previousTrack: {}) }),

            Forward("elapsedTime", { flag in
                player { $0.currentTime = { flag.fire(); return 0 } }
            }, { _ = await $0.elapsedTime() }),

            Forward("trackDuration", { flag in
                player { $0.duration = { flag.fire(); return 0 } }
            }, { _ = await $0.trackDuration() }),

            Forward("playbackIsActive", { flag in
                player { $0.isPlaying = { flag.fire(); return false } }
            }, { _ = await $0.playbackIsActive() }),

            Forward("timeStream", { flag in
                player { $0.timeUpdates = { flag.fire(); return AsyncStream { $0.finish() } } }
            }, { _ = await $0.timeStream() })
        ]

        await check(cases, protocolNamed: "AudioPlaying")
    }

    // MARK: - FileManaging

    @Test func test_everyFileManagingRequirement_forwardsToTheClosureItNames() async {
        let url = URL(fileURLWithPath: "/Docs/Lecture 3.mp3")
        let destination = URL(fileURLWithPath: "/Docs/Archive")

        let cases: [Forward<any FileManaging>] = [
            Forward("items", { flag in
                files { $0.listItems = { _ in flag.fire(); return [] } }
            }, { _ = try? await $0.items(in: nil) }),

            Forward("makeCollection", { flag in
                files { $0.createCollection = { _, _ in flag.fire() } }
            }, { try? await $0.makeCollection(named: "Term 1", in: nil) }),

            Forward("makeCollectionForImport", { flag in
                files { $0.createCollectionForImport = { flag.fire(); return destination } }
            }, { _ = try? await $0.makeCollectionForImport() }),

            Forward("delete", { flag in
                files { $0.deleteItem = { _ in flag.fire() } }
            }, { try? await $0.delete(url) }),

            Forward("move", { flag in
                files { $0.moveItem = { _, _ in flag.fire() } }
            }, { try? await $0.move(url, to: destination) }),

            Forward("rename", { flag in
                files { $0.renameItem = { _, _ in flag.fire() } }
            }, { try? await $0.rename(url, to: "Lecture 4.mp3") }),

            Forward("copyFile", { flag in
                files { $0.importFile = { _, _ in flag.fire() } }
            }, { try? await $0.copyFile(at: url, into: destination) }),

            Forward("metadata", { flag in
                files { $0.getMetadata = { url in flag.fire(); return stubFile(at: url) } }
            }, { _ = try? await $0.metadata(for: url) }),

            Forward("documentsURL", { flag in
                files { $0.documentsDirectory = { flag.fire(); return destination } }
            }, { _ = $0.documentsURL() })
        ]

        await check(cases, protocolNamed: "FileManaging")
    }

    // MARK: - Harness

    /// One case: how to build a client whose single stubbed closure raises `flag`, and how to
    /// reach that closure through the protocol it conforms to.
    private struct Forward<Interface> {
        let member: String
        let client: (Flag) -> Interface
        let call: (Interface) async -> Void

        init(
            _ member: String,
            _ client: @escaping (Flag) -> Interface,
            _ call: @escaping (Interface) async -> Void
        ) {
            self.member = member
            self.client = client
            self.call = call
        }
    }

    private func check<Interface>(_ cases: [Forward<Interface>], protocolNamed name: String) async {
        for forward in cases {
            let flag = Flag()
            await forward.call(forward.client(flag))
            #expect(
                flag.fired,
                "\(name).\(forward.member) must forward to the closure it names, and to no other."
            )
        }
    }
}

/// A reference type so it can be captured by the `@Sendable` client closures and still be read
/// back afterwards. `Mutex` rather than a plain `var` because those closures are `@Sendable`, and
/// a captured `var` written from inside one is a data race under Swift 6.
private final class Flag: Sendable {
    private let state = Mutex(false)

    func fire() { state.withLock { $0 = true } }
    var fired: Bool { state.withLock { $0 } }
}

/// `.test` with one closure replaced. Every *other* closure still reports, which is what makes a
/// mis-wired forward fail loudly rather than quietly raising the wrong flag.
private func player(_ stub: (inout AudioPlayerClient) -> Void) -> AudioPlayerClient {
    var client = AudioPlayerClient.test
    stub(&client)
    return client
}

private func files(_ stub: (inout FileManagerClient) -> Void) -> FileManagerClient {
    var client = FileManagerClient.test
    stub(&client)
    return client
}

private func stubFile(at url: URL) -> AudioFile {
    AudioFile(
        url: url,
        title: url.deletingPathExtension().lastPathComponent,
        duration: 0,
        fileSize: 0,
        format: .mp3,
        creationDate: Date(timeIntervalSince1970: 0)
    )
}
