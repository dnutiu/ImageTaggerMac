//
//  ImageItem.swift
//  ImageTagger
//

import CoreGraphics
import Foundation
import Observation

/// An image added to the tagging session.
@Observable
final class ImageItem: Identifiable {
    enum Status: Equatable {
        /// Waiting to be analyzed.
        case pending
        case analyzing
        case tagged(ImageAnalysis)
        /// The analysis failed, with a user-facing description of the error.
        case failed(String)
    }

    /// The pixel size of the thumbnails shown in the sidebar.
    static let thumbnailPixelSize = 160

    let id = UUID()
    let url: URL
    /// Whether tags can be saved to the image's format.
    let canSaveTags: Bool
    var status: Status = .pending
    var isSavingTags = false
    private(set) var thumbnail: CGImage?

    init(url: URL) {
        self.url = url
        canSaveTags = ImageKeywords.canWrite(to: url)
    }

    var fileName: String { url.lastPathComponent }

    /// The XMP sidecar file that stores the keywords of RAW images, or `nil` if they're stored in the image file.
    var sidecarURL: URL? {
        XMPSidecar.isUsed(forImageAt: url) ? XMPSidecar.url(forImageAt: url) : nil
    }

    var analysis: ImageAnalysis? {
        if case .tagged(let analysis) = status { analysis } else { nil }
    }

    var tags: [String] { analysis?.tags ?? [] }

    /// Whether all the tags are in the file's keywords.
    var areTagsSaved: Bool {
        guard let analysis, !analysis.tags.isEmpty else { return false }
        let keywords = Set(analysis.metadata.keywords.map { $0.lowercased() })
        return analysis.tags.allSatisfy { keywords.contains($0.lowercased()) }
    }

    /// Whether the tags can be saved and some of them aren't saved yet.
    var hasUnsavedTags: Bool {
        canSaveTags && !tags.isEmpty && !areTagsSaved
    }

    var isInProgress: Bool {
        switch status {
        case .pending, .analyzing: true
        case .tagged, .failed: false
        }
    }

    /// Loads the sidebar thumbnail, unless it's already loaded.
    func loadThumbnail() async {
        guard thumbnail == nil else { return }
        thumbnail = try? await ImageLoader.image(at: url, maxPixelSize: Self.thumbnailPixelSize)
    }
}
