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
        trip.destinationImageCreditURL = nil
        trip.destinationImageProvider = nil
        trip.destinationImageResolvedAt = nil
        saveTrips()
    }

    func updateTransferRoute(
        for context: MobilityTransferContext,
        in trip: Trip,
        origin: String,
        destination: String
    ) {
        let normalizedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOrigin.isEmpty, !normalizedDestination.isEmpty else {
            return
        }

        var overrides = trip.transferRouteOverrides
        overrides[context.id] = MobilityTransferRouteOverride(
            origin: normalizedOrigin,
            destination: normalizedDestination
        )

        if let data = try? JSONEncoder().encode(overrides) {
            trip.transferRouteOverridesRaw = String(data: data, encoding: .utf8)
        }
        trip.updatedAt = Date()
        saveTrips()
    }

    func addItineraryItem(
        to trip: Trip,
        kind: ItineraryKind,
        title: String,
        flightNumber: String? = nil,
        startsAt: Date?,
        endsAt: Date?,
        startsAtTimeZoneOffsetSeconds: Int? = nil,
        endsAtTimeZoneOffsetSeconds: Int? = nil,
        location: String,
        status: String,
        confirmationCode: String? = nil,
        providerName: String? = nil
    ) {
        let item = ItineraryItem(
            kind: kind,
            title: normalizedTitle(title),
            flightNumber: normalizedFlightNumber(flightNumber),
            location: normalizedLocation(location),
            status: normalizedStatus(status),
            startsAt: startsAt,
            endsAt: endsAt,
            startsAtTimeZoneOffsetSeconds: startsAtTimeZoneOffsetSeconds,
            endsAtTimeZoneOffsetSeconds: endsAtTimeZoneOffsetSeconds,
            sourceName: trip.sourceName,
            confirmationCode: confirmationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            providerName: providerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
        flightNumber: String? = nil,
        startsAt: Date?,
        endsAt: Date?,
        startsAtTimeZoneOffsetSeconds: Int? = nil,
        endsAtTimeZoneOffsetSeconds: Int? = nil,
        location: String,
        status: String,
        confirmationCode: String? = nil,
        providerName: String? = nil
    ) {
        guard let trip = trips.first(where: { trip in
            trip.items.contains(where: { $0.id == item.id })
        }) else {
            return
        }

        item.kind = kind
        item.title = normalizedTitle(title)
        item.flightNumber = kind == .flight ? normalizedFlightNumber(flightNumber) : nil
        item.startsAt = startsAt
        item.endsAt = endsAt
        item.startsAtTimeZoneOffsetSeconds = startsAt == nil ? nil : startsAtTimeZoneOffsetSeconds
        item.endsAtTimeZoneOffsetSeconds = endsAt == nil ? nil : endsAtTimeZoneOffsetSeconds
        item.location = normalizedLocation(location)
        item.status = normalizedStatus(status)
        item.confirmationCode = confirmationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.providerName = providerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ItemEnrichmentCache.clear(for: item)
        FlightLookupCache.clear(for: item)
        item.updatedAt = Date()

        trip.items = sortedItinerary(trip.items)
        trip.summary = summaryText(for: trip)
        trip.dates = tripDates(for: trip.items, fallback: trip.dates)
        trip.updatedAt = Date()
        saveTrips()
    }

    func attachBoardingPass(_ sourceFile: SourceDocumentFile, to item: ItineraryItem) {
        guard item.kind == .flight,
              let trip = trips.first(where: { trip in
                  trip.items.contains(where: { $0.id == item.id })
              }) else {
            return
        }

        let document = SourceDocument(
            sourceName: String(localized: "Boarding pass"),
            sourceFile: sourceFile
        )
        if let existingDocumentID = item.boardingPassDocumentID,
           let existingDocument = trip.sourceDocuments.first(where: { $0.id == existingDocumentID }) {
            modelContext?.delete(existingDocument)
            trip.sourceDocuments.removeAll { $0.id == existingDocumentID }
        }

        modelContext?.insert(document)
        trip.sourceDocuments.append(document)
        item.boardingPassDocumentID = document.id
        item.status = String(localized: "Checked in")
        item.updatedAt = Date()
        trip.updatedAt = Date()
        saveTrips()
    }

    func removeBoardingPass(from item: ItineraryItem) {
        guard let documentID = item.boardingPassDocumentID,
              let trip = trips.first(where: { trip in
                  trip.items.contains(where: { $0.id == item.id })
              }) else {
            return
        }

        if let document = trip.sourceDocuments.first(where: { $0.id == documentID }) {
            modelContext?.delete(document)
        }

        trip.sourceDocuments.removeAll { $0.id == documentID }
        item.boardingPassDocumentID = nil
        item.updatedAt = Date()
        trip.updatedAt = Date()
        saveTrips()
    }

    func apply(_ draft: ItineraryItemDraft, to item: ItineraryItem) {
        item.kind = draft.kind
        item.title = draft.title
        item.flightNumber = draft.kind == .flight ? normalizedFlightNumber(draft.flightNumber) : nil
        item.startsAt = draft.effectiveStartsAt
        item.endsAt = draft.effectiveEndsAt
        item.startsAtTimeZoneOffsetSeconds = draft.effectiveStartsAt == nil ? nil : draft.startsAtTimeZoneOffsetSeconds
        item.endsAtTimeZoneOffsetSeconds = draft.effectiveEndsAt == nil ? nil : draft.endsAtTimeZoneOffsetSeconds
        item.location = draft.location
        item.status = draft.status
        item.confirmationCode = draft.confirmationCode.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        item.providerName = draft.providerName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ItemEnrichmentCache.clear(for: item)
        FlightLookupCache.clear(for: item)
        item.updatedAt = Date()
    }

    func normalizePreviewItemsForStorage(_ items: [ItineraryItem]) {
        for item in items {
            item.title = normalizedTitle(item.title)
            item.flightNumber = item.kind == .flight ? normalizedFlightNumber(item.resolvedFlightNumber) : nil
            item.location = normalizedLocation(item.location)
            item.status = normalizedStatus(item.status)
            item.endsAt = item.startsAt == nil ? nil : item.endsAt
            if item.startsAt == nil {
                item.startsAtTimeZoneOffsetSeconds = nil
            }
            if item.endsAt == nil {
                item.endsAtTimeZoneOffsetSeconds = nil
            }
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

    func normalizedFlightNumber(_ value: String?) -> String? {
        value?
            .filter { !$0.isWhitespace }
            .uppercased()
            .nilIfEmpty
    }

    func preparePreviewItemsForStorage(_ items: [ItineraryItem], sourceName: String, sourceDocumentID: UUID? = nil) {
        let now = Date()
        for item in items {
            item.sourceName = sourceName
            item.sourceDocumentID = sourceDocumentID
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
        importTripDestination = .newTrip
        importPreparationStatus = nil
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
