//
//  ImageTaggerApp.swift
//  ImageTagger
//
//  Created by Denis-Cosmin Nutiu on 25/10/2026.
//

import SwiftUI

@main
struct ImageTaggerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Window("ImageTagger", id: "main") {
            ContentView()
                .environment(appDelegate.session)
                .task {
                    // Load the model in the background so the first analysis starts quickly.
                    _ = TagPredictor.shared
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            ImageTaggerCommands(session: appDelegate.session)
            SidebarCommands()
            InspectorCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = TaggingSession()

    /// Adds images and folders opened from Finder or dropped on the app's Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { await session.add(urls) }
    }

    /// ImageTagger is a single-window app, so it quits when its window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
