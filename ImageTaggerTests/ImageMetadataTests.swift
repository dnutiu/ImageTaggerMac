//
//  ImageMetadataTests.swift
//  ImageTaggerTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ImageTagger

struct ImageMetadataTests {
    private let locale = Locale(identifier: "en_US")

    @Test func readsTIFFAndExifProperties() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("photo.jpg")
            try writeJPEG(to: url, width: 30, height: 20, properties: [
                kCGImagePropertyOrientation: 1,
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFMake: "FUJIFILM",
                    kCGImagePropertyTIFFModel: "X-T5",
                    kCGImagePropertyTIFFArtist: "Denis-Cosmin Nutiu",
                ],
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifLensModel: "XF23mmF1.4 R LM WR",
                    kCGImagePropertyExifFocalLength: 23.0,
                    kCGImagePropertyExifFNumber: 2.8,
                    kCGImagePropertyExifExposureTime: 1.0 / 250.0,
                    kCGImagePropertyExifISOSpeedRatings: [400],
                    kCGImagePropertyExifDateTimeOriginal: "2024:04:09 15:30:00",
                ],
            ])

            let metadata = ImageMetadata(source: try ImageLoader.source(at: url))

            #expect(metadata.pixelWidth == 30)
            #expect(metadata.pixelHeight == 20)
            #expect(metadata.cameraMake == "FUJIFILM")
            #expect(metadata.cameraModel == "X-T5")
            #expect(metadata.artist == "Denis-Cosmin Nutiu")
            #expect(metadata.lensModel == "XF23mmF1.4 R LM WR")
            #expect(metadata.focalLength == 23)
            #expect(metadata.aperture == 2.8)
            #expect(metadata.exposureTime == 0.004)
            #expect(metadata.iso == 400)
            let date = try #require(metadata.dateTaken)
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            #expect(components == DateComponents(year: 2024, month: 4, day: 9, hour: 15, minute: 30))

            #expect(metadata.cameraEntries(locale: locale).map(\.value) == [
                "FUJIFILM", "X-T5", "XF23mmF1.4 R LM WR", "23 mm", "ƒ/2.8", "1/250 s", "ISO 400",
            ])
            #expect(metadata.informationEntries(locale: locale).first?.value == "30 × 20")
        }
    }

    @Test func rotatedImagesSwapDimensions() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("rotated.jpg")
            try writeJPEG(to: url, width: 30, height: 20, properties: [kCGImagePropertyOrientation: 6])

            let metadata = ImageMetadata(source: try ImageLoader.source(at: url))

            #expect(metadata.pixelWidth == 20)
            #expect(metadata.pixelHeight == 30)
        }
    }

    @Test func missingValuesAreOmitted() {
        let metadata = ImageMetadata(properties: [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "  "],
        ])

        #expect(metadata == ImageMetadata())
        #expect(metadata.cameraEntries().isEmpty)
        #expect(metadata.informationEntries().isEmpty)
    }

    @Test(arguments: [
        (1.0 / 250.0, "1/250 s"),
        (1.0 / 3.0, "1/3 s"),
        (0.5, "1/2 s"),
        (0.4, "0.4 s"),
        (1.0, "1 s"),
        (2.5, "2.5 s"),
        (30.0, "30 s"),
    ])
    func exposureTime(seconds: Double, expected: String) {
        #expect(ImageMetadata.formatExposureTime(seconds, locale: locale) == expected)
    }

    @Test(arguments: [(1.4, "ƒ/1.4"), (8.0, "ƒ/8"), (5.6, "ƒ/5.6")])
    func aperture(fNumber: Double, expected: String) {
        #expect(ImageMetadata.formatAperture(fNumber, locale: locale) == expected)
    }

    @Test func formatsUseTheLocale() {
        #expect(ImageMetadata.formatAperture(2.8, locale: Locale(identifier: "ro_RO")) == "ƒ/2,8")
    }

    private func writeJPEG(to url: URL, width: Int, height: Int, properties: [CFString: Any]) throws {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }
}
