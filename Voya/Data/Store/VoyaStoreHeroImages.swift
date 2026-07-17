import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func loadHeroImageIfNeeded(for trip: Trip) async {
        let needsImage = trip.destinationImageURL == nil
        let needsProviderUpgrade = trip.destinationImageURL != nil && trip.destinationImageProvider == nil
        guard needsImage || needsProviderUpgrade,
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
                trip.destinationImageCreditURL = heroImage.creditURL
                trip.destinationImageProvider = heroImage.source.rawValue
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
        trip.destinationImageCreditURL = nil
        trip.destinationImageProvider = nil
        trip.updatedAt = Date()
        saveTrips()
    }
}
