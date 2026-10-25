//
//  ContentView.swift
//  ImageTagger
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(TaggingSession.self) private var session
    @State private var isInspectorPresented = true
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var session = session

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        } detail: {
            DetailView()
        }
        .inspector(isPresented: $isInspectorPresented) {
            InspectorView()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .navigationTitle(session.selectedItem?.fileName ?? "ImageTagger")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Images", systemImage: "plus") {
                    session.isImporterPresented = true
                }
                .help("Add images or folders to tag")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save Tags", systemImage: "square.and.arrow.down.on.square") {
                    session.isConfirmingSaveAll = true
                }
                .disabled(session.itemsWithUnsavedTags.isEmpty)
                .help("Save the tags of all images to their files")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Inspector", systemImage: "sidebar.trailing") {
                    isInspectorPresented.toggle()
                }
                .help(isInspectorPresented ? "Hide the inspector" : "Show the inspector")
            }
        }
        .fileImporter(
            isPresented: $session.isImporterPresented,
            allowedContentTypes: [.image, .folder],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await session.add(urls) }
        }
        .fileDialogMessage("Choose images or folders to tag.")
        .fileDialogConfirmationLabel("Add")
        .dropDestination(for: URL.self) { urls, _ in
            guard TaggingSession.containsImagesOrFolders(urls) else { return false }
            Task { await session.add(urls) }
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .alert(isPresented: $session.isShowingModelLoadingError, error: session.modelLoadingError) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.recoverySuggestion ?? "")
        }
        .alert(isPresented: $session.isShowingTagSavingError, error: session.tagSavingError) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.recoverySuggestion ?? "")
        }
        .confirmationDialog(
            "Save tags to ^[\(session.itemsWithUnsavedTags.count) image](inflect: true)?",
            isPresented: $session.isConfirmingSaveAll
        ) {
            Button("Save Tags") {
                Task { await session.saveTags(of: session.itemsWithUnsavedTags) }
            }
        } message: {
            Text("The tags are added to the keywords stored in each file, or in an XMP sidecar file for RAW images. Existing keywords are kept.")
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var subtitle: Text {
        session.items.isEmpty ? Text(verbatim: "") : Text("^[\(session.items.count) image](inflect: true)")
    }
}

#Preview {
    ContentView()
        .environment(TaggingSession())
}
