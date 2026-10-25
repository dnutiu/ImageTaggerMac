//
//  TagPredictorTests.swift
//  ImageTaggerTests
//

import Foundation
import Testing
@testable import ImageTagger

struct TagPredictorTests {
    /// Tags the model predicts consistently for each test image.
    ///
    /// Tags close to the confidence threshold depend on how the image is scaled, so they aren't checked.
    @Test(arguments: [
        (TestImage.timisoaraBega, ["nature", "night", "no people", "outdoors", "reflection", "sky", "water"]),
        (TestImage.timisoaraTrees, ["day", "growth", "nature", "no people", "outdoors", "plant", "tree"]),
        (TestImage.timisoaraWaterTower, ["architecture", "building exterior", "built structure", "history", "no people", "outdoors", "travel destinations"]),
    ])
    func predictsTags(image: TestImage, expectedTags: [String]) async throws {
        let predictor = try await TagPredictor.shared.value

        let analysis = try await ImageAnalyzer.analyze(image.url, using: predictor)

        #expect(Set(expectedTags).isSubset(of: analysis.tags), "Predicted \(analysis.tags)")
        #expect(analysis.tags == analysis.tags.sorted())
        #expect(analysis.tags.count <= expectedTags.count + 3, "Predicted \(analysis.tags)")
    }

    @Test func analyzingANonImageFileFails() async throws {
        let predictor = try await TagPredictor.shared.value

        try await withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("notes.txt")
            try Data("Not an image".utf8).write(to: url)

            await #expect(throws: ImageLoadingError.unsupportedFormat) {
                try await ImageAnalyzer.analyze(url, using: predictor)
            }
        }
    }

    @Test func missingModelFails() async {
        await #expect(throws: TagPredictorError.modelNotFound) {
            try await TagPredictor.load(from: nil)
        }
    }
}
