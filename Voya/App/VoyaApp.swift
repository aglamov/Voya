import SwiftUI
import SwiftData

@main
struct VoyaApp: App {
    @UIApplicationDelegateAdaptor(VoyaAppDelegate.self) private var appDelegate
    @StateObject private var store = VoyaStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .modelContainer(for: [Trip.self, ItineraryItem.self, SourceDocument.self])
        }
    }
}
