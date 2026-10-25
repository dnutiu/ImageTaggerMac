//
//  XMPSidecarTests.swift
//  ImageTaggerTests
//

import Foundation
import ImageIO
import Testing
@testable import ImageTagger

struct XMPSidecarTests {
    @Test(arguments: ["photo.dng", "photo.CR2", "photo.nef", "photo.arw"])
    func rawImagesUseSidecars(fileName: String) {
        let url = URL(filePath: "/Photos/\(fileName)")
        #expect(XMPSidecar.isUsed(forImageAt: url))
        #expect(ImageKeywords.canWrite(to: url))
        #expect(XMPSidecar.url(forImageAt: url) == URL(filePath: "/Photos/photo.xmp"))
    }

    @Test(arguments: ["photo.jpg", "photo.heic", "photo.png"])
    func otherImagesDontUseSidecars(fileName: String) {
        #expect(!XMPSidecar.isUsed(forImageAt: URL(filePath: "/Photos/\(fileName)")))
    }

    @Test func createsASidecarWithoutChangingTheRAWImage() async throws {
        try await withTemporaryDirectory { directory in
            let url = try copyRAWImage(to: directory)
            let original = try Data(contentsOf: url)
            #expect(try XMPSidecar.keywords(forImageAt: url) == nil)

            let metadata = try await ImageKeywords.add(["architecture", "history"], toImageAt: url)

            #expect(metadata.keywords == ["architecture", "history"])
            #expect(try XMPSidecar.keywords(forImageAt: url) == ["architecture", "history"])
            #expect(try Data(contentsOf: url) == original)
            let sidecar = try sidecarMetadata(of: url)
            #expect(CGImageMetadataCopyStringValueWithPath(sidecar, nil, "xmp:MetadataDate" as CFString) != nil)
        }
    }

    @Test func keepsTheOtherMetadataOfExistingSidecars() async throws {
        try await withTemporaryDirectory { directory in
            let url = try copyRAWImage(to: directory)
            try FileManager.default.copyItem(at: resource("lightroom-sidecar", "xmp"), to: XMPSidecar.url(forImageAt: url))

            let metadata = try await ImageKeywords.add(["night", "timisoara"], toImageAt: url)

            #expect(metadata.keywords == ["Timisoara", "architecture", "night"])
            let sidecar = try sidecarMetadata(of: url)
            #expect(ImageKeywords.keywords(in: sidecar) == ["Timisoara", "architecture", "night"])
            let expectedValues = [
                "crs:Exposure2012": "+0.35",
                "crs:HasSettings": "True",
                "crs:ToneCurvePV2012[1]": "128, 140",
                "crs:Look.crs:Name": "Adobe Color",
                "crs:Look.crs:Parameters.crs:ProcessVersion": "15.4",
                "xmpMM:History[0].stEvt:action": "saved",
                "lr:hierarchicalSubject[0]": "Places|Timisoara",
                "xmp:Rating": "4",
                "tiff:Make": "FUJIFILM",
            ]
            for (path, value) in expectedValues {
                #expect(CGImageMetadataCopyStringValueWithPath(sidecar, nil, path as CFString) as String? == value, "\(path)")
            }
            #expect(CGImageMetadataCopyTagWithPath(sidecar, nil, "dc:title" as CFString) != nil)
        }
    }

    @Test func newSidecarsKeepTheKeywordsEmbeddedInTheImage() async throws {
        try await withTemporaryDirectory { directory in
            let url = try copyRAWImage(to: directory)

            let keywords = try XMPSidecar.add(["tree", "Holiday"], toImageAt: url, embeddedKeywords: ["holiday", "Family"])

            #expect(keywords == ["holiday", "Family", "tree"])
            #expect(try XMPSidecar.keywords(forImageAt: url) == ["holiday", "Family", "tree"])
        }
    }

    @Test func doesNotDuplicateSavedKeywords() async throws {
        try await withTemporaryDirectory { directory in
            let url = try copyRAWImage(to: directory)
            _ = try await ImageKeywords.add(["architecture", "history"], toImageAt: url)
            let sidecar = try Data(contentsOf: XMPSidecar.url(forImageAt: url))

            let metadata = try await ImageKeywords.add(["History"], toImageAt: url)

            #expect(metadata.keywords == ["architecture", "history"])
            #expect(try Data(contentsOf: XMPSidecar.url(forImageAt: url)) == sidecar)
        }
    }

    @Test func doesNotChangeSidecarsItCantRead() async throws {
        try await withTemporaryDirectory { directory in
            let url = try copyRAWImage(to: directory)
            let sidecarURL = XMPSidecar.url(forImageAt: url)
            let invalid = Data("<x:xmpmeta><rdf:RDF".utf8)
            try invalid.write(to: sidecarURL)

            await #expect(throws: KeywordWritingError.invalidSidecar("timisoara-water-tower.xmp")) {
                try await ImageKeywords.add(["tree"], toImageAt: url)
            }
            #expect(try Data(contentsOf: sidecarURL) == invalid)
        }
    }

    @Test func doesNotReplaceSidecarsItCantAccess() async throws {
        try await withTemporaryDirectory { directory in
            let url = try copyRAWImage(to: directory)
            let sidecarURL = XMPSidecar.url(forImageAt: url)
            try FileManager.default.copyItem(at: resource("lightroom-sidecar", "xmp"), to: sidecarURL)
            let original = try Data(contentsOf: sidecarURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sidecarURL.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: sidecarURL.path) }

            await #expect(throws: CocoaError.self) {
                try await ImageKeywords.add(["tree"], toImageAt: url)
            }
            #expect(throws: CocoaError.self) {
                try XMPSidecar.keywords(forImageAt: url)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: sidecarURL.path)
            #expect(try Data(contentsOf: sidecarURL) == original)
        }
    }

    @Test func analyzesRAWImagesAndReadsTheirSidecar() async throws {
        let predictor = try await TagPredictor.shared.value

        try await withTemporaryDirectory { directory in
            let url = try copyRAWImage(to: directory)
            try FileManager.default.copyItem(at: resource("lightroom-sidecar", "xmp"), to: XMPSidecar.url(forImageAt: url))

            let analysis = try await ImageAnalyzer.analyze(url, using: predictor)

            #expect(analysis.tags.contains("architecture"), "Predicted \(analysis.tags)")
            #expect(analysis.metadata.keywords == ["Timisoara", "architecture"])
            #expect(analysis.metadata.cameraModel == "Test DNG")
        }
    }

    @Test @MainActor func sessionSavesRAWTagsToSidecars() async throws {
        try await withTemporaryDirectory { directory in
            let url = try copyRAWImage(to: directory)
            let session = makeSession()
            await session.add([url])
            while let task = session.analysisTask { await task.value }
            let item = try #require(session.items.first)
            #expect(item.sidecarURL == XMPSidecar.url(forImageAt: url))
            #expect(item.hasUnsavedTags)

            await session.saveTags(of: [item])

            #expect(item.areTagsSaved)
            #expect(try XMPSidecar.keywords(forImageAt: url) == item.tags)
        }
    }

    // MARK: - Helpers

    private func resource(_ name: String, _ fileExtension: String) -> URL {
        Bundle(for: BundleToken.self).url(forResource: name, withExtension: fileExtension)!
    }

    private func copyRAWImage(to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("timisoara-water-tower.dng")
        try FileManager.default.copyItem(at: resource("timisoara-water-tower", "dng"), to: url)
        return url
    }

    private func sidecarMetadata(of url: URL) throws -> CGImageMetadata {
        let data = try Data(contentsOf: XMPSidecar.url(forImageAt: url))
        return try #require(CGImageMetadataCreateFromXMPData(data as CFData))
    }
}

private final class BundleToken {}
