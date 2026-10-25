//
//  ImageKeywordsTests.swift
//  ImageTaggerTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ImageTagger

struct ImageKeywordsTests {
    @Test func mergingKeepsExistingKeywordsAndIgnoresCase() {
        let merged = ImageKeywords.merging(["Tree", "night", "day"], into: ["tree", "Holiday"])
        #expect(merged == ["tree", "Holiday", "night", "day"])
    }

    @Test func savesKeywordsToJPEGWithoutReencodingIt() async throws {
        try await withTemporaryDirectory { directory in
            let url = try copy(.timisoaraTrees, to: directory)
            let original = try Data(contentsOf: url)

            let metadata = try await ImageKeywords.add(["day", "no people", "tree"], toImageAt: url)

            #expect(metadata.keywords == ["day", "no people", "tree"])
            #expect(try keywords(at: url) == ["day", "no people", "tree"])
            #expect(try compressedImageData(of: Data(contentsOf: url)) == compressedImageData(of: original))
        }
    }

    @Test func addsToExistingKeywords() async throws {
        try await withTemporaryDirectory { directory in
            let url = try copy(.timisoaraTrees, to: directory)

            _ = try await ImageKeywords.add(["Holiday", "tree"], toImageAt: url)
            let metadata = try await ImageKeywords.add(["day", "TREE"], toImageAt: url)

            #expect(metadata.keywords == ["Holiday", "tree", "day"])
            #expect(try keywords(at: url) == ["Holiday", "tree", "day"])
        }
    }

    @Test func updatesLegacyIPTCKeywords() async throws {
        try await withTemporaryDirectory { directory in
            // ImageIO writes an IPTC IIM block when it creates an image with IPTC properties.
            let url = directory.appendingPathComponent("legacy.jpg")
            let source = try ImageLoader.source(at: TestImage.timisoaraTrees.url)
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
            let properties: [CFString: Any] = [kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["legacy"]]]
            CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
            #expect(try iptcBlock(of: Data(contentsOf: url)).contains("legacy".utf8))

            _ = try await ImageKeywords.add(["night"], toImageAt: url)

            let iptc = try iptcBlock(of: Data(contentsOf: url))
            #expect(iptc.contains("legacy".utf8))
            #expect(iptc.contains("night".utf8))
            #expect(try keywords(at: url) == ["legacy", "night"])
        }
    }

    @Test(arguments: [UTType.heic, .tiff])
    func savesKeywordsToOtherFormats(type: UTType) async throws {
        try await withTemporaryDirectory { directory in
            let url = try convert(.timisoaraTrees, to: type, in: directory)
            #expect(ImageKeywords.canWrite(to: url))

            _ = try await ImageKeywords.add(["day", "tree"], toImageAt: url)

            #expect(try keywords(at: url) == ["day", "tree"])
        }
    }

    @Test func refusesUnsupportedFormats() async throws {
        try await withTemporaryDirectory { directory in
            let url = try convert(.timisoaraTrees, to: .png, in: directory)
            let original = try Data(contentsOf: url)
            #expect(!ImageKeywords.canWrite(to: url))

            await #expect(throws: KeywordWritingError.unsupportedFormat) {
                try await ImageKeywords.add(["tree"], toImageAt: url)
            }
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func writingInPlaceKeepsTheFile() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("file.bin")
            let original = Data(repeating: 1, count: 1000)
            try original.write(to: url)
            let fileNumber = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int

            try ImageKeywords.write(Data([1, 2, 3]), inPlaceOf: url, original: original)

            #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
            #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int == fileNumber)
        }
    }

    // MARK: - Helpers

    private func keywords(at url: URL) throws -> [String] {
        ImageKeywords.keywords(in: try ImageLoader.source(at: url))
    }

    private func convert(_ image: TestImage, to type: UTType, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(image.rawValue).appendingPathExtension(for: type)
        let source = try ImageLoader.source(at: image.url)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try ImageLoader.image(from: source, maxPixelSize: 800), nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// Returns the compressed image data of a JPEG, from its start of scan marker.
    private func compressedImageData(of jpeg: Data) throws -> Data {
        let startOfScan = try #require(jpeg.firstRange(of: Data([0xFF, 0xDA])))
        return jpeg[startOfScan.lowerBound...]
    }

    /// Returns the APP13 segment of a JPEG, which holds the IPTC IIM metadata.
    private func iptcBlock(of jpeg: Data) throws -> Data {
        let bytes = [UInt8](jpeg)
        var offset = 2
        while offset + 4 <= bytes.count, bytes[offset] == 0xFF, bytes[offset + 1] != 0xDA {
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            if bytes[offset + 1] == 0xED {
                return Data(bytes[offset + 4 ..< offset + 2 + length])
            }
            offset += 2 + length
        }
        Issue.record("The JPEG has no APP13 segment")
        return Data()
    }
}

/// Copies a test image to `directory`, so tests never modify the bundled images.
func copy(_ image: TestImage, to directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(image.url.lastPathComponent)
    try FileManager.default.copyItem(at: image.url, to: url)
    return url
}
