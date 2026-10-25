//
//  SidebarView.swift
//  ImageTagger
//

import SwiftUI

/// Lists the session's images.
struct SidebarView: View {
    @Environment(TaggingSession.self) private var session
    @AppStorage(TagFormat.storageKey) private var tagFormat = TagFormat.comma

    var body: some View {
        @Bindable var session = session

        List(selection: $session.selection) {
            ForEach(session.items) { item in
                ImageRow(item: item)
            }
        }
        .contextMenu(forSelectionType: ImageItem.ID.self) { ids in
            if let item = item(for: ids) {
                ImageItemActions(item: item)
            }
        } primaryAction: { ids in
            if let item = item(for: ids) {
                session.open(item)
            }
        }
        .accessibilityIdentifier("images")
        .onDeleteCommand {
            if let selection = session.selection {
                session.remove([selection])
            }
        }
        .copyable(copyableTags)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if session.isAnalyzing {
                    ActivityProgressView(
                        title: "Analyzed \(session.completedCount) of \(session.batchCount)",
                        completed: session.completedCount,
                        total: session.batchCount,
                        stop: session.cancelAnalysis
                    )
                }
                if session.isSavingTags {
                    ActivityProgressView(
                        title: "Saved \(session.savedCount) of \(session.savingCount)",
                        completed: session.savedCount,
                        total: session.savingCount
                    )
                }
            }
        }
    }

    /// The selected image's tags, copied with ⌘C.
    private var copyableTags: [String] {
        guard let tags = session.selectedItem?.tags, !tags.isEmpty else { return [] }
        return [tagFormat.format(tags)]
    }

    private func item(for ids: Set<ImageItem.ID>) -> ImageItem? {
        guard let id = ids.first else { return nil }
        return session.items.first { $0.id == id }
    }
}

/// The context menu actions for an image.
private struct ImageItemActions: View {
    @Environment(TaggingSession.self) private var session
    @AppStorage(TagFormat.storageKey) private var tagFormat = TagFormat.comma
    let item: ImageItem

    var body: some View {
        Button("Open with Default App") {
            session.open(item)
        }
        Button("Show in Finder") {
            session.showInFinder(item)
        }
        Divider()
        Button("Copy Tags") {
            session.copyTags(of: item, format: tagFormat)
        }
        .disabled(item.tags.isEmpty)
        Button("Save Tags to File") {
            Task { await session.saveTags(of: [item]) }
        }
        .disabled(!item.hasUnsavedTags || item.isSavingTags)
        Divider()
        Button("Remove from List") {
            session.remove([item.id])
        }
    }
}

private struct ImageRow: View {
    let item: ImageItem

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                status
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        switch item.status {
        case .pending:
            Text("Waiting")
        case .analyzing:
            Text("Analyzing…")
        case .tagged(let analysis) where item.areTagsSaved:
            Text("^[\(analysis.tags.count) tag](inflect: true) · Saved")
        case .tagged(let analysis):
            Text("^[\(analysis.tags.count) tag](inflect: true)")
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.multicolor)
        }
    }
}

private struct ThumbnailView: View {
    let item: ImageItem

    var body: some View {
        ZStack {
            if let thumbnail = item.thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                Image(systemName: isFailed ? "exclamationmark.triangle" : "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(.rect(cornerRadius: 6))
        .task(id: item.id) {
            await item.loadThumbnail()
        }
    }

    private var isFailed: Bool {
        if case .failed = item.status { true } else { false }
    }
}

/// Shows the progress of a background activity at the bottom of the sidebar.
private struct ActivityProgressView: View {
    let title: LocalizedStringKey
    let completed: Int
    let total: Int
    var stop: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
            if let stop {
                Button("Stop", systemImage: "xmark.circle.fill", action: stop)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Stop analyzing the remaining images")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
