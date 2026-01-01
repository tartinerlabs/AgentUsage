//
//  ClaudeMeter_iOSApp.swift
//  ClaudeMeter-iOS
//
//  Created by Ru Chern Chong on 1/1/26.
//

import SwiftUI
import SwiftData

@main
struct ClaudeMeter_iOSApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
