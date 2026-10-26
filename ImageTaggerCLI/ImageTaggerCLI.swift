//
//  ImageTaggerCLI.swift
//  ImageTaggerCLI
//

import Foundation

/// The result of tagging an image.
nonisolated struct TaggingResult: Sendable {
    let url: URL
    var tags: [String] = []
    /// Why the image couldn't be analyzed.
    var analysisError: (any Error)?
    /// Why the tags couldn't be saved to the file.
    var savingError: (any Error)?
    var isSaved = false
}

/// The `imagetagger` command, which tags images from the Terminal.
///
/// It's embedded in the app at `ImageTagger.app/Contents/Helpers/imagetagger` and uses the app's tagging model.
/// Unlike the app, it isn't sandboxed, so it can save tags to any file the user can write.
@main
enum ImageTaggerCLI {
    /// The maximum number of images analyzed in parallel.
    static let maxConcurrentAnalyses = ProcessInfo.processInfo.activeProcessorCount

    static func main() async {
        let options: CommandLineOptions
        do {
            options = try CommandLineOptions(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            printError("\(error.localizedDescription)\nRun imagetagger --help to see the options.")
            exit(EX_USAGE)
        }
        if options.showsHelp {
            print(CommandLineOptions.usage)
            exit(EXIT_SUCCESS)
        }
        guard let appBundle else {
            printError("ImageTagger.app wasn't found. Run imagetagger from the app, or through a symbolic link to it.")
            exit(EXIT_FAILURE)
        }
        if options.showsVersion {
            print(appBundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            exit(EXIT_SUCCESS)
        }

        var succeeded = true
        var urls: [URL] = []
        for path in options.paths {
            let url = URL(fileURLWithPath: path).absoluteURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                printError("\(path): No such file or folder")
                succeeded = false
            } else if !isDirectory.boolValue, !ImageFinder.isImage(url) {
                printError("\(path): Not an image")
                succeeded = false
            } else {
                urls.append(url)
            }
        }
        var knownFiles = Set<URL>()
        let files = await ImageFinder.imageFiles(in: urls).filter { knownFiles.insert($0.standardizedFileURL).inserted }
        guard !files.isEmpty else {
            if succeeded {
                printError("no images found")
            }
            exit(EXIT_FAILURE)
        }

        let predictor: TagPredictor
        do {
            predictor = try await TagPredictor.load(
                from: appBundle.url(forResource: "TagPrediction", withExtension: "mlmodelc")
            )
        } catch {
            printError("the tagging model couldn’t be loaded. \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }

        var savedCount = 0
        await tag(files, using: predictor, savingTags: options.savesTags) { result in
            let path = displayPath(of: result.url)
            if let error = result.analysisError {
                printError("\(path): \(error.localizedDescription)")
                succeeded = false
                return
            }
            print(result.tags.isEmpty ? "\(path):" : "\(path): \(options.format.format(result.tags))")
            if let error = result.savingError {
                printError("\(path): \(error.localizedDescription)")
                // Images in formats without keywords, like PNG, are expected in folders and aren't failures.
                if error as? KeywordWritingError != .unsupportedFormat {
                    succeeded = false
                }
            }
            if result.isSaved {
                savedCount += 1
            }
        }

        if options.savesTags {
            let images = files.count == 1 ? "image" : "images"
            printToStandardError("Saved the tags of \(savedCount) of \(files.count) \(images).")
        }
        exit(succeeded ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    /// The app that contains the command, and the tagging model.
    ///
    /// The command is at `ImageTagger.app/Contents/Helpers/imagetagger`, and is usually run through a symbolic link.
    private static var appBundle: Bundle? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let appURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return appURL.pathExtension == "app" ? Bundle(url: appURL) : nil
    }

    /// Analyzes the images in parallel and saves their tags, reporting the results in the order of `files`.
    private static func tag(
        _ files: [URL],
        using predictor: TagPredictor,
        savingTags: Bool,
        report: (TaggingResult) -> Void
    ) async {
        await withTaskGroup(of: (Int, TaggingResult).self) { group in
            var nextIndex = 0
            var runningCount = 0
            var reportedCount = 0
            // The results of images that finished before an image added earlier.
            var finishedResults: [Int: TaggingResult] = [:]
            while true {
                if runningCount < maxConcurrentAnalyses, nextIndex < files.count {
                    let index = nextIndex
                    let url = files[index]
                    group.addTask {
                        (index, await tagImage(at: url, using: predictor, savingTags: savingTags))
                    }
                    nextIndex += 1
                    runningCount += 1
                } else if let (index, result) = await group.next() {
                    runningCount -= 1
                    finishedResults[index] = result
                    while let result = finishedResults.removeValue(forKey: reportedCount) {
                        report(result)
                        reportedCount += 1
                    }
                } else {
                    break
                }
            }
        }
    }

    /// Predicts the image's tags, and adds them to the keywords stored in the file if `savingTags` is true.
    @concurrent
    nonisolated private static func tagImage(
        at url: URL,
        using predictor: TagPredictor,
        savingTags: Bool
    ) async -> TaggingResult {
        var result = TaggingResult(url: url)
        do {
            result.tags = try await ImageAnalyzer.analyze(url, using: predictor).tags
        } catch {
            result.analysisError = error
            return result
        }
        guard savingTags, !result.tags.isEmpty else { return result }
        guard ImageKeywords.canWrite(to: url) else {
            result.savingError = KeywordWritingError.unsupportedFormat
            return result
        }
        do {
            _ = try await ImageKeywords.add(result.tags, toImageAt: url)
            result.isSaved = true
        } catch {
            result.savingError = error
        }
        return result
    }

    /// Returns the path of `url` relative to the current folder, or its full path if it's outside the current folder.
    private static func displayPath(of url: URL) -> String {
        let currentFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.path
        let prefix = currentFolder + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
    }

    /// Writes a message to the standard error, prefixed with the command's name.
    private static func printError(_ message: String) {
        printToStandardError("imagetagger: \(message)")
    }

    private static func printToStandardError(_ message: String) {
        // The standard output is buffered when it's redirected, so flush it to keep the messages in order.
        fflush(nil)
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
