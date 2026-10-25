//
//  InspectorView.swift
//  ImageTagger
//

import SwiftUI

/// Shows the tags and metadata of the selected image.
struct InspectorView: View {
    @Environment(TaggingSession.self) private var session

    var body: some View {
        if let item = session.selectedItem {
            ImageInspector(item: item)
        } else {
            ContentUnavailableView("No Selection", systemImage: "info.circle")
        }
    }
}

private struct ImageInspector: View {
    @Environment(TaggingSession.self) private var session
    @AppStorage(TagFormat.storageKey) private var tagFormat = TagFormat.comma
    @State private var copyCount = 0
    @State private var showsCopiedConfirmation = false
    let item: ImageItem

    var body: some View {
        Form {
            Section("Tags") {
                tags
                Picker("Format", selection: $tagFormat) {
                    ForEach(TagFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .help("Choose how tags are separated")
                HStack {
                    Button {
                        session.copyTags(of: item, format: tagFormat)
                        copyCount += 1
                    } label: {
                        Label(
                            showsCopiedConfirmation ? "Copied" : "Copy Tags",
                            systemImage: showsCopiedConfirmation ? "checkmark" : "doc.on.doc"
                        )
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(item.tags.isEmpty)
                    .help("Copy the tags to the clipboard")

                    SaveTagsButton(item: item)
                }
            }

            if let keywords = item.analysis?.metadata.keywords, !keywords.isEmpty {
                Section {
                    Text(keywords.joined(separator: ", "))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("keywords")
                } header: {
                    Text("Keywords in File")
                } footer: {
                    if let sidecarURL = item.sidecarURL {
                        Text("Stored in \(sidecarURL.lastPathComponent)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let metadata = item.analysis?.metadata {
                MetadataSection(title: "Information", entries: metadata.informationEntries())
                MetadataSection(title: "Camera", entries: metadata.cameraEntries())
            }
        }
        .formStyle(.grouped)
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            showsCopiedConfirmation = true
            try? await Task.sleep(for: .seconds(1.5))
            showsCopiedConfirmation = false
        }
        .onChange(of: item.id) {
            showsCopiedConfirmation = false
        }
    }

    @ViewBuilder
    private var tags: some View {
        switch item.status {
        case .pending, .analyzing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Analyzing…")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case .tagged(let analysis) where analysis.tags.isEmpty:
            Text("No tags found")
                .foregroundStyle(.secondary)
        case .tagged(let analysis):
            Text(tagFormat.format(analysis.tags))
                .textSelection(.enabled)
                .accessibilityIdentifier("tags")
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Saves the tags to the image file's keywords.
private struct SaveTagsButton: View {
    @Environment(TaggingSession.self) private var session
    let item: ImageItem

    var body: some View {
        Button {
            Task { await session.saveTags(of: [item]) }
        } label: {
            Group {
                if item.isSavingTags {
                    Label {
                        Text("Saving…")
                    } icon: {
                        ProgressView()
                            .controlSize(.small)
                    }
                } else if item.areTagsSaved {
                    Label("Saved", systemImage: "checkmark")
                } else {
                    Label("Save to File", systemImage: "square.and.arrow.down")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(!item.hasUnsavedTags || item.isSavingTags)
        .help(help)
    }

    private var help: LocalizedStringKey {
        if !item.canSaveTags {
            "Tags can only be saved to JPEG, HEIC, TIFF and RAW images"
        } else if let sidecarURL = item.sidecarURL {
            item.areTagsSaved
                ? "The tags are saved in \(sidecarURL.lastPathComponent)"
                : "Add the tags to the keywords in \(sidecarURL.lastPathComponent), the XMP sidecar file photo apps read for RAW images. Existing keywords are kept."
        } else if item.areTagsSaved {
            "The tags are saved in the file’s keywords"
        } else {
            "Add the tags to the keywords stored in the file. Existing keywords are kept."
        }
    }
}

private struct MetadataSection: View {
    let title: LocalizedStringKey
    let entries: [ImageMetadata.Entry]

    var body: some View {
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    LabeledContent(entry.label) {
                        Text(entry.value)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }
}
