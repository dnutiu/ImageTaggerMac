//
//  CommandLineTool.swift
//  ImageTagger
//

import AppKit

/// The `imagetagger` command embedded in the app, which tags images from the Terminal.
enum CommandLineTool {
    /// The location of the command in the app.
    static var url: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/imagetagger")
    }

    /// Whether the app includes the command.
    ///
    /// Release builds leave it out unless `EMBEDS_COMMAND_LINE_TOOL` is set, as `Scripts/release.sh` does, because
    /// every executable in a Mac App Store app has to be sandboxed, and a sandboxed command couldn't read the images in
    /// the Terminal's current folder.
    static var isEmbedded: Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// The Terminal command that links the command into `/usr/local/bin`, which is in the shell's search path.
    ///
    /// The app is sandboxed, so it can't create the link itself.
    static var installCommand: String {
        "sudo mkdir -p /usr/local/bin && sudo ln -sf \(shellQuoted(url.path)) /usr/local/bin/imagetagger"
    }

    /// Explains how to install the command, and copies the command that installs it.
    static func showInstallInstructions() {
        let alert = NSAlert()
        // A link to an app that runs from the disk image, or from a randomized read-only location because it was
        // downloaded and not moved yet, would stop working.
        let values = try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        guard values?.volumeIsReadOnly != true else {
            alert.messageText = String(localized: "Move ImageTagger to the Applications Folder")
            alert.informativeText = String(localized: "The imagetagger command can be installed once ImageTagger is in the Applications folder.")
            alert.runModal()
            return
        }

        alert.messageText = String(localized: "Install the imagetagger Command")
        alert.informativeText = String(localized: """
            To tag images from the Terminal, run this command to link imagetagger into /usr/local/bin:

            \(installCommand)

            Then run imagetagger in a folder to save the tags of its images, or imagetagger --help to see the options.
            """)
        alert.addButton(withTitle: String(localized: "Copy Command"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(installCommand, forType: .string)
    }

    /// Quotes `path` for the shell, if it contains characters the shell would interpret.
    static func shellQuoted(_ path: String) -> String {
        let safeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+"))
        guard path.unicodeScalars.contains(where: { !safeCharacters.contains($0) }) else { return path }
        return "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
