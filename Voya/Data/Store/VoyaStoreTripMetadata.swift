import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func tripTitle(for items: [ItineraryItem], fallback: String, preferredDestination: String? = nil) -> String {
        if let longestStayPlace = longestStayPlaceName(from: items) {
            return longestStayPlace
        }

        if let destination = destinationName(from: items) {
            return destination
        }

        if let preferredDestination = normalizedPlaceName(preferredDestination), !preferredDestination.isEmpty {
            return preferredDestination
        }

        return fallback
            .replacingOccurrences(of: "Trip to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Stay at ", with: "", options: .caseInsensitive)
    }

    func destinationName(from items: [ItineraryItem]) -> String? {
        if let flight = items.first(where: { $0.kind == .flight }),
           let destination = flight.location.components(separatedBy: " to ").last {
            return cityName(from: destination)
        }

        if let hotel = items.first(where: { $0.kind == .hotel }) {
            return cityName(from: hotel.location)
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
           let destination = firstItem.location.components(separatedBy: " to ").last {
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
                      let place = placeName(for: item) else {
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
            if let destination = item.location.components(separatedBy: " to ").last {
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
        let storedDates = items.flatMap { item in
            [item.startsAt, item.endsAt].compactMap { $0 }
        }

        if let first = storedDates.min(),
           let last = storedDates.max() {
            return tripDates(from: first, to: last)
        }

        return fallback
    }

    func tripDates(from start: Date, to end: Date) -> String {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.month, .day], from: start)
        let endComponents = calendar.dateComponents([.month, .day], from: end)
        let startMonth = monthAbbreviation(for: startComponents.month)
        let endMonth = monthAbbreviation(for: endComponents.month)
        let startDay = startComponents.day ?? 1
        let endDay = endComponents.day ?? startDay

        guard startComponents.month != endComponents.month || startDay != endDay else {
            return DateIntervalFormatter.localizedDateRange(month: startMonth, day: startDay)
        }

        if startComponents.month == endComponents.month {
            return DateIntervalFormatter.localizedDateRange(month: startMonth, startDay: startDay, endDay: endDay)
        }

        return DateIntervalFormatter.localizedDateRange(startMonth: startMonth, startDay: startDay, endMonth: endMonth, endDay: endDay)
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
        formatter.locale = .autoupdatingCurrent
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
        let calendar = Calendar.current
        let end = item.endsAt ?? startsAt
        let startOfStart = calendar.startOfDay(for: startsAt)
        let startOfEnd = calendar.startOfDay(for: end)
        let dayCount = min(calendar.dateComponents([.day], from: startOfStart, to: startOfEnd).day ?? 0, 30)

        return (0...max(0, dayCount)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfStart).flatMap(dateKey)
        }
    }

    func dateKey(for date: Date) -> String? {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return nil }
        return "\(month)-\(day)"
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
}
