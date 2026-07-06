import Foundation
import SwiftData
import SwiftUI

@MainActor
final class VoyaStore: ObservableObject {
    static let pastedConfirmationSourceName = String(localized: "Pasted confirmation")

    var modelContext: ModelContext?

    @Published var inspirationText = String(localized: "Warm 4-day trip under $700 with easy transit")
    @Published var selectedMood: TripMood = .warm
    @Published var importText = ""
    @Published var extractedPreview: ExtractionPreview?
    @Published var importedDocuments: [ImportedDocument] = []
    @Published var trips: [Trip] = []
    @Published var selectedTripID: UUID?
    @Published var importMessage: String?
    @Published var importSuccess: ImportSuccess?
    @Published var importPreparationStatus: ImportPreparationStatus?
    @Published var isExtractingConfirmation = false
    @Published var isConfirmingExtraction = false
    @Published var assistantIntelligenceCache: [String: AssistantIntelligence] = [:]
    @Published var refreshingAssistantIntelligenceKeys: Set<String> = []

    var selectedTrip: Trip? {
        guard let selectedTripID else { return trips.first }
        return trips.first { $0.id == selectedTripID } ?? trips.first
    }

    var activeTrips: [Trip] {
        activeTrips(at: Date())
    }

    var archivedTrips: [Trip] {
        archivedTrips(at: Date())
    }

    var currentOrUpcomingTrip: Trip? {
        currentOrUpcomingTrip(at: Date())
    }

    let recommendations = SampleData.recommendations

    var itinerary: [ItineraryItem] {
        selectedTrip.map { sortedItinerary($0.items) } ?? []
    }

    func itinerary(for trip: Trip) -> [ItineraryItem] {
        sortedItinerary(trip.items)
    }
}
