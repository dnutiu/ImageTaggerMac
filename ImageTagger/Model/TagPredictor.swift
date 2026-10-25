//
//  TagPredictor.swift
//  ImageTagger
//

import CoreML
import Foundation
import Vision

/// Errors thrown while loading the tagging model.
nonisolated enum TagPredictorError: LocalizedError {
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            String(localized: "The tagging model is missing from the app. If you built ImageTagger from source, generate TagPrediction.mlpackage as described in the README.")
        }
    }
}

/// Predicts an image's tags with a ResNet based multi-label Core ML classifier.
nonisolated final class TagPredictor: Sendable {
    /// Tags with a probability above this value are reported.
    ///
    /// It matches the logit threshold of -0.5 used by the original model: sigmoid(-0.5) ≈ 0.3775.
    static let confidenceThreshold: Float = 0.3775

    /// The shared predictor, backed by the model bundled with the app.
    ///
    /// The model is loaded once, the first time this property is accessed.
    static let shared = Task { try await TagPredictor.load() }

    private let request: CoreMLRequest

    init(model: MLModel) throws {
        var request = CoreMLRequest(model: try CoreMLModelContainer(model: model))
        request.cropAndScaleAction = .centerCrop
        self.request = request
    }

    /// Loads the compiled model at `url`, the bundled model by default.
    static func load(
        from url: URL? = Bundle.main.url(forResource: "TagPrediction", withExtension: "mlmodelc")
    ) async throws -> TagPredictor {
        guard let url else {
            throw TagPredictorError.modelNotFound
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try await MLModel.load(contentsOf: url, configuration: configuration)
        return try TagPredictor(model: model)
    }

    /// Returns the predicted tags for `image`, sorted alphabetically.
    @concurrent
    func tags(for image: CGImage) async throws -> [String] {
        try await request.perform(on: image)
            .compactMap { $0 as? ClassificationObservation }
            .filter { $0.confidence > Self.confidenceThreshold }
            .map(\.identifier)
            .sorted()
    }
}
