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
                .task {
                    guard ProcessInfo.processInfo.arguments.contains("--voya-live-flight-alert-test") else {
                        return
                    }
                    let result = await VoyaPushRegistrationService.shared.startFlightAlertSelfTest()
                    print("[Voya] Live flight alert test: \(result.status) \(result.flightNumber ?? "") \(result.error ?? "")")
                }
        }
    }
}
