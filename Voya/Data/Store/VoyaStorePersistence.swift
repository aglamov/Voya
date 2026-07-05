import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func configure(modelContext: ModelContext) {
        guard self.modelContext !== modelContext else { return }
        self.modelContext = modelContext
        fetchTrips()
    }

    @discardableResult
    func selectCurrentTripIfAvailable(at date: Date = Date()) -> Bool {
        guard let trip = currentOrUpcomingTrip(at: date) else {
            return false
        }

        selectedTripID = trip.id
        return true
    }

    func fetchTrips() {
        guard let modelContext else { return }

        var descriptor = FetchDescriptor<Trip>(
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.items]

        do {
            trips = try modelContext.fetch(descriptor)
            removeDuplicateItemsFromLoadedTrips()
            if let selectedTripID, !trips.contains(where: { $0.id == selectedTripID }) {
                self.selectedTripID = trips.first?.id
            } else if selectedTripID == nil {
                selectedTripID = trips.first?.id
            }
            syncTripNotifications()
        } catch {
            importMessage = String(localized: "Could not load saved trips")
            trips = []
        }
    }

    func activeTrips(at date: Date) -> [Trip] {
        trips.filter { !isArchived($0, at: date) }
    }

    func archivedTrips(at date: Date) -> [Trip] {
        trips.filter { isArchived($0, at: date) }
    }

    func currentOrUpcomingTrip(at date: Date) -> Trip? {
        let datedTrips = activeTrips(at: date).compactMap { trip -> (trip: Trip, interval: DateInterval)? in
            guard let interval = activeInterval(for: trip) else { return nil }
            return (trip, interval)
        }

        if let current = datedTrips
            .filter({ $0.interval.contains(date) })
            .min(by: { $0.interval.start < $1.interval.start }) {
            return current.trip
        }

        return datedTrips
            .filter { $0.interval.start > date }
            .min(by: { $0.interval.start < $1.interval.start })?
            .trip
    }

    func isArchived(_ trip: Trip, at date: Date) -> Bool {
        guard let interval = activeInterval(for: trip) else {
            return false
        }

        return interval.end < Calendar.current.startOfDay(for: date)
    }

    func activeInterval(for trip: Trip) -> DateInterval? {
        let tripDates = [trip.startsAt, trip.endsAt].compactMap { $0 }
        let itemDates = trip.items.flatMap { item in
            [item.startsAt, item.endsAt].compactMap { $0 }
        }
        let dates = tripDates.isEmpty ? itemDates : tripDates

        guard let firstDate = dates.min(), let lastDate = dates.max() else {
            return nil
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: firstDate)
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: lastDate) ?? lastDate

        return DateInterval(start: start, end: max(start, end))
    }

    func saveTrips() {
        guard let modelContext else { return }

        do {
            try modelContext.save()
            fetchTrips()
        } catch {
            importMessage = String(localized: "Could not save trip changes")
        }
    }

    func removeDuplicateItemsFromLoadedTrips() {
        guard let modelContext else { return }
        var removedItems: [ItineraryItem] = []

        for trip in trips {
            let deduplicated = deduplicatedItems(from: trip.items)
            guard !deduplicated.duplicates.isEmpty else { continue }

            trip.items = sortedItinerary(deduplicated.unique)
            trip.summary = summaryText(for: trip)
            trip.updatedAt = Date()
            removedItems.append(contentsOf: deduplicated.duplicates)
        }

        guard !removedItems.isEmpty else { return }

        for item in removedItems {
            modelContext.delete(item)
        }

        do {
            try modelContext.save()
            syncTripNotifications()
        } catch {
            importMessage = String(localized: "Could not clean up duplicate trip items")
        }
    }

    func syncTripNotifications() {
        let notificationTrips = trips.map { trip in
            VoyaNotificationTrip(
                id: trip.id,
                title: trip.title,
                items: sortedItinerary(trip.items).map { item in
                    VoyaNotificationItem(
                        id: item.id,
                        kind: item.kind,
                        title: item.title,
                        location: item.location,
                        status: item.status,
                        startsAt: item.startsAt,
                        endsAt: item.endsAt
                    )
                }
            )
        }

        Task {
            await VoyaNotificationScheduler.shared.syncNotifications(for: notificationTrips)
        }
    }
}
