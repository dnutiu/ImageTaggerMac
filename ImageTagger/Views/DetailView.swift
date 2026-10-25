//
//  DetailView.swift
//  ImageTagger
//

import SwiftUI

/// Shows the selected image, or an empty state.
struct DetailView: View {
    @Environment(TaggingSession.self) private var session

    var body: some View {
        if session.items.isEmpty {
            ContentUnavailableView {
                Label("No Images", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Add photos to generate keywords for them. You can also drag images or folders here.")
            } actions: {
                Button("Add Images…") {
                    session.isImporterPresented = true
                }
            }
        } else if let item = session.selectedItem {
            ImagePreview(item: item)
        } else {
            ContentUnavailableView(
                "No Image Selected",
                systemImage: "photo",
                description: Text("Select an image in the sidebar to see its tags.")
            )
        }
    }
}

private struct ImagePreview: View {
    /// The pixel size of the preview, large enough for a full-screen window.
    private static let previewPixelSize = 3072

    @Environment(TaggingSession.self) private var session
    let item: ImageItem
    @State private var image: CGImage?

    var body: some View {
        Group {
            if case .failed(let message) = item.status {
                ContentUnavailableView {
                    Label("Can’t Analyze “\(item.fileName)”", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            } else if let image = image ?? item.thumbnail {
                Image(image, scale: 1, label: Text(item.fileName))
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                    .onTapGesture(count: 2) {
                        session.open(item)
                    }
                    .accessibilityAction(named: "Open with Default App") {
                        session.open(item)
                    }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottom) {
            if item.isInProgress {
                Label {
                    Text("Analyzing…")
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect()
                .padding(.bottom, 36)
            }
        }
        .task(id: item.id) {
            image = nil
            image = try? await ImageLoader.image(at: item.url, maxPixelSize: Self.previewPixelSize)
        }
    }
}
