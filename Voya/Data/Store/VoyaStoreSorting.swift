import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func sortedItinerary(_ items: [ItineraryItem]) -> [ItineraryItem] {
        items.sorted { first, second in
            let firstKey = sortKey(for: first)
            let secondKey = sortKey(for: second)

            if firstKey.date != secondKey.date {
                return firstKey.date < secondKey.date
            }

            if firstKey.time != secondKey.time {
                return firstKey.time < secondKey.time
            }

            return firstKey.kind < secondKey.kind
        }
    }

    func sortKey(for item: ItineraryItem) -> (date: Int, time: Int, kind: Int) {
        if let startsAt = item.startsAt {
            let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: startsAt)
            return (
                date: (components.month ?? 99) * 100 + (components.day ?? 99),
                time: (components.hour ?? 23) * 60 + (components.minute ?? 59),
                kind: kindSortOrder(item.kind)
            )
        }

        return (
            date: Int.max,
            time: Int.max,
            kind: kindSortOrder(item.kind)
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
