//
//  SettingsView.swift
//  ImageTagger
//

import SwiftUI

/// The app's settings window.
struct SettingsView: View {
    @AppStorage(TaggingSession.savesTagsAutomaticallyKey) private var savesTagsAutomatically = false
    @AppStorage(TagFormat.storageKey) private var tagFormat = TagFormat.comma

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $savesTagsAutomatically) {
                    Text("Save tags to image files automatically")
                    Text("After an image is analyzed, its tags are added to the keywords stored in the file, or in an XMP sidecar file for RAW images. Existing keywords are kept. Works with JPEG, HEIC, TIFF and RAW images.")
                }
            }
            Section {
                Picker("Tag format", selection: $tagFormat) {
                    ForEach(TagFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
            } footer: {
                Text("The format used to display and copy tags.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView()
}
