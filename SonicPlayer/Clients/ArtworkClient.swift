import ComposableArchitecture
import Foundation
import SwiftUI
import UIKit

@DependencyClient
struct ArtworkClient {
    var getArtwork: @Sendable (URL) async -> UIImage? = { _ in nil }
    var getFolderArtwork: @Sendable (URL) async -> UIImage? = { _ in nil }
    var getColors: @Sendable (URL, Bool, [Color]?) async -> [Color] = { _, _, fallback in fallback ?? [] }
    var clearCache: @Sendable () async -> Void = {}
    var getCacheStats: @Sendable () async -> (imageCount: Int, colorCount: Int) = { (0, 0) }
}

extension DependencyValues {
    var artworkClient: ArtworkClient {
        get { self[ArtworkClient.self] }
        set { self[ArtworkClient.self] = newValue }
    }
}

extension ArtworkClient: DependencyKey {
    static let liveValue: ArtworkClient = {
        // Single shared actor instance for the entire app
        let cache = ArtworkCacheActor()

        return Self(
            getArtwork: { url in
                await cache.loadArtwork(for: url)
            },
            getFolderArtwork: { url in
                await cache.loadFolderArtwork(for: url)
            },
            getColors: { url, isFolder, fallbackColors in
                await cache.loadColors(for: url, isFolder: isFolder, fallbackColors: fallbackColors)
            },
            clearCache: {
                await cache.clearCache()
            },
            getCacheStats: {
                await cache.getCacheStats()
            }
        )
    }()

    static let testValue = Self(
        getArtwork: { _ in nil },
        getFolderArtwork: { _ in nil },
        getColors: { _, _, fallbackColors in fallbackColors ?? Color.sonicTealColors },
        clearCache: {},
        getCacheStats: { (0, 0) }
    )
}
