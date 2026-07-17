import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func loadHeroImageIfNeeded(for trip: Trip) async {
        let now = Date()
        let needsImage = trip.destinationImageURL == nil
        let needsProviderUpgrade = trip.destinationImageURL != nil && trip.destinationImageProvider == nil
        let fallbackRetryDate = trip.destinationImageResolvedAt?.addingTimeInterval(24 * 60 * 60)
        let needsFallbackRetry = trip.destinationImageProvider == DestinationImageSource.wikipedia.rawValue
            && (fallbackRetryDate.map { $0 <= now } ?? true)
        guard needsImage || needsProviderUpgrade || needsFallbackRetry,
              trips.contains(where: { $0.id == trip.id }) else {
            return
        }

        let originalImageURL = trip.destinationImageURL
        let originalProvider = trip.destinationImageProvider
        let resolver = DestinationImageResolver()
        for searchTerm in heroImageSearchTerms(for: trip) {
            do {
                let heroImage = try await resolver.image(for: searchTerm)
                guard let currentIndex = trips.firstIndex(where: { $0.id == trip.id }),
                      trips[currentIndex].destinationImageURL == originalImageURL,
                      trips[currentIndex].destinationImageProvider == originalProvider else {
                    return
                }

                let trip = trips[currentIndex]
                trip.destinationImageURL = heroImage.url
                trip.destinationImageCredit = heroImage.credit
                trip.destinationImageCreditURL = heroImage.creditURL
                trip.destinationImageProvider = heroImage.source.rawValue
                trip.destinationImageResolvedAt = now
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
        if trip.destinationImageURL == nil {
            trip.destinationImageCredit = nil
            trip.destinationImageCreditURL = nil
            trip.destinationImageProvider = nil
        }
        trip.destinationImageResolvedAt = now
        trip.updatedAt = Date()
        saveTrips()
    }
}
