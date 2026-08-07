import Foundation

/// The filesystem seam, as a protocol (#44).
///
/// `FileManagerClient` **conforms** rather than being replaced. That is the whole reason the
/// existing suite did not have to change: `.live` and `.test` are still `FileManagerClient`
/// values, so the sixteen `client.closure = { … }` lines across the test target keep working,
/// and `.test` keeps reporting an issue for any closure a path reaches without stubbing —
/// behaviour a hand-written mock class would have had to reimplement member by member.
///
/// **The method names deliberately differ from the client's stored properties.** A stored
/// `var getMetadata` and a `func getMetadata(…)` cannot coexist on one type, so the protocol
/// reads as an interface (`metadata(for:)`) and the conformance below forwards to the closure.
protocol FileManaging: Sendable {
    func items(in directory: URL?) async throws -> [FileSystemItem]
    func makeCollection(named name: String, in parent: URL?) async throws
    func makeCollectionForImport() async throws -> URL
    func delete(_ url: URL) async throws
    func move(_ url: URL, to destination: URL) async throws
    func rename(_ url: URL, to name: String) async throws
    func copyFile(at source: URL, into destination: URL?) async throws
    func metadata(for url: URL) async throws -> AudioFile
    func documentsURL() -> URL
}

extension FileManagerClient: FileManaging {
    func items(in directory: URL?) async throws -> [FileSystemItem] { try await listItems(directory) }
    func makeCollection(named name: String, in parent: URL?) async throws { try await createCollection(name, parent) }
    func makeCollectionForImport() async throws -> URL { try await createCollectionForImport() }
    func delete(_ url: URL) async throws { try await deleteItem(url) }
    func move(_ url: URL, to destination: URL) async throws { try await moveItem(url, destination) }
    func rename(_ url: URL, to name: String) async throws { try await renameItem(url, name) }
    func copyFile(at source: URL, into destination: URL?) async throws { try await importFile(source, destination) }
    func metadata(for url: URL) async throws -> AudioFile { try await getMetadata(url) }
    func documentsURL() -> URL { documentsDirectory() }
}
