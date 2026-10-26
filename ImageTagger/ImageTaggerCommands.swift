//
//  ImageTaggerCommands.swift
//  ImageTagger
//

import SwiftUI

/// The app's menu bar commands.
struct ImageTaggerCommands: Commands {
    let session: TaggingSession
    @AppStorage(TagFormat.storageKey) private var tagFormat = TagFormat.comma

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About ImageTagger") {
                AboutPanel.show()
            }
        }

        CommandGroup(after: .appSettings) {
            if CommandLineTool.isEmbedded {
                Button("Install Command Line Tool…") {
                    CommandLineTool.showInstallInstructions()
                }
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("Add Images…") {
                session.isImporterPresented = true
            }
            .keyboardShortcut("o")
        }

        CommandGroup(before: .saveItem) {
            Button("Save Tags to File") {
                if let item = session.selectedItem {
                    Task { await session.saveTags(of: [item]) }
                }
            }
            .keyboardShortcut("s")
            .disabled(!(session.selectedItem?.hasUnsavedTags ?? false) || (session.selectedItem?.isSavingTags ?? false))

            Button("Save Tags to All Images…") {
                session.isConfirmingSaveAll = true
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(session.itemsWithUnsavedTags.isEmpty)
            Divider()
        }

        CommandGroup(after: .pasteboard) {
            Button("Copy Tags") {
                if let item = session.selectedItem {
                    session.copyTags(of: item, format: tagFormat)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(session.selectedItem?.tags.isEmpty ?? true)
        }

        CommandGroup(before: .sidebar) {
            Picker("Tag Format", selection: $tagFormat) {
                ForEach(TagFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            Divider()
        }

        CommandMenu("Image") {
            Button("Open with Default App") {
                if let item = session.selectedItem {
                    session.open(item)
                }
            }
            .keyboardShortcut(.downArrow)
            .disabled(session.selectedItem == nil)

            Button("Show in Finder") {
                if let item = session.selectedItem {
                    session.showInFinder(item)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(session.selectedItem == nil)

            Divider()

            Button("Stop Analyzing") {
                session.cancelAnalysis()
            }
            .keyboardShortcut(".")
            .disabled(!session.isAnalyzing)

            Divider()

            Button("Remove from List") {
                if let selection = session.selection {
                    session.remove([selection])
                }
            }
            .disabled(session.selectedItem == nil)

            Button("Remove All") {
                session.removeAll()
            }
            .disabled(session.items.isEmpty)
        }

        CommandGroup(replacing: .help) {
            Link("ImageTagger on GitHub", destination: AboutPanel.sourceCodeURL)
            Link("NucuLabs Blog", destination: AboutPanel.websiteURL)
        }
    }
}
