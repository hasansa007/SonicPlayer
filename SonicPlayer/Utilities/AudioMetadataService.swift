import AVFoundation
import SwiftUI

struct AudioMetadataService {

    /// Extract album artwork from an audio file
    static func extractArtwork(from url: URL) async -> UIImage? {
        let asset = AVAsset(url: url)

        // Try to get artwork from metadata
        guard let formats = try? await asset.load(.availableMetadataFormats) else { return nil }
        
        for format in formats {
            guard let metadata = try? await asset.loadMetadata(for: format) else { continue }

            for item in metadata {
                guard let commonKey = item.commonKey else { continue }

                if commonKey == .commonKeyArtwork,
                   let data = try? await item.load(.dataValue),
                   let image = UIImage(data: data) {
                    return image
                }
            }
        }

        return nil
    }

    /// Extract metadata including title, artist, album
    static func extractMetadata(from url: URL) async -> AudioMetadata {
        let asset = AVAsset(url: url)
        var metadata = AudioMetadata()

        guard let formats = try? await asset.load(.availableMetadataFormats) else { return metadata }

        for format in formats {
            guard let items = try? await asset.loadMetadata(for: format) else { continue }

            for item in items {
                guard let commonKey = item.commonKey else { continue }

                switch commonKey {
                case .commonKeyTitle:
                    metadata.title = try? await item.load(.stringValue)
                case .commonKeyArtist:
                    metadata.artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName:
                    metadata.album = try? await item.load(.stringValue)
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue) {
                        metadata.artworkData = data
                    }
                default:
                    break
                }
            }
        }

        return metadata
    }

    /// Get first audio file's artwork from a folder
    static func extractFolderArtwork(from folderURL: URL) async -> UIImage? {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }

        let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac", "opus", "ogg"]

        for case let fileURL as URL in enumerator {
            let fileExtension = fileURL.pathExtension.lowercased()

            if audioExtensions.contains(fileExtension) {
                if let artwork = await extractArtwork(from: fileURL) { // Await the async call
                    return artwork
                }
            }
        }

        return nil
    }
}

struct AudioMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var artworkData: Data?

    var artwork: UIImage? {
        guard let data = artworkData else { return nil }
        return UIImage(data: data)
    }
}
