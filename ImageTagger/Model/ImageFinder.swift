//
//  ImageFinder.swift
//  ImageTagger
//

import Foundation
import UniformTypeIdentifiers

/// Finds the image files in the files and folders the user chose.
nonisolated enum ImageFinder {
    /// Returns the image files in `urls`, searching folders and their subfolders.
    @concurrent
    static func imageFiles(in urls: [URL]) async -> [URL] {
        urls.flatMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true, values?.isPackage != true {
                return imageFiles(inFolder: url)
            }
            return isImage(url) ? [url] : []
        }
    }

    static func isImage(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey])
        return values?.contentType?.conforms(to: .image) ?? false
    }

    private static func imageFiles(inFolder folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.contentTypeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return enumerator
            .compactMap { $0 as? URL }
            .filter(isImage)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
