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
final class SourceDocument: Identifiable {
    @Attribute(.unique) var id: UUID
    var sourceName: String
    var fileName: String
    var contentType: String
    var dataBase64: String
    var importedAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sourceName: String,
        fileName: String,
        contentType: String,
        dataBase64: String,
        importedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceName = sourceName
        self.fileName = fileName
        self.contentType = contentType
        self.dataBase64 = dataBase64
        self.importedAt = importedAt
        self.createdAt = createdAt
    }
}

@Model
final class ItineraryItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var kind: ItineraryKind
    var title: String
    var flightNumber: String?
    var location: String
    var status: String
    var startsAt: Date?
    var endsAt: Date?
    var startsAtTimeZoneOffsetSeconds: Int?
    var endsAtTimeZoneOffsetSeconds: Int?
    var sourceName: String?
    var sourceDocumentID: UUID?
    var boardingPassDocumentID: UUID?
    var confirmationCode: String?
    var providerName: String?
    var rawData: String?
    var normalizedData: String?
    var enrichmentCacheKey: String?
    var enrichmentRawData: String?
    var enrichmentUpdatedAt: Date?
    var enrichmentExpiresAt: Date?
    var flightLookupCacheKey: String?
    var flightLookupRawData: String?
    var flightLookupUpdatedAt: Date?
    var flightLookupExpiresAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: ItineraryKind,
        title: String,
        flightNumber: String? = nil,
        location: String,
        status: String,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        startsAtTimeZoneOffsetSeconds: Int? = nil,
        endsAtTimeZoneOffsetSeconds: Int? = nil,
        sourceName: String? = nil,
        sourceDocumentID: UUID? = nil,
        boardingPassDocumentID: UUID? = nil,
        confirmationCode: String? = nil,
        providerName: String? = nil,
        rawData: String? = nil,
        normalizedData: String? = nil,
        enrichmentCacheKey: String? = nil,
        enrichmentRawData: String? = nil,
        enrichmentUpdatedAt: Date? = nil,
        enrichmentExpiresAt: Date? = nil,
        flightLookupCacheKey: String? = nil,
        flightLookupRawData: String? = nil,
        flightLookupUpdatedAt: Date? = nil,
        flightLookupExpiresAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.flightNumber = flightNumber
        self.location = location
        self.status = status
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.startsAtTimeZoneOffsetSeconds = startsAtTimeZoneOffsetSeconds
        self.endsAtTimeZoneOffsetSeconds = endsAtTimeZoneOffsetSeconds
        self.sourceName = sourceName
        self.sourceDocumentID = sourceDocumentID
        self.boardingPassDocumentID = boardingPassDocumentID
        self.confirmationCode = confirmationCode
        self.providerName = providerName
        self.rawData = rawData
        self.normalizedData = normalizedData
        self.enrichmentCacheKey = enrichmentCacheKey
        self.enrichmentRawData = enrichmentRawData
        self.enrichmentUpdatedAt = enrichmentUpdatedAt
        self.enrichmentExpiresAt = enrichmentExpiresAt
        self.flightLookupCacheKey = flightLookupCacheKey
        self.flightLookupRawData = flightLookupRawData
        self.flightLookupUpdatedAt = flightLookupUpdatedAt
        self.flightLookupExpiresAt = flightLookupExpiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTime: String {
        startsAt.map {
            ItineraryDateFormatter.displayTime(
                start: $0,
                end: endsAt,
                startTimeZoneOffsetSeconds: startsAtTimeZoneOffsetSeconds,
                endTimeZoneOffsetSeconds: endsAtTimeZoneOffsetSeconds
            )
        } ?? String(localized: "Time needed")
    }

    var resolvedFlightNumber: String? {
        if let flightNumber {
            let normalizedFlightNumber = flightNumber
                .filter { !$0.isWhitespace }
                .uppercased()
            if !normalizedFlightNumber.isEmpty {
                return normalizedFlightNumber
            }
        }

        let searchableText = "\(title) \(location)".uppercased()
        guard let match = searchableText.firstMatch(of: /[A-Z0-9]{2,3}\s?\d{1,4}[A-Z]?/) else {
            return nil
        }

        return String(match.output)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
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
    @Relationship(deleteRule: .cascade) var sourceDocuments: [SourceDocument]
    var sourceName: String
    var destinationImageURL: URL?
    var destinationImageCredit: String?
    var destinationImageCreditURL: URL?
    var destinationImageProvider: String?
    var destinationImageResolvedAt: Date?
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
        sourceDocuments: [SourceDocument] = [],
        sourceName: String,
        destinationImageURL: URL? = nil,
        destinationImageCredit: String? = nil,
        destinationImageCreditURL: URL? = nil,
        destinationImageProvider: String? = nil,
        destinationImageResolvedAt: Date? = nil,
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
        self.sourceDocuments = sourceDocuments
        self.sourceName = sourceName
        self.destinationImageURL = destinationImageURL
        self.destinationImageCredit = destinationImageCredit
        self.destinationImageCreditURL = destinationImageCreditURL
        self.destinationImageProvider = destinationImageProvider
        self.destinationImageResolvedAt = destinationImageResolvedAt
        self.notes = notes
        self.rawData = rawData
        self.startLocationName = startLocationName
        self.startLocationAddress = startLocationAddress
        self.endLocationName = endLocationName
        self.endLocationAddress = endLocationAddress
    }
}

extension Trip {
    var displayDates: String {
        let dates: [(date: Date, offset: Int?)] = items.flatMap { item in
            [
                item.startsAt.map { ($0, item.startsAtTimeZoneOffsetSeconds) },
                item.endsAt.map { ($0, item.endsAtTimeZoneOffsetSeconds ?? item.startsAtTimeZoneOffsetSeconds) }
            ].compactMap { $0 }
        }
        guard let start = dates.min(by: { $0.date < $1.date }),
              let end = dates.max(by: { $0.date < $1.date }) else {
            let fallbackDates = ItineraryDateParser.dates(from: self.dates)
            guard let fallbackStart = fallbackDates.min(),
                  let fallbackEnd = fallbackDates.max() else {
                return String(localized: "Dates needed")
            }
            return DateIntervalFormatter.localizedDateRange(start: fallbackStart, end: fallbackEnd)
        }

        return DateIntervalFormatter.localizedDateRange(
            start: start.date,
            end: end.date,
            startTimeZoneOffsetSeconds: start.offset,
            endTimeZoneOffsetSeconds: end.offset
        )
    }
}
