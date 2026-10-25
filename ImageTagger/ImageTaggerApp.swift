//
//  ImageTaggerApp.swift
//  ImageTagger
//
//  Created by Denis-Cosmin Nutiu on 25/10/2026.
//

import SwiftUI
import CoreData

@main
struct ImageTaggerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
