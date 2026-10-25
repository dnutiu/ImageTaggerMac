//
//  ImageMetadata.swift
//  ImageTagger
//

import Foundation
import ImageIO

/// Common photo metadata read from an image's TIFF and Exif properties.
nonisolated struct ImageMetadata: Equatable, Sendable {
    var pixelWidth: Int?
    var pixelHeight: Int?
    var dateTaken: Date?
    var artist: String?
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    /// Focal length in millimeters.
    var focalLength: Double?
    /// The f-number.
    var aperture: Double?
    /// Exposure time in seconds.
    var exposureTime: Double?
    var iso: Int?
    /// The keywords stored in the file, for example by Lightroom or by saving tags.
    var keywords: [String] = []

    init() {}

    init(source: CGImageSource) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        self.init(properties: properties ?? [:])
        keywords = ImageKeywords.keywords(in: source)
    }

    init(properties: [CFString: Any]) {
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]

        pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int
        pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        // Orientations 5 to 8 rotate the image by 90 degrees.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&pixelWidth, &pixelHeight)
        }
        dateTaken = (exif[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(Self.date(fromExif:))
        artist = Self.text(tiff[kCGImagePropertyTIFFArtist])
        cameraMake = Self.text(tiff[kCGImagePropertyTIFFMake])
        cameraModel = Self.text(tiff[kCGImagePropertyTIFFModel])
        lensModel = Self.text(exif[kCGImagePropertyExifLensModel])
        focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
        aperture = exif[kCGImagePropertyExifFNumber] as? Double
        exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double
        iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
    }

    private static func text(_ value: Any?) -> String? {
        let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return text?.isEmpty == false ? text : nil
    }

    /// Parses an Exif date such as `2024:04:09 15:30:00`, which is in the camera's local time.
    private static func date(fromExif value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }
}

// MARK: - Display

extension ImageMetadata {
    /// A labeled metadata value ready for display.
    nonisolated struct Entry: Identifiable, Equatable, Sendable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// General information about the image file.
    func informationEntries(locale: Locale = .current) -> [Entry] {
        var entries: [Entry] = []
        if let pixelWidth, let pixelHeight {
            entries.append(Entry(label: String(localized: "Dimensions"), value: "\(pixelWidth) × \(pixelHeight)"))
        }
        if let dateTaken {
            let style = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
            entries.append(Entry(label: String(localized: "Date Taken"), value: dateTaken.formatted(style)))
        }
        if let artist {
            entries.append(Entry(label: String(localized: "Author"), value: artist))
        }
        return entries
    }

    /// Information about the camera and exposure.
    func cameraEntries(locale: Locale = .current) -> [Entry] {
        var entries: [Entry] = []
        if let cameraMake {
            entries.append(Entry(label: String(localized: "Make"), value: cameraMake))
        }
        if let cameraModel {
            entries.append(Entry(label: String(localized: "Model"), value: cameraModel))
        }
        if let lensModel {
            entries.append(Entry(label: String(localized: "Lens"), value: lensModel))
        }
        if let focalLength {
            entries.append(Entry(label: String(localized: "Focal Length"), value: Self.formatFocalLength(focalLength, locale: locale)))
        }
        if let aperture {
            entries.append(Entry(label: String(localized: "Aperture"), value: Self.formatAperture(aperture, locale: locale)))
        }
        if let exposureTime {
            entries.append(Entry(label: String(localized: "Shutter Speed"), value: Self.formatExposureTime(exposureTime, locale: locale)))
        }
        if let iso {
            entries.append(Entry(label: String(localized: "ISO"), value: "ISO \(iso)"))
        }
        return entries
    }

    /// Formats an f-number, for example `ƒ/2.8`.
    static func formatAperture(_ fNumber: Double, locale: Locale = .current) -> String {
        "ƒ/" + fNumber.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    /// Formats an exposure time, for example `1/250 s` or `2 s`.
    static func formatExposureTime(_ seconds: Double, locale: Locale = .current) -> String {
        if seconds > 0, seconds < 1 {
            let reciprocal = 1 / seconds
            if abs(reciprocal - reciprocal.rounded()) < 0.05 {
                return "1/\(Int(reciprocal.rounded())) s"
            }
            return seconds.formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + " s"
        }
        return seconds.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + " s"
    }

    /// Formats a focal length, for example `35 mm`.
    static func formatFocalLength(_ millimeters: Double, locale: Locale = .current) -> String {
        millimeters.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + " mm"
    }
}
