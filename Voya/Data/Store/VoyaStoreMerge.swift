import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func suggestedImportTripID(for incomingItems: [ItineraryItem]) -> UUID? {
        guard let incomingRange = overallDateRange(for: incomingItems) else {
            return nil
        }

        return trips.compactMap { trip -> (id: UUID, distance: TimeInterval, isSelected: Bool)? in
            guard let tripRange = overallDateRange(for: trip.items),
                  dateRangesAreNear(incomingItems, trip.items) else {
                return nil
            }

            let distance: TimeInterval
            if incomingRange.start <= tripRange.end, tripRange.start <= incomingRange.end {
                distance = 0
            } else {
                distance = min(
                    abs(incomingRange.start.timeIntervalSince(tripRange.end)),
                    abs(tripRange.start.timeIntervalSince(incomingRange.end))
                )
            }

            return (trip.id, distance, trip.id == selectedTripID)
        }
        .min { first, second in
            if first.distance != second.distance {
                return first.distance < second.distance
            }
            return first.isSelected && !second.isSelected
        }?
        .id
    }

    func tripIndexForMerge(with incomingItems: [ItineraryItem]) -> Int? {
        if let selectedTripID,
           let selectedIndex = trips.firstIndex(where: { $0.id == selectedTripID }),
           shouldMerge(incomingItems, into: trips[selectedIndex], allowDateOnlyMatch: true) {
            return selectedIndex
        }

        return trips.indices.first { index in
            shouldMerge(incomingItems, into: trips[index], allowDateOnlyMatch: false)
        }
    }

    func shouldMerge(_ incomingItems: [ItineraryItem], into trip: Trip, allowDateOnlyMatch: Bool) -> Bool {
        let incomingDates = Set(incomingItems.flatMap(dateKeys))
        let tripDates = Set(trip.items.flatMap(dateKeys))
        let sharesDate = !incomingDates.isDisjoint(with: tripDates)
        let hasNearbyDates = dateRangesAreNear(incomingItems, trip.items)

        let incomingPlaces = placeTokens(for: incomingItems)
        let tripPlaces = placeTokens(for: trip.items)
        let sharesPlace = !incomingPlaces.isDisjoint(with: tripPlaces)
        let complementaryKinds = hasComplementaryTravelKinds(incomingItems, trip.items)

        return (sharesDate || hasNearbyDates) && (sharesPlace || allowDateOnlyMatch || complementaryKinds)
    }

    func hasComplementaryTravelKinds(_ incomingItems: [ItineraryItem], _ tripItems: [ItineraryItem]) -> Bool {
        let incomingKinds = Set(incomingItems.map(\.kind))
        let tripKinds = Set(tripItems.map(\.kind))

        return (incomingKinds.contains(.flight) && tripKinds.contains(.hotel))
            || (incomingKinds.contains(.hotel) && tripKinds.contains(.flight))
    }

    func deduplicatedItems(from items: [ItineraryItem]) -> (unique: [ItineraryItem], duplicates: [ItineraryItem]) {
        var unique: [ItineraryItem] = []
        var duplicates: [ItineraryItem] = []

        for item in items {
            if let existingIndex = unique.firstIndex(where: { areDuplicateItems($0, item) }) {
                let existing = unique[existingIndex]
                if duplicatePreferenceScore(for: item) > duplicatePreferenceScore(for: existing) {
                    unique[existingIndex] = item
                    duplicates.append(existing)
                } else {
                    duplicates.append(item)
                }
            } else {
                unique.append(item)
            }
        }

        return (unique, duplicates)
    }

    func duplicatePreferenceScore(for item: ItineraryItem) -> Int {
        normalizedKeyText(item.location).count
            + (item.status.localizedCaseInsensitiveContains("needs") ? 0 : 50)
            + (item.confirmationCode?.isEmpty == false ? 25 : 0)
            + (item.normalizedData?.isEmpty == false ? 15 : 0)
            + (item.flightLookupRawData?.isEmpty == false ? 15 : 0)
    }

    func areDuplicateItems(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        guard first.kind == second.kind else { return false }

        switch first.kind {
        case .flight:
            return duplicateFlight(first, second)
        case .hotel:
            return duplicateHotel(first, second)
        case .transit, .event:
            return duplicateGeneralItem(first, second)
        }
    }

    func duplicateFlight(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        let firstFlightNumbers = Set([first.resolvedFlightNumber].compactMap { $0 })
        let secondFlightNumbers = Set([second.resolvedFlightNumber].compactMap { $0 })
        let sharesFlightNumber = !firstFlightNumbers.isEmpty && !firstFlightNumbers.isDisjoint(with: secondFlightNumbers)
        let sameRoute = routeKey(for: first.location) == routeKey(for: second.location)

        guard sharesFlightNumber && sameRoute else { return false }
        return sameTravelDay(first, second) || timesAreClose(first.startsAt, second.startsAt, tolerance: 6 * 60 * 60)
    }

    func duplicateHotel(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        let sameName = normalizedKeyText(first.title) == normalizedKeyText(second.title)
        let samePlace = !placeTokens(for: [first]).isDisjoint(with: placeTokens(for: [second]))
            || normalizedKeyText(first.location) == normalizedKeyText(second.location)

        guard sameName && samePlace else { return false }
        return dateRangesOverlap(first, second) || sameTravelDay(first, second)
    }

    func duplicateGeneralItem(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        normalizedKeyText(first.title) == normalizedKeyText(second.title)
            && normalizedKeyText(first.location) == normalizedKeyText(second.location)
            && (sameTravelDay(first, second) || timesAreClose(first.startsAt, second.startsAt, tolerance: 2 * 60 * 60))
    }

    func flightNumbers(in value: String) -> Set<String> {
        let pattern = #"\b[A-Z0-9]{2}\s?\d{2,4}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(value.startIndex..., in: value)
        return Set(
            regex.matches(in: value, range: range).compactMap { match in
                Range(match.range, in: value).map {
                    value[$0].uppercased().replacingOccurrences(of: " ", with: "")
                }
            }
        )
    }

    func routeKey(for location: String) -> String {
        normalizedKeyText(location)
            .replacingOccurrences(of: #"(^|\s)(from|to)($|\s)"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sameTravelDay(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        guard let firstDate = first.startsAt, let secondDate = second.startsAt else {
            return false
        }

        return Calendar.current.isDate(firstDate, inSameDayAs: secondDate)
    }

    func timesAreClose(_ first: Date?, _ second: Date?, tolerance: TimeInterval) -> Bool {
        guard let first, let second else { return false }
        return abs(first.timeIntervalSince(second)) <= tolerance
    }

    func dateRangesOverlap(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        guard let firstStart = first.startsAt, let secondStart = second.startsAt else {
            return false
        }

        let firstEnd = first.endsAt ?? firstStart
        let secondEnd = second.endsAt ?? secondStart
        return firstStart <= secondEnd && secondStart <= firstEnd
    }

    func normalizedKeyText(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
