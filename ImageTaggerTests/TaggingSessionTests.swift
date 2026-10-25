//
//  TaggingSessionTests.swift
//  ImageTaggerTests
//

import Foundation
import Testing
@testable import ImageTagger

@MainActor
struct TaggingSessionTests {
    @Test func analyzesAddedImages() async throws {
        let session = makeSession()

        await session.add(TestImage.allCases.map(\.url))
        #expect(session.items.count == 3)
        #expect(session.isAnalyzing)
        #expect(session.selection == session.items.first?.id)
        await waitForAnalysis(of: session)

        #expect(!session.isAnalyzing)
        for item in session.items {
            #expect(!item.tags.isEmpty, "\(item.fileName) has no tags")
        }
        #expect(session.items.map(\.fileName) == TestImage.allCases.map { "\($0.rawValue).jpg" })
    }

    @Test func skipsImagesAlreadyInTheSession() async {
        let session = makeSession()
        let url = TestImage.timisoaraBega.url

        await session.add([url, url])
        await session.add([url])

        #expect(session.items.count == 1)
        session.removeAll()
    }

    @Test func reportsImagesThatCantBeAnalyzed() async throws {
        let session = makeSession()

        try await withTemporaryDirectory { directory in
            // The file has an image extension but isn't a valid image.
            let url = directory.appendingPathComponent("broken.jpg")
            try Data("Not an image".utf8).write(to: url)

            await session.add([url])
            await waitForAnalysis(of: session)
        }

        let item = try #require(session.items.first)
        guard case .failed = item.status else {
            Issue.record("Expected the analysis to fail, got \(item.status)")
            return
        }
    }

    @Test func modelLoadingErrorsAreReported() async throws {
        let session = makeSession(loadPredictor: { throw TagPredictorError.modelNotFound })

        await session.add([TestImage.timisoaraBega.url])
        await waitForAnalysis(of: session)

        #expect(session.isShowingModelLoadingError)
        #expect(session.modelLoadingError != nil)
        let item = try #require(session.items.first)
        #expect(!item.isInProgress)
    }

    @Test func cancellingRemovesUnfinishedImages() async {
        let session = makeSession(loadPredictor: {
            try await Task.sleep(for: .seconds(0.5))
            return try await TagPredictor.shared.value
        })

        await session.add(TestImage.allCases.map(\.url))
        session.cancelAnalysis()

        #expect(session.items.isEmpty)
        #expect(session.selection == nil)
        #expect(!session.isAnalyzing)
        await waitForAnalysis(of: session)
        #expect(session.items.isEmpty)
    }

    @Test func removingTheSelectionSelectsTheNextImage() async {
        let session = makeSession()
        await session.add(TestImage.allCases.map(\.url))
        let ids = session.items.map(\.id)

        session.selection = ids[1]
        session.remove([ids[1]])
        #expect(session.selection == ids[2])

        session.remove([ids[2]])
        #expect(session.selection == ids[0])

        session.removeAll()
        #expect(session.items.isEmpty)
        #expect(session.selection == nil)
    }

    @Test func findsImagesInFoldersRecursively() async throws {
        try await withTemporaryDirectory { directory in
            let subfolder = directory.appendingPathComponent("Trip", isDirectory: true)
            try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
            let manager = FileManager.default
            try manager.copyItem(at: TestImage.timisoaraBega.url, to: directory.appendingPathComponent("b.jpg"))
            try manager.copyItem(at: TestImage.timisoaraTrees.url, to: directory.appendingPathComponent("a.jpg"))
            try manager.copyItem(at: TestImage.timisoaraWaterTower.url, to: subfolder.appendingPathComponent("c.jpg"))
            try manager.copyItem(at: TestImage.timisoaraBega.url, to: directory.appendingPathComponent(".hidden.jpg"))
            try Data("notes".utf8).write(to: directory.appendingPathComponent("notes.txt"))

            let files = await TaggingSession.imageFiles(in: [directory])

            #expect(files.map(\.lastPathComponent) == ["a.jpg", "b.jpg", "c.jpg"])
            #expect(TaggingSession.containsImagesOrFolders([directory]))
            #expect(!TaggingSession.containsImagesOrFolders([directory.appendingPathComponent("notes.txt")]))
        }
    }

    @Test func savesTagsToTheFiles() async throws {
        try await withTemporaryDirectory { directory in
            let session = makeSession()
            await session.add([try copy(.timisoaraBega, to: directory), try copy(.timisoaraTrees, to: directory)])
            await waitForAnalysis(of: session)
            #expect(session.itemsWithUnsavedTags.count == 2)

            await session.saveTags(of: session.items)

            #expect(session.itemsWithUnsavedTags.isEmpty)
            #expect(!session.isSavingTags)
            #expect(!session.isShowingTagSavingError)
            for item in session.items {
                #expect(item.areTagsSaved)
                let fileKeywords = ImageKeywords.keywords(in: try ImageLoader.source(at: item.url))
                #expect(fileKeywords == item.tags)
            }
        }
    }

    @Test func savesTagsAutomaticallyWhenEnabled() async throws {
        let session = makeSession(savesTagsAutomatically: true)

        try await withTemporaryDirectory { directory in
            var urls: [URL] = []
            for image in TestImage.allCases {
                urls.append(try copy(image, to: directory))
            }
            await session.add(urls)
            await waitForAnalysis(of: session)
            try await waitUntilTagsAreSaved(in: session)

            for item in session.items {
                #expect(item.areTagsSaved, "\(item.fileName) wasn't saved")
                #expect(ImageKeywords.keywords(in: try ImageLoader.source(at: item.url)) == item.tags)
            }
        }
    }

    @Test func doesNotSaveTagsAutomaticallyByDefault() async throws {
        let session = makeSession()

        try await withTemporaryDirectory { directory in
            let url = try copy(.timisoaraBega, to: directory)
            let original = try Data(contentsOf: url)

            await session.add([url])
            await waitForAnalysis(of: session)
            try await Task.sleep(for: .milliseconds(200))

            #expect(session.items.first?.hasUnsavedTags == true)
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func reportsTagSavingErrorsTogether() async throws {
        try await withTemporaryDirectory { directory in
            let session = makeSession()
            let urls = [try copy(.timisoaraBega, to: directory), try copy(.timisoaraTrees, to: directory)]
            await session.add(urls)
            await waitForAnalysis(of: session)

            // Neither the files nor their folder can be written.
            let manager = FileManager.default
            for url in urls {
                try manager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
            }
            try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
            defer {
                try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
                for url in urls {
                    try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
                }
            }

            await session.saveTags(of: session.items)

            #expect(session.isShowingTagSavingError)
            #expect(session.tagSavingError?.failures.map(\.fileName) == urls.map(\.lastPathComponent))
            #expect(session.itemsWithUnsavedTags.count == 2)
        }
    }

    private func waitUntilTagsAreSaved(in session: TaggingSession) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while session.items.contains(where: { !$0.areTagsSaved }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func waitForAnalysis(of session: TaggingSession) async {
        while let task = session.analysisTask {
            await task.value
        }
    }
}
