import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func tripTitle(for items: [ItineraryItem], fallback: String, preferredDestination: String? = nil) -> String {
        if let destination = destinationName(from: items) {
            return destination
        }

        if let preferredDestination = geographicPlaceName(preferredDestination, excluding: items) {
            return preferredDestination
        }

        if let longestStayPlace = longestStayPlaceName(from: items) {
            return longestStayPlace
        }

        let normalizedFallback = fallback
            .replacingOccurrences(of: "Trip to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Stay at ", with: "", options: .caseInsensitive)

        return geographicPlaceName(normalizedFallback, excluding: items)
            ?? String(localized: "Trip")
    }

    func stableTripDestination(
        current: String?,
        items: [ItineraryItem],
        fallback: String,
        preferredDestination: String? = nil
    ) -> String {
        if let current = normalizedPlaceName(current),
           !matchesKnownVenueName(current, in: items) {
            return current
        }

        return tripTitle(
            for: items,
            fallback: fallback,
            preferredDestination: preferredDestination
        )
    }

    func destinationName(from items: [ItineraryItem]) -> String? {
        if let flight = items.first(where: { $0.kind == .flight }),
           let destination = flightDestination(from: flight.location) {
            return cityName(from: destination)
        }

        if let hotel = items.first(where: { $0.kind == .hotel }) {
            return geographicPlaceName(hotel.location, excluding: items)
        }

        return nil
    }

    func heroImageSearchTerms(for trip: Trip) -> [String] {
        uniquePlaceNames([
            trip.title,
            longestStayPlaceName(from: trip.items),
            firstTripPointName(from: trip.items),
            destinationName(from: trip.items)
        ])
    }

    func firstTripPointName(from items: [ItineraryItem]) -> String? {
        guard let firstItem = items.first else { return nil }

        if firstItem.kind == .flight,
           let destination = flightDestination(from: firstItem.location) {
            return cityName(from: destination)
        }

        return cityName(from: firstItem.location)
    }

    func longestStayPlaceName(from items: [ItineraryItem]) -> String? {
        items
            .compactMap { item -> (place: String, duration: Int)? in
                guard item.kind == .hotel else {
                    return nil
                }

                guard let duration = durationMinutes(for: item),
                      let place = geographicPlaceName(item.location, excluding: items) else {
                    return nil
                }

                return (place, duration)
            }
            .max { $0.duration < $1.duration }
            .map(\.place)
    }

    func placeName(for item: ItineraryItem) -> String? {
        switch item.kind {
        case .flight, .transit:
            if let destination = flightDestination(from: item.location) {
                return cityName(from: destination)
            }
        case .hotel, .event:
            return cityName(from: item.location)
        }

        return normalizedPlaceName(item.location)
    }

    func uniquePlaceNames(_ values: [String?]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap(normalizedPlaceName).filter { value in
            seen.insert(value.lowercased()).inserted
        }
    }

    func tripDates(for items: [ItineraryItem], fallback: String) -> String {
        let storedDates: [(date: Date, offset: Int?)] = items.flatMap { item in
            [
                item.startsAt.map { ($0, item.startsAtTimeZoneOffsetSeconds) },
                item.endsAt.map { ($0, item.endsAtTimeZoneOffsetSeconds ?? item.startsAtTimeZoneOffsetSeconds) }
            ].compactMap { $0 }
        }

        if let first = storedDates.min(by: { $0.date < $1.date }),
           let last = storedDates.max(by: { $0.date < $1.date }) {
            return DateIntervalFormatter.localizedDateRange(
                start: first.date,
                end: last.date,
                startTimeZoneOffsetSeconds: first.offset,
                endTimeZoneOffsetSeconds: last.offset
            )
        }

        return fallback
    }

    func monthAbbreviation(for month: Int?) -> String {
        let monthSymbols = Self.localizedMonthSymbols
        guard let month, monthSymbols.indices.contains(month - 1) else {
            return ""
        }

        return monthSymbols[month - 1]
    }

    static var localizedMonthSymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = VoyaAppLocale.current
        return formatter.shortMonthSymbols
    }

    func summaryText(for trip: Trip) -> String {
        guard !trip.items.isEmpty else {
            return String(localized: "No confirmed items yet")
        }

        return String(localized: "\(trip.items.count) confirmed item\(trip.items.count == 1 ? "" : "s") in one travel chain")
    }

    func summaryText(itemCount: Int, sourceName: String) -> String {
        String(localized: "\(itemCount) confirmed item\(itemCount == 1 ? "" : "s") from \(sourceName)")
    }

    func combinedSourceName(_ existing: String, _ incoming: String) -> String {
        existing.localizedCaseInsensitiveContains(incoming) ? existing : "\(existing) + \(incoming)"
    }

    func placeTokens(for items: [ItineraryItem]) -> Set<String> {
        let ignoredWords: Set<String> = [
            "airport", "terminal", "hotel", "flight", "check", "needed", "confirmed",
            "the", "and", "from", "with", "to", "at", "in", "on"
        ]

        return Set(
            items
                .flatMap { [$0.title, $0.location] }
                .flatMap { value in
                    value
                        .lowercased()
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { $0.count > 2 && !ignoredWords.contains($0) }
                }
        )
    }

    func dateKeys(for item: ItineraryItem) -> [String] {
        guard let startsAt = item.startsAt else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ItineraryDateFormatter.timeZone(
            offsetSeconds: item.startsAtTimeZoneOffsetSeconds
        )
        let end = item.endsAt ?? startsAt
        let startOfStart = calendar.startOfDay(for: startsAt)
        let startOfEnd = calendar.startOfDay(for: end)
        let dayCount = min(calendar.dateComponents([.day], from: startOfStart, to: startOfEnd).day ?? 0, 30)

        return (0...max(0, dayCount)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfStart).flatMap {
                dateKey(for: $0, calendar: calendar)
            }
        }
    }

    func dateKey(for date: Date, calendar: Calendar = .current) -> String? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return "\(year)-\(month)-\(day)"
    }

    func dateRangesAreNear(_ firstItems: [ItineraryItem], _ secondItems: [ItineraryItem]) -> Bool {
        guard let firstRange = overallDateRange(for: firstItems),
              let secondRange = overallDateRange(for: secondItems) else {
            return false
        }

        let tolerance: TimeInterval = 36 * 60 * 60
        return firstRange.start <= secondRange.end.addingTimeInterval(tolerance)
            && secondRange.start <= firstRange.end.addingTimeInterval(tolerance)
    }

    func overallDateRange(for items: [ItineraryItem]) -> (start: Date, end: Date)? {
        let dates = items.flatMap { item in
            [item.startsAt, item.endsAt].compactMap { $0 }
        }

        guard let start = dates.min(), let end = dates.max() else {
            return nil
        }

        return (start, end)
    }

    func durationMinutes(for item: ItineraryItem) -> Int? {
        guard let startsAt = item.startsAt,
              let endsAt = item.endsAt else {
            return nil
        }

        return max(0, Int(endsAt.timeIntervalSince(startsAt) / 60))
    }

    func cityName(from location: String) -> String {
        if let airportCode = location
            .uppercased()
            .split(whereSeparator: { !$0.isLetter })
            .last(where: { $0.count == 3 }),
           let city = Self.airportCities[String(airportCode)] {
            return city
        }

        let suffixes = [
            " Fiumicino", " Heathrow", " Gatwick", " Airport", " Terminal 1",
            " Terminal 2", " Terminal 3", " Terminal 4", " Terminal 5"
        ]

        return suffixes.reduce(location) { result, suffix in
            result.replacingOccurrences(of: suffix, with: "", options: .caseInsensitive)
        }
        .replacingOccurrences(of: #".*,\s*\d{4,6}\s+([^,]+),.*"#, with: "$1", options: .regularExpression)
        .replacingOccurrences(of: #"\s*\([A-Z]{3}\)"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    func normalizedPlaceName(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = cityName(from: value)
            .replacingOccurrences(of: "Trip to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Stay at ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        return normalized.isEmpty ? nil : normalized
    }

    func geographicPlaceName(_ value: String?, excluding items: [ItineraryItem]) -> String? {
        guard let place = normalizedPlaceName(value),
              !isSpecificVenueName(place, in: items) else {
            return nil
        }

        return place
    }

    private func isSpecificVenueName(_ value: String, in items: [ItineraryItem]) -> Bool {
        let normalizedValue = comparablePlaceName(value)
        guard !normalizedValue.isEmpty else { return true }

        if matchesKnownVenueName(value, in: items) {
            return true
        }

        let venueWords: Set<String> = [
            "hotel", "hostel", "resort", "inn", "suites", "apartment", "apartments",
            "отель", "гостиница", "хостел", "апартаменты"
        ]
        let words = Set(normalizedValue.split(separator: " ").map(String.init))
        return !words.isDisjoint(with: venueWords)
    }

    private func matchesKnownVenueName(_ value: String, in items: [ItineraryItem]) -> Bool {
        let normalizedValue = comparablePlaceName(value)
        guard !normalizedValue.isEmpty else { return false }

        let venueNames = items
            .filter { $0.kind == .hotel || $0.kind == .event }
            .flatMap { [$0.title, $0.providerName] }
            .compactMap { $0 }
            .map(comparablePlaceName)
            .filter { !$0.isEmpty }

        return venueNames.contains(where: {
            $0 == normalizedValue
                || ($0.count >= 5 && normalizedValue.contains($0))
        })
    }

    private func comparablePlaceName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func flightDestination(from location: String) -> String? {
        let normalized = location
            .replacingOccurrences(of: "→", with: " to ")
            .replacingOccurrences(of: "–", with: " to ")
        let parts = normalized.components(separatedBy: " to ")
        guard parts.count > 1 else { return nil }
        return parts.last?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static let airportCities: [String: String] = [
        "LTN": "London",
        "LHR": "London",
        "LGW": "London",
        "STN": "London",
        "LCY": "London"
    ]
}
