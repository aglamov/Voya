import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: VoyaStore
    @State private var selectedTab: VoyaTab = .trips

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()
                .ignoresSafeArea()

            Group {
                switch selectedTab {
                case .trips:
                    TripsView(selectedTab: $selectedTab)
                case .import:
                    ImportView(selectedTab: $selectedTab)
                case .assistant:
                    AssistantView()
                }
            }
            .safeAreaPadding(.bottom, 92)

            VoyaTabBar(selectedTab: $selectedTab)
        }
        .tint(.voyaTeal)
        .preferredColorScheme(.light)
        .onAppear {
            store.configure(modelContext: modelContext)
            if store.selectCurrentTripIfAvailable() {
                selectedTab = .trips
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voyaPushDeviceTokenDidChange)) { _ in
            Task {
                await VoyaPushRegistrationService.shared.syncTripWatches(for: store.trips, force: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voyaNotificationOpened)) { notification in
            selectedTab = .trips
            if let rawTripID = notification.userInfo?["tripID"] as? String,
               let tripID = UUID(uuidString: rawTripID),
               store.trips.contains(where: { $0.id == tripID }) {
                store.selectedTripID = tripID
            } else if let rawItemID = notification.userInfo?["itemID"] as? String,
                      let itemID = UUID(uuidString: rawItemID),
                      let trip = store.trips.first(where: { trip in trip.items.contains(where: { $0.id == itemID }) }) {
                store.selectedTripID = trip.id
            } else {
                _ = store.selectCurrentTripIfAvailable()
            }
            if let rawItemID = notification.userInfo?["itemID"] as? String {
                store.notificationItemID = UUID(uuidString: rawItemID)
            }
        }
    }
}

enum VoyaTab: String, CaseIterable, Identifiable {
    case trips = "Trips"
    case `import` = "Import"
    case assistant = "Assistant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trips: String(localized: "Trips")
        case .import: String(localized: "Import")
        case .assistant: String(localized: "Assistant")
        }
    }

    var symbol: String {
        switch self {
        case .trips: "calendar"
        case .import: "tray.and.arrow.down"
        case .assistant: "message.badge"
        }
    }
}
