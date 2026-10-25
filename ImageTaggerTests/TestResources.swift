//
//  TestResources.swift
//  ImageTaggerTests
//

import Foundation
import Testing
@testable import ImageTagger

private final class BundleToken {}

/// Test photos by https://unsplash.com/@ndcphoto, shared with the original ImageTagger tests.
enum TestImage: String, CaseIterable, CustomTestStringConvertible {
    case timisoaraBega = "timisoara-bega"
    case timisoaraTrees = "timisoara-threes"
    case timisoaraWaterTower = "timisoara-water-tower"

    var url: URL {
        Bundle(for: BundleToken.self).url(forResource: rawValue, withExtension: "jpg")!
    }

    var testDescription: String { rawValue }
}

/// Creates a temporary directory that's removed when `body` returns.
func withTemporaryDirectory<Result>(_ body: (URL) async throws -> Result) async rethrows -> Result {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ImageTaggerTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
}

/// Creates a session with its own user defaults, so the app's settings don't affect tests.
@MainActor
func makeSession(
    savesTagsAutomatically: Bool = false,
    loadPredictor: @escaping @Sendable () async throws -> TagPredictor = { try await TagPredictor.shared.value }
) -> TaggingSession {
    let defaults = UserDefaults(suiteName: "ImageTaggerTests-\(UUID().uuidString)")!
    defaults.set(savesTagsAutomatically, forKey: TaggingSession.savesTagsAutomaticallyKey)
    return TaggingSession(loadPredictor: loadPredictor, defaults: defaults)
}
