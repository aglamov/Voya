import SwiftUI
import SwiftData

@main
struct VoyaApp: App {
    @StateObject private var store = VoyaStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .modelContainer(for: [Trip.self, ItineraryItem.self, SourceDocument.self])
        }
    }
}
