//
//  CommandLineToolTests.swift
//  ImageTaggerTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ImageTagger

/// Tests the `imagetagger` command embedded in the app, by running it like the Terminal does.
///
/// The tests run one at a time, because Core ML caches the compiled model the first time the command runs, and when
/// several commands create the cache at once, Core ML prints errors to the standard output.
@Suite(.serialized)
struct CommandLineToolTests {
    struct CommandResult {
        var status: Int32
        var output: String
        var errors: String
    }

    @Test func printsTagsWithoutSavingThemInADryRun() async throws {
        try await withTemporaryDirectory { directory in
            let url = try copy(.timisoaraTrees, to: directory)
            let original = try Data(contentsOf: url)

            let result = try await run(["--dry-run", "--format", "hashtags"], in: directory)

            #expect(result.status == EXIT_SUCCESS)
            #expect(result.output.hasPrefix("timisoara-threes.jpg: #"))
            #expect(result.output.contains("#tree"))
            #expect(!result.errors.contains("imagetagger:"))
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func savesTagsToTheImagesInTheCurrentFolder() async throws {
        try await withTemporaryDirectory { directory in
            let subfolder = directory.appending(path: "Trip")
            try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
            let jpeg = try copy(.timisoaraTrees, to: directory)
            let raw = subfolder.appending(path: "timisoara-water-tower.dng")
            let rawResource = try #require(Bundle(for: BundleToken.self).url(forResource: "timisoara-water-tower", withExtension: "dng"))
            try FileManager.default.copyItem(at: rawResource, to: raw)

            let result = try await run([], in: directory)

            #expect(result.status == EXIT_SUCCESS)
            let paths = result.output.split(separator: "\n").map { $0.prefix { $0 != ":" } }
            #expect(paths == ["timisoara-threes.jpg", "Trip/timisoara-water-tower.dng"])
            #expect(result.errors.contains("Saved the tags of 2 of 2 images.\n"))
            #expect(!result.errors.contains("imagetagger:"))
            #expect(ImageKeywords.keywords(in: try ImageLoader.source(at: jpeg)).contains("tree"))
            #expect(try XMPSidecar.keywords(forImageAt: raw)?.contains("tower") == true)
        }
    }

    @Test func doesNotFailForImagesWhoseTagsCantBeSaved() async throws {
        try await withTemporaryDirectory { directory in
            let png = directory.appending(path: "photo.png")
            let image = try await ImageLoader.image(at: TestImage.timisoaraTrees.url, maxPixelSize: 400)
            let destination = try #require(CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))

            let result = try await run(["photo.png"], in: directory)

            #expect(result.status == EXIT_SUCCESS)
            #expect(result.output.hasPrefix("photo.png: "))
            #expect(result.errors.contains(KeywordWritingError.unsupportedFormat.localizedDescription))
        }
    }

    @Test func failsForMissingFiles() async throws {
        try await withTemporaryDirectory { directory in
            let result = try await run(["missing.jpg"], in: directory)

            #expect(result.status == EXIT_FAILURE)
            #expect(result.errors.contains("imagetagger: missing.jpg: No such file or folder\n"))
        }
    }

    @Test func rejectsUnknownOptions() async throws {
        try await withTemporaryDirectory { directory in
            let result = try await run(["--recursive"], in: directory)

            #expect(result.status == EX_USAGE)
            #expect(result.errors.contains("imagetagger: unknown option --recursive\n"))
        }
    }

    @Test @MainActor func quotesPathsInTheInstallCommand() {
        #expect(CommandLineTool.shellQuoted("/Applications/ImageTagger.app") == "/Applications/ImageTagger.app")
        #expect(CommandLineTool.shellQuoted("/Users/me/My Apps/ImageTagger.app") == "'/Users/me/My Apps/ImageTagger.app'")
        #expect(CommandLineTool.shellQuoted("/Volumes/Mac's Disk") == #"'/Volumes/Mac'\''s Disk'"#)
    }

    // MARK: - Helpers

    /// Runs the command embedded in the app, with `directory` as the current folder.
    private func run(_ arguments: [String], in directory: URL) async throws -> CommandResult {
        let process = Process()
        process.executableURL = await CommandLineTool.url
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // A Terminal's environment. The test runner's variables would load XCTest into the command, make it log to the
        // standard error, and make it act like the sandboxed app. The command inherits the runner's sandbox though, so
        // it keeps the home folder in the app's container, where Core ML can cache the compiled model.
        let variables: Set = ["HOME", "CFFIXED_USER_HOME", "PATH", "TMPDIR", "LLVM_PROFILE_FILE"]
        process.environment = ProcessInfo.processInfo.environment.filter { variables.contains($0.key) }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let outputHandle = output.fileHandleForReading
        let errorHandle = errors.fileHandleForReading
        try process.run()

        // Both pipes are read while the command runs, so it never waits for a full pipe to be emptied.
        async let outputText = text(from: outputHandle)
        async let errorText = text(from: errorHandle)
        let (outputString, errorString) = try await (outputText, errorText)
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: outputString, errors: errorString)
    }

    private func text(from handle: FileHandle) async throws -> String {
        var data = Data()
        for try await byte in handle.bytes {
            data.append(byte)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private final class BundleToken {}
