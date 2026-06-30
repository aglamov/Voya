import Foundation
import SwiftUI

enum TripMood: String, CaseIterable, Identifiable {
    case warm = "Warm"
    case food = "Food"
    case culture = "Culture"
    case events = "Events"

    var id: String { rawValue }
}

struct TripRecommendation: Identifiable {
    let id = UUID()
    let destination: String
    let dates: String
    let fit: String
    let estimatedCost: String
    let details: [String]
    let accent: Color
}

enum ItineraryKind: String {
    case flight = "Flight"
    case hotel = "Hotel"
    case event = "Event"
    case transit = "Transit"

    var symbol: String {
        switch self {
        case .flight: "airplane"
        case .hotel: "bed.double"
        case .event: "ticket"
        case .transit: "tram"
        }
    }
}

struct ItineraryItem: Identifiable {
    let id = UUID()
    let kind: ItineraryKind
    let title: String
    let time: String
    let location: String
    let status: String
}

struct TravelAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let severity: AlertSeverity
}

enum AlertSeverity {
    case calm
    case watch
    case action

    var color: Color {
        switch self {
        case .calm: .teal
        case .watch: .orange
        case .action: .red
        }
    }
}

struct ExtractionPreview {
    var type: String
    var title: String
    var primaryTime: String
    var confidence: Double
    var fields: [(String, String)]
}

final class VoyaStore: ObservableObject {
    @Published var inspirationText = "Warm 4-day trip under $700 with easy transit"
    @Published var selectedMood: TripMood = .warm
    @Published var importText = "BA2490 London Heathrow to Rome Fiumicino, Aug 12, 09:40. Hotel Artemide check-in Aug 12."
    @Published var extractedPreview: ExtractionPreview?

    let recommendations = SampleData.recommendations
    let itinerary = SampleData.itinerary
    let alerts = SampleData.alerts

    func runMockExtraction() {
        extractedPreview = ExtractionPreview(
            type: "Flight + hotel",
            title: "London to Rome",
            primaryTime: "Aug 12, 09:40",
            confidence: 0.91,
            fields: [
                ("Flight", "BA2490"),
                ("From", "London Heathrow"),
                ("To", "Rome Fiumicino"),
                ("Hotel", "Hotel Artemide"),
                ("Review", "Confirm airport terminal before saving")
            ]
        )
    }
}
