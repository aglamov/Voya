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
    @State private var selectedTab: VoyaTab = .inspire

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()
                .ignoresSafeArea()

            Group {
                switch selectedTab {
                case .inspire:
                    InspireView()
                case .trips:
                    TripsView()
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
    }
}

enum VoyaTab: String, CaseIterable, Identifiable {
    case inspire = "Inspire"
    case trips = "Trips"
    case `import` = "Import"
    case assistant = "Assistant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inspire: String(localized: "Inspire")
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
