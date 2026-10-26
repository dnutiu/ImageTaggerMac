//
//  TaggingSession.swift
//  ImageTagger
//

import AppKit
import Foundation
import Observation
import OSLog
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "nuculabs.dev.ImageTagger", category: "TaggingSession")

/// Manages the images of the current session and analyzes them in the background.
@Observable
final class TaggingSession {
    /// An error shown when the tagging model can't be loaded.
    struct ModelLoadingError: LocalizedError {
        let underlyingError: any Error

        var errorDescription: String? { String(localized: "Couldn’t Load the Tagging Model") }
        var recoverySuggestion: String? { underlyingError.localizedDescription }
    }

    /// An error shown when tags can't be saved to some images.
    struct TagSavingError: LocalizedError {
        let failures: [(fileName: String, error: any Error)]

        var errorDescription: String? {
            if failures.count == 1, let failure = failures.first {
                return String(localized: "Couldn’t Save Tags to “\(failure.fileName)”")
            }
            return String(localized: "Couldn’t Save Tags to \(failures.count) Images")
        }

        var recoverySuggestion: String? {
            if failures.count == 1 {
                return failures.first?.error.localizedDescription
            }
            return failures
                .map { "\($0.fileName): \($0.error.localizedDescription)" }
                .joined(separator: "\n")
        }
    }

    /// The user defaults key of the setting that saves tags to the image files after they're analyzed.
    static let savesTagsAutomaticallyKey = "savesTagsAutomatically"

    /// The maximum number of images analyzed in parallel.
    static let maxConcurrentAnalyses = ProcessInfo.processInfo.activeProcessorCount

    private(set) var items: [ImageItem] = []
    var selection: ImageItem.ID?
    var isImporterPresented = false

    private(set) var isAnalyzing = false
    /// The number of images analyzed since the analysis started.
    private(set) var completedCount = 0
    /// The number of images added since the analysis started.
    private(set) var batchCount = 0

    var modelLoadingError: ModelLoadingError?
    var isShowingModelLoadingError = false

    /// The number of images whose tags were saved since saving started.
    private(set) var savedCount = 0
    /// The number of images whose tags are being saved.
    private(set) var savingCount = 0
    var isConfirmingSaveAll = false
    var tagSavingError: TagSavingError?
    var isShowingTagSavingError = false

    @ObservationIgnored private let loadPredictor: @Sendable () async throws -> TagPredictor
    @ObservationIgnored private(set) var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var queue: [ImageItem] = []
    @ObservationIgnored private var securityScopedURLs: [URL] = []
    @ObservationIgnored private var tagSavingFailures: [(fileName: String, error: any Error)] = []
    @ObservationIgnored private let defaults: UserDefaults

    init(
        loadPredictor: @escaping @Sendable () async throws -> TagPredictor = { try await TagPredictor.shared.value },
        defaults: UserDefaults = .standard
    ) {
        self.loadPredictor = loadPredictor
        self.defaults = defaults
    }

    var selectedItem: ImageItem? {
        guard let selection else { return nil }
        return items.first { $0.id == selection }
    }

    /// The images whose tags can be saved and aren't saved yet.
    var itemsWithUnsavedTags: [ImageItem] {
        items.filter { $0.hasUnsavedTags && !$0.isSavingTags }
    }

    var isSavingTags: Bool { savingCount > 0 }

    // MARK: - Adding and removing images

    /// Adds the images at `urls` to the session and starts analyzing them.
    ///
    /// Folders are searched for images. Images that are already in the session are skipped.
    func add(_ urls: [URL]) async {
        for url in urls where url.startAccessingSecurityScopedResource() {
            securityScopedURLs.append(url)
        }

        let files = await ImageFinder.imageFiles(in: urls)
        var knownFiles = Set(items.map(\.url.standardizedFileURL))
        let newItems = files
            .filter { knownFiles.insert($0.standardizedFileURL).inserted }
            .map(ImageItem.init(url:))
        guard !newItems.isEmpty else {
            if files.isEmpty { NSSound.beep() }
            return
        }

        items += newItems
        queue += newItems
        batchCount += newItems.count
        if selection == nil {
            selection = newItems.first?.id
        }
        startAnalysisIfNeeded()
    }

    /// Removes the images with the given identifiers from the session.
    func remove(_ ids: Set<ImageItem.ID>) {
        guard !ids.isEmpty else { return }
        let removedPendingCount = queue.count(where: { ids.contains($0.id) })
        queue.removeAll { ids.contains($0.id) }
        batchCount -= removedPendingCount

        if let selection, ids.contains(selection) {
            let index = items.firstIndex { $0.id == selection } ?? 0
            let remaining = items.filter { !ids.contains($0.id) }
            self.selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        }
        items.removeAll { ids.contains($0.id) }
    }

    /// Removes all images and stops the analysis.
    func removeAll() {
        cancelAnalysis()
        items.removeAll()
        selection = nil
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
    }

    // MARK: - Analysis

    /// Stops the analysis and removes the images that weren't analyzed yet.
    func cancelAnalysis() {
        guard let analysisTask else { return }
        analysisTask.cancel()
        queue.removeAll()
        remove(Set(items.filter(\.isInProgress).map(\.id)))
        isAnalyzing = false
        completedCount = 0
        batchCount = 0
    }

    private func startAnalysisIfNeeded() {
        guard analysisTask == nil, !queue.isEmpty else { return }
        isAnalyzing = true
        analysisTask = Task {
            await analyzeQueuedItems()
            analysisTask = nil
            if queue.isEmpty {
                isAnalyzing = false
                completedCount = 0
                batchCount = 0
            } else {
                // Images were added while a cancelled analysis was finishing.
                startAnalysisIfNeeded()
            }
        }
    }

    private func analyzeQueuedItems() async {
        let predictor: TagPredictor
        do {
            predictor = try await loadPredictor()
        } catch is CancellationError {
            return
        } catch {
            for item in queue {
                item.status = .failed(String(localized: "The tagging model couldn’t be loaded."))
            }
            queue.removeAll()
            modelLoadingError = ModelLoadingError(underlyingError: error)
            isShowingModelLoadingError = true
            return
        }

        await withTaskGroup(of: (ImageItem, Result<ImageAnalysis, any Error>).self) { group in
            var runningCount = 0
            while !Task.isCancelled {
                if runningCount < Self.maxConcurrentAnalyses, !queue.isEmpty {
                    let item = queue.removeFirst()
                    item.status = .analyzing
                    let url = item.url
                    group.addTask {
                        do {
                            return (item, .success(try await ImageAnalyzer.analyze(url, using: predictor)))
                        } catch {
                            return (item, .failure(error))
                        }
                    }
                    runningCount += 1
                } else if runningCount > 0, let (item, result) = await group.next() {
                    runningCount -= 1
                    guard !Task.isCancelled else { break }
                    switch result {
                    case .success(let analysis):
                        item.status = .tagged(analysis)
                        if defaults.bool(forKey: Self.savesTagsAutomaticallyKey) {
                            Task { await saveTags(of: [item]) }
                        }
                    case .failure(let error):
                        logger.error("Couldn’t analyze \(item.url.path, privacy: .private): \(error)")
                        item.status = .failed(error.localizedDescription)
                    }
                    completedCount += 1
                } else {
                    break
                }
            }
        }
    }

    // MARK: - Saving tags

    /// Adds the images' tags to the keywords stored in their files.
    ///
    /// The errors are reported together, once all the images being saved are done.
    func saveTags(of items: [ImageItem]) async {
        let items = items.filter { $0.hasUnsavedTags && !$0.isSavingTags }
        guard !items.isEmpty else { return }
        for item in items {
            item.isSavingTags = true
        }
        savingCount += items.count

        for item in items {
            do {
                let metadata = try await ImageKeywords.add(item.tags, toImageAt: item.url)
                if case .tagged(var analysis) = item.status {
                    analysis.metadata = metadata
                    item.status = .tagged(analysis)
                }
            } catch {
                logger.error("Couldn’t save tags of \(item.url.path, privacy: .private): \(error)")
                tagSavingFailures.append((item.fileName, error))
            }
            item.isSavingTags = false
            savedCount += 1
        }

        guard savedCount == savingCount else { return }
        savedCount = 0
        savingCount = 0
        if !tagSavingFailures.isEmpty {
            tagSavingError = TagSavingError(failures: tagSavingFailures)
            isShowingTagSavingError = true
            tagSavingFailures.removeAll()
        }
    }

    // MARK: - Actions

    func copyTags(of item: ImageItem, format: TagFormat) {
        guard !item.tags.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(format.format(item.tags), forType: .string)
    }

    /// Opens the image in the user's default image viewer.
    func open(_ item: ImageItem) {
        NSWorkspace.shared.open(item.url)
    }

    func showInFinder(_ item: ImageItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: - Finding images

    /// Returns whether `urls` contain an image or a folder, which may contain images.
    static func containsImagesOrFolders(_ urls: [URL]) -> Bool {
        urls.contains { url in
            let values = try? url.resourceValues(forKeys: [.contentTypeKey])
            return values?.contentType.map { $0.conforms(to: .image) || $0.conforms(to: .folder) } ?? false
        }
    }
}
