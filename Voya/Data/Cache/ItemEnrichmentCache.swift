import Foundation
import SwiftData
import SwiftUI

enum ItemEnrichmentCache {
    private static let schemaVersion = "travel-brief-v6"

    static func key(for item: ItineraryItem) -> String {
        let dateFormatter = ISO8601DateFormatter()
        return [
            schemaVersion,
            VoyaAppLocale.currentIdentifier,
            item.kind.rawValue,
            normalized(item.title),
            normalized(item.location),
            normalized(item.status),
            item.startsAt.map { dateFormatter.string(from: $0) } ?? "",
            item.endsAt.map { dateFormatter.string(from: $0) } ?? ""
        ].joined(separator: "|")
    }

    static func freshCachedEnrichment(for item: ItineraryItem, now: Date = Date()) -> ItemEnrichment? {
        guard item.enrichmentCacheKey == key(for: item),
              let expiresAt = item.enrichmentExpiresAt,
              expiresAt > now else {
            return nil
        }

        return cachedEnrichment(for: item)
    }

    static func cachedEnrichment(for item: ItineraryItem) -> ItemEnrichment? {
        guard let rawData = item.enrichmentRawData,
              let data = rawData.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(ItemEnrichment.self, from: data)
    }

    static func clear(for item: ItineraryItem) {
        item.enrichmentCacheKey = nil
        item.enrichmentRawData = nil
        item.enrichmentUpdatedAt = nil
        item.enrichmentExpiresAt = nil
    }

    static func store(_ enrichment: ItemEnrichment, for item: ItineraryItem, now: Date = Date()) {
        guard let data = try? JSONEncoder().encode(enrichment),
              let rawData = String(data: data, encoding: .utf8) else {
            return
        }

        item.enrichmentCacheKey = key(for: item)
        item.enrichmentRawData = rawData
        item.enrichmentUpdatedAt = now
        item.enrichmentExpiresAt = expirationDate(for: item, now: now)
    }

    private static func expirationDate(for item: ItineraryItem, now: Date) -> Date {
        guard let startsAt = item.startsAt else {
            return now.addingTimeInterval(60 * 60)
        }

        if startsAt < now {
            return now.addingTimeInterval(60 * 60 * 24)
        }

        let secondsUntilStart = startsAt.timeIntervalSince(now)
        if secondsUntilStart <= 60 * 60 * 24 {
            return now.addingTimeInterval(60 * 30)
        }
        if secondsUntilStart <= 60 * 60 * 24 * 7 {
            return now.addingTimeInterval(60 * 60 * 3)
        }

        return now.addingTimeInterval(60 * 60 * 12)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}
