//
//  XMPSidecar.swift
//  ImageTagger
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads and writes the keywords of RAW images, which are stored in an XMP sidecar file next to the image.
///
/// The sidecar has the image's name with the `xmp` extension, for example `IMG_1234.CR2` and `IMG_1234.xmp`, the
/// convention used by Lightroom, Bridge, Capture One and Photo Mechanic. Only the keywords and the metadata date of an
/// existing sidecar are changed, so other metadata and the develop settings of photo editors are kept.
nonisolated enum XMPSidecar {
    /// Returns whether keywords of the image at `url` are stored in a sidecar file.
    static func isUsed(forImageAt url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) ?? false
    }

    static func url(forImageAt url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("xmp")
    }

    /// Returns the keywords in the image's sidecar, or `nil` if the image doesn't have a sidecar.
    static func keywords(forImageAt url: URL) throws -> [String]? {
        guard isUsed(forImageAt: url) else { return nil }
        let sidecarURL = Self.url(forImageAt: url)
        return try RelatedFileCoordinator.read(sidecarURL, relatedTo: url) { sidecarURL -> [String]? in
            guard let data = try contents(of: sidecarURL) else { return nil }
            return ImageKeywords.keywords(in: try metadata(from: data, of: sidecarURL))
        }
    }

    /// Adds `tags` to the keywords in the image's sidecar, creating the sidecar if needed.
    ///
    /// A new sidecar starts with the keywords embedded in the image, so they aren't hidden by the sidecar.
    ///
    /// - Returns: The keywords in the sidecar after saving.
    static func add(_ tags: [String], toImageAt url: URL, embeddedKeywords: [String]) throws -> [String] {
        let sidecarURL = Self.url(forImageAt: url)
        return try RelatedFileCoordinator.write(sidecarURL, relatedTo: url) { sidecarURL in
            let original = try contents(of: sidecarURL)
            let metadata: CGMutableImageMetadata
            let existingKeywords: [String]
            if let original {
                let parsed = try Self.metadata(from: original, of: sidecarURL)
                guard let copy = CGImageMetadataCreateMutableCopy(parsed) else {
                    throw KeywordWritingError.notSaved
                }
                metadata = copy
                existingKeywords = ImageKeywords.keywords(in: parsed)
            } else {
                metadata = CGImageMetadataCreateMutable()
                existingKeywords = []
            }

            let keywords = ImageKeywords.merging(tags, into: original == nil ? embeddedKeywords : existingKeywords)
            guard keywords != existingKeywords else { return keywords }

            try ImageKeywords.setKeywords(keywords, in: metadata)
            let metadataDate = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: .current).format(.now)
            CGImageMetadataSetValueWithPath(metadata, nil, "xmp:MetadataDate" as CFString, metadataDate as CFString)
            guard let data = CGImageMetadataCreateXMPData(metadata, nil) as Data?,
                  let written = CGImageMetadataCreateFromXMPData(data as CFData),
                  ImageKeywords.keywords(in: written) == keywords
            else {
                throw KeywordWritingError.notSaved
            }

            try ImageKeywords.write(data, to: sidecarURL, replacing: original)
            return keywords
        }
    }

    /// Returns the sidecar's contents, or `nil` if it doesn't exist.
    ///
    /// Other errors are thrown, so a sidecar that can't be read is never mistaken for a missing one and replaced.
    private static func contents(of sidecarURL: URL) throws -> Data? {
        do {
            return try Data(contentsOf: sidecarURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    private static func metadata(from data: Data, of sidecarURL: URL) throws -> CGImageMetadata {
        guard let metadata = CGImageMetadataCreateFromXMPData(data as CFData) else {
            throw KeywordWritingError.invalidSidecar(sidecarURL.lastPathComponent)
        }
        return metadata
    }
}

/// Coordinates access to a file related to a file the user opened, such as a sidecar.
///
/// When the user opens a single image, the sandbox only allows access to that image. Files with the same name and a
/// different extension can be accessed through a file presenter, if the app declares their type as a related item
/// type in its Info.plist.
nonisolated private enum RelatedFileCoordinator {
    private final class Presenter: NSObject, NSFilePresenter {
        let primaryPresentedItemURL: URL?
        let presentedItemURL: URL?
        let presentedItemOperationQueue = OperationQueue()

        init(url: URL, relatedTo primaryURL: URL) {
            presentedItemURL = url
            primaryPresentedItemURL = primaryURL
        }
    }

    static func read<Result>(_ url: URL, relatedTo primaryURL: URL, _ body: (URL) throws -> Result) throws -> Result {
        try coordinate(url, relatedTo: primaryURL, writing: false, body)
    }

    static func write<Result>(_ url: URL, relatedTo primaryURL: URL, _ body: (URL) throws -> Result) throws -> Result {
        try coordinate(url, relatedTo: primaryURL, writing: true, body)
    }

    private static func coordinate<Result>(
        _ url: URL,
        relatedTo primaryURL: URL,
        writing: Bool,
        _ body: (URL) throws -> Result
    ) throws -> Result {
        let presenter = Presenter(url: url, relatedTo: primaryURL)
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        let coordinator = NSFileCoordinator(filePresenter: presenter)
        var coordinationError: NSError?
        var result: Swift.Result<Result, any Error>?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
                result = Swift.Result { try body(url) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
                result = Swift.Result { try body(url) }
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw CocoaError(.fileReadUnknown)
        }
        return try result.get()
    }
}
