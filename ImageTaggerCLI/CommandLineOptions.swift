//
//  CommandLineOptions.swift
//  ImageTaggerCLI
//

import Foundation

/// An error in the command's arguments.
nonisolated enum UsageError: LocalizedError {
    case unknownOption(String)
    case missingValue(String)
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .unknownOption(let option):
            "unknown option \(option)"
        case .missingValue(let option):
            "\(option) needs a value"
        case .invalidFormat(let format):
            "unknown tag format \(format), use comma, space or hashtags"
        }
    }
}

/// The options of the `imagetagger` command, parsed from its arguments.
nonisolated struct CommandLineOptions {
    static let usage = """
        OVERVIEW: Predicts the tags of images and adds them to the keywords stored in the files.

        USAGE: imagetagger [--dry-run] [--format <format>] [<path> ...]

        ARGUMENTS:
          <path>                  Images or folders to tag. Folders are searched recursively.
                                  The current folder is tagged when no path is given.

        OPTIONS:
          -n, --dry-run           Print the tags without saving them.
          -f, --format <format>   How tags are printed: comma, space or hashtags. (default: comma)
          --version               Show the version.
          -h, --help              Show this help.

        Tags are saved like in the app: to the XMP keywords of JPEG, HEIC and TIFF images, without compressing
        them again, and to an XMP sidecar file for RAW images. Existing keywords are kept.
        """

    /// The images and folders to tag, the current folder by default.
    var paths: [String] = []
    var savesTags = true
    var format = TagFormat.comma
    var showsHelp = false
    var showsVersion = false

    init(arguments: [String]) throws(UsageError) {
        var arguments = arguments.makeIterator()
        var parsesOptions = true
        while let argument = arguments.next() {
            guard parsesOptions, argument.hasPrefix("-"), argument != "-" else {
                paths.append(argument)
                continue
            }
            // Long options can also have their value after an equals sign, as in --format=hashtags.
            var option = argument
            var value: String?
            if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
                option = String(argument[..<equals])
                value = String(argument[argument.index(after: equals)...])
            }

            switch option {
            case "-f", "--format":
                guard let value = value ?? arguments.next() else { throw .missingValue(option) }
                guard let format = TagFormat(rawValue: value) else { throw .invalidFormat(value) }
                self.format = format
            case _ where value != nil:
                throw .unknownOption(argument)
            case "--":
                parsesOptions = false
            case "-n", "--dry-run":
                savesTags = false
            case "-h", "--help":
                showsHelp = true
            case "--version":
                showsVersion = true
            default:
                throw .unknownOption(argument)
            }
        }
        if paths.isEmpty {
            paths = ["."]
        }
    }
}
