import Foundation
import SwiftData
import SwiftUI

enum TripMood: String, CaseIterable, Identifiable {
    case warm = "Warm"
    case food = "Food"
    case culture = "Culture"
    case events = "Events"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warm: String(localized: "Warm")
        case .food: String(localized: "Food")
        case .culture: String(localized: "Culture")
        case .events: String(localized: "Events")
        }
    }
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

enum ItineraryKind: String, CaseIterable, Codable, Sendable {
    case flight = "Flight"
    case hotel = "Hotel"
    case event = "Event"
    case transit = "Transit"

    var displayName: String {
        switch self {
        case .flight: String(localized: "Flight")
        case .hotel: String(localized: "Hotel")
        case .event: String(localized: "Event")
        case .transit: String(localized: "Transit")
        }
    }

    var symbol: String {
        switch self {
        case .flight: "airplane"
        case .hotel: "bed.double"
        case .event: "ticket"
        case .transit: "tram"
        }
    }
}

@Model
final class ItineraryItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var kind: ItineraryKind
    var title: String
    var location: String
    var status: String
    var startsAt: Date?
    var endsAt: Date?
    var sourceName: String?
    var sourceDocumentID: UUID?
    var confirmationCode: String?
    var providerName: String?
    var rawData: String?
    var normalizedData: String?
    var enrichmentCacheKey: String?
    var enrichmentRawData: String?
    var enrichmentUpdatedAt: Date?
    var enrichmentExpiresAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: ItineraryKind,
        title: String,
        location: String,
        status: String,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        sourceName: String? = nil,
        sourceDocumentID: UUID? = nil,
        confirmationCode: String? = nil,
        providerName: String? = nil,
        rawData: String? = nil,
        normalizedData: String? = nil,
        enrichmentCacheKey: String? = nil,
        enrichmentRawData: String? = nil,
        enrichmentUpdatedAt: Date? = nil,
        enrichmentExpiresAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.location = location
        self.status = status
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.sourceName = sourceName
        self.sourceDocumentID = sourceDocumentID
        self.confirmationCode = confirmationCode
        self.providerName = providerName
        self.rawData = rawData
        self.normalizedData = normalizedData
        self.enrichmentCacheKey = enrichmentCacheKey
        self.enrichmentRawData = enrichmentRawData
        self.enrichmentUpdatedAt = enrichmentUpdatedAt
        self.enrichmentExpiresAt = enrichmentExpiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTime: String {
        startsAt.map { ItineraryDateFormatter.displayTime(start: $0, end: endsAt) } ?? String(localized: "Time needed")
    }
}

@Model
final class Trip: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var dates: String
    var summary: String
    var destination: String?
    var startsAt: Date?
    var endsAt: Date?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var items: [ItineraryItem]
    var sourceName: String
    var destinationImageURL: URL?
    var destinationImageCredit: String?
    var notes: String?
    var rawData: String?
    var startLocationName: String?
    var startLocationAddress: String?
    var endLocationName: String?
    var endLocationAddress: String?

    init(
        id: UUID = UUID(),
        title: String,
        dates: String,
        summary: String,
        destination: String? = nil,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        items: [ItineraryItem],
        sourceName: String,
        destinationImageURL: URL? = nil,
        destinationImageCredit: String? = nil,
        notes: String? = nil,
        rawData: String? = nil,
        startLocationName: String? = nil,
        startLocationAddress: String? = nil,
        endLocationName: String? = nil,
        endLocationAddress: String? = nil
    ) {
        self.id = id
        self.title = title
        self.dates = dates
        self.summary = summary
        self.destination = destination
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = items
        self.sourceName = sourceName
        self.destinationImageURL = destinationImageURL
        self.destinationImageCredit = destinationImageCredit
        self.notes = notes
        self.rawData = rawData
        self.startLocationName = startLocationName
        self.startLocationAddress = startLocationAddress
        self.endLocationName = endLocationName
        self.endLocationAddress = endLocationAddress
    }
}
