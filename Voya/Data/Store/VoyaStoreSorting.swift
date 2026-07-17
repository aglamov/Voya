import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func sortedItinerary(_ items: [ItineraryItem]) -> [ItineraryItem] {
        items.sorted { first, second in
            isOrdered(
                first,
                before: second,
                firstDate: first.startsAt,
                secondDate: second.startsAt
            )
        }
    }

    /// Returns a presentation order for the trip timeline without changing the
    /// booking dates stored on its items. A hotel's check-in time describes when
    /// the room becomes available, so an arrival later that day should still be
    /// shown before the stay.
    func timelineItinerary(for trip: Trip) -> [ItineraryItem] {
        let items = trip.items
        let placementDates = Dictionary(uniqueKeysWithValues: items.map { item in
            (item.id, timelinePlacementDate(for: item, among: items))
        })

        return items.sorted { first, second in
            isOrdered(
                first,
                before: second,
                firstDate: placementDates[first.id] ?? first.startsAt,
                secondDate: placementDates[second.id] ?? second.startsAt
            )
        }
    }

    private func isOrdered(
        _ first: ItineraryItem,
        before second: ItineraryItem,
        firstDate: Date?,
        secondDate: Date?
    ) -> Bool {
        switch (firstDate, secondDate) {
        case let (firstDate?, secondDate?) where firstDate != secondDate:
            return firstDate < secondDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        let firstKind = kindSortOrder(first.kind)
        let secondKind = kindSortOrder(second.kind)
        if firstKind != secondKind {
            return firstKind < secondKind
        }

        if first.createdAt != second.createdAt {
            return first.createdAt < second.createdAt
        }

        return first.id.uuidString < second.id.uuidString
    }

    private func timelinePlacementDate(for item: ItineraryItem, among items: [ItineraryItem]) -> Date? {
        guard item.kind == .hotel,
              let checkIn = item.startsAt,
              let checkOut = item.endsAt,
              checkOut > checkIn else {
            return item.startsAt
        }

        // Only reinterpret arrivals close to the beginning of the stay. Later
        // day trips remain inside the accommodation interval in normal time order.
        let arrivalWindowEnd = min(checkOut, checkIn.addingTimeInterval(36 * 60 * 60))
        let stayDescription = "\(item.title) \(item.location)"

        let arrival = items
            .filter { candidate in
                candidate.id != item.id
                    && (candidate.kind == .flight || candidate.kind == .transit)
            }
            .compactMap { candidate -> Date? in
                guard let boundary = candidate.endsAt ?? candidate.startsAt,
                      boundary >= checkIn,
                      boundary <= arrivalWindowEnd,
                      !movementClearlyDeparts(candidate, from: stayDescription) else {
                    return nil
                }
                return boundary
            }
            .min()

        return arrival.map { max(checkIn, $0) } ?? checkIn
    }

    private func movementClearlyDeparts(_ item: ItineraryItem, from stayDescription: String) -> Bool {
        let route = routeParts(in: item.location)
        guard route.count >= 2 else {
            return false
        }

        let originMatches = placesOverlap(route[0], stayDescription)
        let destinationMatches = placesOverlap(route[route.count - 1], stayDescription)
        return originMatches && !destinationMatches
    }

    private func routeParts(in value: String) -> [String] {
        value
            .replacingOccurrences(of: "→", with: " to ")
            .components(separatedBy: " to ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func placesOverlap(_ first: String, _ second: String) -> Bool {
        let ignoredTokens: Set<String> = [
            "airport", "arrivals", "departures", "hotel", "resort", "station",
            "аэропорт", "вокзал", "отель", "гостиница"
        ]
        let firstTokens = placeTokens(in: first).subtracting(ignoredTokens)
        let secondTokens = placeTokens(in: second).subtracting(ignoredTokens)
        return !firstTokens.isDisjoint(with: secondTokens)
    }

    private func placeTokens(in value: String) -> Set<String> {
        Set(
            value
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .components(separatedBy: .alphanumerics.inverted)
                .map { $0.lowercased() }
                .filter { $0.count >= 3 }
        )
    }

    func kindSortOrder(_ kind: ItineraryKind) -> Int {
        switch kind {
        case .flight: 0
        case .transit: 1
        case .hotel: 2
        case .event: 3
        }
    }
}
