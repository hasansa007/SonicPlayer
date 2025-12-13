import UIKit
import SwiftUI

struct ColorExtractor {

    /// Extract dominant colors from an image
    static func extractColors(from image: UIImage, count: Int = 3) -> [Color]? {
        guard image.cgImage != nil else {
            return nil
        }

        // Resize image for faster processing
        let size = CGSize(width: 50, height: 50)
        UIGraphicsBeginImageContext(size)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let resized = resizedImage?.cgImage else {
            return nil
        }

        // Extract pixel data
        let width = resized.width
        let height = resized.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(resized, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Sample colors and find dominant ones
        var colorCounts: [UIColor: Int] = [:]

        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let pixelIndex = (y * width + x) * bytesPerPixel
                let r = CGFloat(pixelData[pixelIndex]) / 255.0
                let g = CGFloat(pixelData[pixelIndex + 1]) / 255.0
                let b = CGFloat(pixelData[pixelIndex + 2]) / 255.0

                // Skip very dark or very light colors
                let brightness = (r + g + b) / 3.0
                if brightness < 0.15 || brightness > 0.85 {
                    continue
                }

                // Quantize colors to reduce variations
                let quantizedR = round(r * 4) / 4
                let quantizedG = round(g * 4) / 4
                let quantizedB = round(b * 4) / 4

                let color = UIColor(red: quantizedR, green: quantizedG, blue: quantizedB, alpha: 1.0)
                colorCounts[color, default: 0] += 1
            }
        }

        // Sort by frequency and get top colors
        let sortedColors = colorCounts.sorted { $0.value > $1.value }
        let topColors = sortedColors.prefix(count).map { Color($0.key) }

        if topColors.isEmpty {
            return nil
        }
        
        // If we don't have enough colors, duplicate the last one or blend
        if topColors.count < count {
            var result = Array(topColors)
            while result.count < count {
                // Deterministic fill: blend or duplicate
                let last = result.last ?? .gray
                result.append(last.opacity(0.8)) 
            }
            return result
        }

        return Array(topColors)
    }

    /// Generate random vibrant gradient colors
    static func generateRandomGradientColors(count: Int = 3) -> [Color] {
        let gradients: [[Color]] = [
            [Color(hex: "667eea"), Color(hex: "764ba2")],
            [Color(hex: "f093fb"), Color(hex: "f5576c")],
            [Color(hex: "4facfe"), Color(hex: "00f2fe")],
            [Color(hex: "43e97b"), Color(hex: "38f9d7")],
            [Color(hex: "fa709a"), Color(hex: "fee140")],
            [Color(hex: "30cfd0"), Color(hex: "330867")],
            [Color(hex: "a8edea"), Color(hex: "fed6e3")],
            [Color(hex: "ff9a9e"), Color(hex: "fecfef")],
            [Color(hex: "ffecd2"), Color(hex: "fcb69f")],
            [Color(hex: "ff6e7f"), Color(hex: "bfe9ff")],
            [Color(hex: "e0c3fc"), Color(hex: "8ec5fc")],
            [Color(hex: "f093fb"), Color(hex: "f5576c")]
        ]

        let selectedGradient = gradients.randomElement() ?? gradients[0]

        if count == 2 {
            return selectedGradient
        } else if count == 3 {
            // Create a middle color by blending
            let middle = selectedGradient[0].blend(with: selectedGradient[1], ratio: 0.5)
            return [selectedGradient[0], middle, selectedGradient[1]]
        }

        return selectedGradient
    }
}

// MARK: - Color Extensions

extension Color {
    func blend(with other: Color, ratio: Double) -> Color {
        let ratio = min(max(ratio, 0), 1)

        guard let components1 = UIColor(self).cgColor.components,
              let components2 = UIColor(other).cgColor.components else {
            return self
        }

        let r = components1[0] * (1 - ratio) + components2[0] * ratio
        let g = components1[1] * (1 - ratio) + components2[1] * ratio
        let b = components1[2] * (1 - ratio) + components2[2] * ratio

        return Color(red: r, green: g, blue: b)
    }
}
