import SwiftUI
import UIKit

// MARK: - Thread-Safe Actor-Based Cache

actor ArtworkCacheActor {
    private var imageCache: [URL: UIImage] = [:]
    private var colorCache: [URL: [Color]] = [:]
    private var loadingURLs: Set<URL> = []

    /// Load artwork asynchronously with caching
    func loadArtwork(for url: URL) async -> UIImage? {
        // Return from cache if available
        if let cached = imageCache[url] {
            return cached
        }

        // Prevent duplicate loading
        if loadingURLs.contains(url) {
            // Wait a bit and check cache again
            try? await Task.sleep(for: .milliseconds(100))
            return imageCache[url]
        }

        loadingURLs.insert(url)

        // Extract artwork (this is a synchronous operation)
        let artwork = await AudioMetadataService.extractArtwork(from: url)

        if let artwork = artwork {
            imageCache[url] = artwork
        }
        loadingURLs.remove(url)

        return artwork
    }

    /// Load folder artwork asynchronously with caching
    func loadFolderArtwork(for url: URL) async -> UIImage? {
        // Return from cache if available
        if let cached = imageCache[url] {
            return cached
        }

        // Prevent duplicate loading
        if loadingURLs.contains(url) {
            try? await Task.sleep(for: .milliseconds(100))
            return imageCache[url]
        }

        loadingURLs.insert(url)

        // Extract folder artwork
        let artwork = await AudioMetadataService.extractFolderArtwork(from: url)

        if let artwork = artwork {
            imageCache[url] = artwork
        }
        loadingURLs.remove(url)

        return artwork
    }

    /// Load colors asynchronously with caching
    func loadColors(for url: URL, isFolder: Bool = false, fallbackColors: [Color]? = nil) async -> [Color] {
        // Check cache first
        if let cached = colorCache[url] {
            return cached
        }

        // Try to get artwork
        let artwork = isFolder ? await loadFolderArtwork(for: url) : await loadArtwork(for: url)

        let colors: [Color]
        if let artwork = artwork, let extracted = ColorExtractor.extractColors(from: artwork, count: 3) {
            colors = extracted
        } else {
            colors = fallbackColors ?? ColorExtractor.generateRandomGradientColors(count: 3)
        }

        colorCache[url] = colors
        return colors
    }

    /// Clear all cached data
    func clearCache() async {
        imageCache.removeAll()
        colorCache.removeAll()
        loadingURLs.removeAll()
    }

    /// Get cache statistics (for debugging)
    func getCacheStats() async -> (imageCount: Int, colorCount: Int) {
        (imageCache.count, colorCache.count)
    }
}


