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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: VoyaStore
    @State private var selectedTab: VoyaTab = .inspire
    @State private var pendingNotificationDestination: VoyaNotificationDestination?

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()
                .ignoresSafeArea()

            Group {
                switch selectedTab {
                case .inspire:
                    InspireView(selectedTab: $selectedTab)
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
            if let destination = VoyaNotificationScheduler.shared.takePendingDestination() {
                queueNotification(destination)
            } else if store.selectCurrentTripIfAvailable() {
                selectedTab = .trips
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            openPendingNotificationAfterActivation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .voyaPushDeviceTokenDidChange)) { _ in
            Task {
                await VoyaPushRegistrationService.shared.syncTripWatches(for: store.trips, force: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voyaNotificationOpened)) { notification in
            if let destination = VoyaNotificationScheduler.shared.takePendingDestination()
                ?? notification.userInfo?["destination"] as? VoyaNotificationDestination {
                queueNotification(destination)
            }
        }
    }

    private func queueNotification(_ destination: VoyaNotificationDestination) {
        pendingNotificationDestination = destination
        guard scenePhase == .active else { return }
        openPendingNotificationAfterActivation()
    }

    private func openPendingNotificationAfterActivation() {
        Task { @MainActor in
            // Notification responses can arrive while SwiftUI is restoring the scene.
            // Presenting a sheet during that transaction can leave UIKit's presenter stuck.
            await Task.yield()
            guard scenePhase == .active,
                  let destination = pendingNotificationDestination else {
                return
            }
            pendingNotificationDestination = nil
            openNotification(destination)
        }
    }

    private func openNotification(_ destination: VoyaNotificationDestination) {
        if destination.eventType == "inspiration_ready" {
            selectedTab = .inspire
            Task { await store.refreshInspiration() }
            return
        }
        if destination.eventType == "mission_result" {
            selectedTab = .assistant
            Task { await store.refreshAgentMissions() }
            return
        }
        selectedTab = .trips

        if let transferID = destination.transferID {
            if let tripID = destination.tripID,
               store.trips.contains(where: { $0.id == tripID }) {
                store.selectedTripID = tripID
            } else {
                _ = store.selectCurrentTripIfAvailable()
            }
            store.notificationItemID = nil
            store.notificationTransferID = transferID
        } else if let itemID = destination.itemID,
           let trip = store.trips.first(where: { trip in trip.items.contains(where: { $0.id == itemID }) }) {
            store.selectedTripID = trip.id
            store.notificationTransferID = nil
            store.notificationItemID = itemID
        } else if let tripID = destination.tripID,
                  store.trips.contains(where: { $0.id == tripID }) {
            store.selectedTripID = tripID
            store.notificationItemID = nil
            store.notificationTransferID = nil
        } else {
            store.notificationItemID = nil
            store.notificationTransferID = nil
            _ = store.selectCurrentTripIfAvailable()
        }
    }
}

enum VoyaTab: String, CaseIterable, Identifiable {
    case inspire = "Inspiration"
    case trips = "Trips"
    case `import` = "Import"
    case assistant = "Assistant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inspire: String(localized: "Inspiration")
        case .trips: String(localized: "Trips")
        case .import: String(localized: "Import")
        case .assistant: String(localized: "Assistant")
        }
    }

    var symbol: String {
        switch self {
        case .inspire: "sparkles"
        case .trips: "calendar"
        case .import: "tray.and.arrow.down"
        case .assistant: "message.badge"
        }
    }
}
