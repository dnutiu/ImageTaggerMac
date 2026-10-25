//
//  ImageKeywords.swift
//  ImageTagger
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Errors thrown while saving keywords to an image file.
nonisolated enum KeywordWritingError: LocalizedError, Equatable {
    case unsupportedFormat
    case notSaved
    /// The XMP sidecar with the given file name can't be parsed, so it isn't changed.
    case invalidSidecar(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            String(localized: "Tags can only be saved to JPEG, HEIC, TIFF and RAW images.")
        case .notSaved:
            String(localized: "The tags couldn’t be written to the image’s metadata.")
        case .invalidSidecar(let fileName):
            String(localized: "The XMP sidecar file “\(fileName)” couldn’t be read, so it wasn’t changed.")
        }
    }
}

/// Reads and writes an image's keywords, the metadata field photo apps use for tags.
///
/// Keywords are written to XMP `dc:subject`, which Lightroom, Capture One, Photo Mechanic, Spotlight and Windows
/// read. When a file also has legacy IPTC IIM keywords, ImageIO updates them too, so both stay in sync.
/// The image data is copied as is, without being decoded and compressed again.
///
/// RAW images can't be changed, so their keywords are saved to an ``XMPSidecar`` file.
nonisolated enum ImageKeywords {
    /// The formats whose metadata ImageIO can rewrite without re-encoding the image.
    static let writableTypes: Set<UTType> = [.jpeg, .heic, .tiff]

    /// Returns whether keywords can be saved for the image at `url`, based on its file extension.
    static func canWrite(to url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return writableTypes.contains(type) || XMPSidecar.isUsed(forImageAt: url)
    }

    /// Returns the keywords stored in the image's IPTC and XMP metadata.
    static func keywords(in source: CGImageSource) -> [String] {
        var keywords: [String] = []
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let iptc = properties?[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        switch iptc?[kCGImagePropertyIPTCKeywords] {
        case let values as [String]: keywords += values
        case let value as String: keywords.append(value)
        default: break
        }
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            keywords += Self.keywords(in: metadata)
        }
        return merging(keywords, into: [])
    }

    /// Returns the keywords stored in XMP `dc:subject`.
    static func keywords(in metadata: CGImageMetadata) -> [String] {
        guard let subject = CGImageMetadataCopyTagWithPath(metadata, nil, "dc:subject" as CFString) else {
            return []
        }
        let keywords: [String] = switch CGImageMetadataTagCopyValue(subject) {
        case let tags as [CGImageMetadataTag]: tags.compactMap { CGImageMetadataTagCopyValue($0) as? String }
        case let values as [String]: values
        case let value as String: [value]
        default: []
        }
        return merging(keywords, into: [])
    }

    /// Replaces the keywords stored in XMP `dc:subject`.
    static func setKeywords(_ keywords: [String], in metadata: CGMutableImageMetadata) throws {
        guard let subject = CGImageMetadataTagCreate(
            "http://purl.org/dc/elements/1.1/" as CFString, "dc" as CFString, "subject" as CFString,
            .arrayUnordered, keywords as CFArray
        ), CGImageMetadataSetTagWithPath(metadata, nil, "dc:subject" as CFString, subject) else {
            throw KeywordWritingError.notSaved
        }
    }

    /// Appends the `tags` that aren't in `keywords` yet, ignoring case.
    static func merging(_ tags: [String], into keywords: [String]) -> [String] {
        var seen = Set(keywords.map { $0.lowercased() })
        return keywords + tags.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Adds `tags` to the keywords of the image at `url`, keeping the keywords it already has.
    ///
    /// RAW images get the keywords in their XMP sidecar file. Other images get them in the file.
    ///
    /// - Returns: The image's metadata after saving.
    @concurrent
    static func add(_ tags: [String], toImageAt url: URL) async throws -> ImageMetadata {
        if XMPSidecar.isUsed(forImageAt: url) {
            var metadata = ImageMetadata(source: try ImageLoader.source(at: url))
            metadata.keywords = try XMPSidecar.add(tags, toImageAt: url, embeddedKeywords: metadata.keywords)
            return metadata
        }

        let original = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              let type = CGImageSourceGetType(source).flatMap({ UTType($0 as String) }),
              writableTypes.contains(type)
        else {
            throw KeywordWritingError.unsupportedFormat
        }

        let existingKeywords = keywords(in: source)
        let newKeywords = merging(tags, into: existingKeywords)
        guard newKeywords != existingKeywords else {
            return ImageMetadata(source: source)
        }

        let updated = try data(from: source, type: type, replacingKeywordsWith: newKeywords)
        // Make sure the keywords were written before replacing the original file.
        guard let updatedSource = CGImageSourceCreateWithData(updated as CFData, nil),
              Set(keywords(in: updatedSource).map { $0.lowercased() }) == Set(newKeywords.map { $0.lowercased() })
        else {
            throw KeywordWritingError.notSaved
        }

        try write(updated, to: url, replacing: original)
        return ImageMetadata(source: updatedSource)
    }

    private static func data(from source: CGImageSource, type: UTType, replacingKeywordsWith keywords: [String]) throws -> Data {
        let metadata = CGImageMetadataCreateMutable()
        try setKeywords(keywords, in: metadata)

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, type.identifier as CFString, CGImageSourceGetCount(source), nil
        ) else {
            throw KeywordWritingError.unsupportedFormat
        }
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: true,
        ]
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? KeywordWritingError.notSaved
        }
        return output as Data
    }

    /// Writes `data` to the file at `url`, replacing the `original` contents and preserving the file's attributes.
    ///
    /// - Parameter original: The file's current contents, or `nil` to create a new file.
    static func write(_ data: Data, to url: URL, replacing original: Data?) throws {
        guard let original else {
            try data.write(to: url, options: .withoutOverwriting)
            return
        }
        do {
            // An atomic replacement needs access to the file's folder, granted when the user adds a folder.
            let directory = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            let replacement = directory.appendingPathComponent(url.lastPathComponent)
            try data.write(to: replacement)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: replacement)
        } catch {
            // Access to a single file only allows writing it in place.
            try write(data, inPlaceOf: url, original: original)
        }
    }

    /// Overwrites the file's contents, restoring the original contents if writing fails.
    static func write(_ data: Data, inPlaceOf url: URL, original: Data) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        do {
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            try? handle.truncate(atOffset: 0)
            try? handle.write(contentsOf: original)
            try? handle.synchronize()
            throw error
        }
    }
}
