//
//  ImageLoader.swift
//  ImageTagger
//

import CoreGraphics
import Foundation
import ImageIO

/// Errors thrown while reading image files.
nonisolated enum ImageLoadingError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            String(localized: "The file isn’t in a supported image format.")
        }
    }
}

/// Reads images with ImageIO, downsampling them so large photos stay cheap to decode.
nonisolated enum ImageLoader {
    /// Creates an image source for the file at `url`.
    static func source(at url: URL) throws -> CGImageSource {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0
        else {
            throw ImageLoadingError.unsupportedFormat
        }
        return source
    }

    /// Returns an upright image whose longest side is at most `maxPixelSize` pixels.
    static func image(from source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageLoadingError.unsupportedFormat
        }
        return image
    }

    /// Loads an upright, downsampled image from the file at `url` off the main actor.
    @concurrent
    static func image(at url: URL, maxPixelSize: Int) async throws -> CGImage {
        try image(from: source(at: url), maxPixelSize: maxPixelSize)
    }
}
