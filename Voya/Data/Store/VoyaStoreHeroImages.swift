import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func loadHeroImageIfNeeded(for trip: Trip) async {
        guard trip.destinationImageURL == nil,
              trips.contains(where: { $0.id == trip.id }) else {
            return
        }

        let resolver = DestinationImageResolver()
        for searchTerm in heroImageSearchTerms(for: trip) {
            do {
                let heroImage = try await resolver.image(for: searchTerm)
                guard let currentIndex = trips.firstIndex(where: { $0.id == trip.id }),
                      trips[currentIndex].destinationImageURL == nil else {
                    return
                }

                let trip = trips[currentIndex]
                trip.destinationImageURL = heroImage.url
                trip.destinationImageCredit = heroImage.credit
                trip.updatedAt = Date()
                saveTrips()
                return
            } catch {
                continue
            }
        }

        guard let currentIndex = trips.firstIndex(where: { $0.id == trip.id }) else {
            return
        }

        let trip = trips[currentIndex]
        trip.destinationImageCredit = nil
        trip.updatedAt = Date()
        saveTrips()
    }
}
