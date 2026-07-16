import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func sortedItinerary(_ items: [ItineraryItem]) -> [ItineraryItem] {
        items.sorted { first, second in
            switch (first.startsAt, second.startsAt) {
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
