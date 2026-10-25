//
//  ImageAnalyzer.swift
//  ImageTagger
//

import Foundation

/// The result of analyzing an image.
nonisolated struct ImageAnalysis: Equatable, Sendable {
    var tags: [String]
    var metadata: ImageMetadata
}

/// Reads an image file, predicts its tags and extracts its metadata.
nonisolated enum ImageAnalyzer {
    /// The size the image is downsampled to before it's center-cropped and scaled for the model.
    static let analysisPixelSize = 1024

    @concurrent
    static func analyze(_ url: URL, using predictor: TagPredictor) async throws -> ImageAnalysis {
        let source = try ImageLoader.source(at: url)
        let image = try ImageLoader.image(from: source, maxPixelSize: analysisPixelSize)
        let tags = try await predictor.tags(for: image)
        var metadata = ImageMetadata(source: source)
        // The keywords of RAW images are saved in a sidecar file, which takes precedence once it exists.
        if let sidecarKeywords = try? XMPSidecar.keywords(forImageAt: url) {
            metadata.keywords = sidecarKeywords
        }
        return ImageAnalysis(tags: tags, metadata: metadata)
    }
}
