import SwiftUI

@main
struct VoyaApp: App {
    @StateObject private var store = VoyaStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
