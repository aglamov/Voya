import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func deleteItineraryItem(_ item: ItineraryItem) {
        guard let trip = trips.first(where: { trip in
            trip.items.contains(where: { $0.id == item.id })
        }) else {
            return
        }

        trip.items.removeAll { $0.id == item.id }
        trip.items = sortedItinerary(trip.items)
        trip.summary = summaryText(for: trip)
        trip.dates = tripDates(for: trip.items, fallback: trip.dates)
        trip.updatedAt = Date()
        modelContext?.delete(item)
        saveTrips()
    }

    func deleteTrip(_ trip: Trip) {
        guard let modelContext,
              let index = trips.firstIndex(where: { $0.id == trip.id }) else {
            return
        }

        let deletedTripID = trip.id
        let deletedTripTitle = trip.title
        modelContext.delete(trip)
        trips.remove(at: index)

        if selectedTripID == deletedTripID || selectedTripID == nil {
            selectedTripID = trips.first?.id
        }

        importMessage = String(localized: "Trip deleted: \(deletedTripTitle)")
        saveTrips()
    }

    func updateTrip(
        _ trip: Trip,
        title: String,
        destination: String,
        summary: String,
        notes: String,
        startLocationName: String,
        startLocationAddress: String,
        endLocationName: String,
        endLocationAddress: String
    ) {
        trip.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        trip.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        trip.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        trip.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        trip.startLocationName = startLocationName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        trip.startLocationAddress = startLocationAddress.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        trip.endLocationName = endLocationName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        trip.endLocationAddress = endLocationAddress.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        trip.updatedAt = Date()
        trip.destinationImageURL = nil
        trip.destinationImageCredit = nil
        saveTrips()
    }

    func addItineraryItem(
        to trip: Trip,
        kind: ItineraryKind,
        title: String,
        startsAt: Date?,
        endsAt: Date?,
        location: String,
        status: String
    ) {
        let item = ItineraryItem(
            kind: kind,
            title: normalizedTitle(title),
            location: normalizedLocation(location),
            status: normalizedStatus(status),
            startsAt: startsAt,
            endsAt: endsAt,
            sourceName: trip.sourceName
        )
        modelContext?.insert(item)
        trip.items.append(item)
        trip.items = sortedItinerary(trip.items)
        trip.summary = summaryText(for: trip)
        trip.dates = tripDates(for: trip.items, fallback: trip.dates)
        trip.updatedAt = Date()
        saveTrips()
    }

    func updateItineraryItem(
        _ item: ItineraryItem,
        kind: ItineraryKind,
        title: String,
        startsAt: Date?,
        endsAt: Date?,
        location: String,
        status: String
    ) {
        guard let trip = trips.first(where: { trip in
            trip.items.contains(where: { $0.id == item.id })
        }) else {
            return
        }

        item.kind = kind
        item.title = normalizedTitle(title)
        item.startsAt = startsAt
        item.endsAt = endsAt
        item.location = normalizedLocation(location)
        item.status = normalizedStatus(status)
        item.updatedAt = Date()

        trip.items = sortedItinerary(trip.items)
        trip.summary = summaryText(for: trip)
        trip.dates = tripDates(for: trip.items, fallback: trip.dates)
        trip.updatedAt = Date()
        saveTrips()
    }

    func apply(_ draft: ItineraryItemDraft, to item: ItineraryItem) {
        item.kind = draft.kind
        item.title = draft.title
        item.startsAt = draft.effectiveStartsAt
        item.endsAt = draft.effectiveEndsAt
        item.location = draft.location
        item.status = draft.status
        item.updatedAt = Date()
    }

    func normalizePreviewItemsForStorage(_ items: [ItineraryItem]) {
        for item in items {
            item.title = normalizedTitle(item.title)
            item.location = normalizedLocation(item.location)
            item.status = normalizedStatus(item.status)
            item.endsAt = item.startsAt == nil ? nil : item.endsAt
        }
    }

    func normalizedTitle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? String(localized: "Untitled item")
    }

    func normalizedLocation(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? String(localized: "Location needed")
    }

    func normalizedStatus(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? String(localized: "Needs review")
    }

    func preparePreviewItemsForStorage(_ items: [ItineraryItem], sourceName: String) {
        let now = Date()
        for item in items {
            item.sourceName = sourceName
            item.updatedAt = now
            modelContext?.insert(item)
        }
    }

    func deleteItems(_ items: [ItineraryItem]) {
        guard let modelContext else { return }
        for item in items {
            modelContext.delete(item)
        }
    }

    func prepareForNextImport() {
        importSuccess = nil
        importMessage = nil
    }

    func prepareForNextPastedImport() {
        importText = ""
        prepareForNextImport()
    }

    func refreshPreviewFields() {
        guard let preview = extractedPreview else { return }
        var updatedPreview = preview
        updatedPreview.fields = ConfirmationParser.fields(for: preview.items, sourceName: preview.sourceName)
        extractedPreview = updatedPreview
    }
}
