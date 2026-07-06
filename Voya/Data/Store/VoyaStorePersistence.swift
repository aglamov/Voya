import Foundation
import PDFKit
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
        descriptor.relationshipKeyPathsForPrefetching = [\.items, \.sourceDocuments]

        do {
            trips = try modelContext.fetch(descriptor)
            migrateLegacyTripSourceDocuments()
            removeDuplicateItemsFromLoadedTrips()
            backfillFlightBookingDetailsFromSources()
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

    func sourceDocument(for item: ItineraryItem) -> SourceDocument? {
        guard let sourceDocumentID = item.sourceDocumentID else {
            return nil
        }

        return trips.lazy
            .flatMap(\.sourceDocuments)
            .first { $0.id == sourceDocumentID }
    }

    func boardingPassDocument(for item: ItineraryItem) -> SourceDocument? {
        guard let boardingPassDocumentID = item.boardingPassDocumentID else {
            return nil
        }

        return trips.lazy
            .flatMap(\.sourceDocuments)
            .first { $0.id == boardingPassDocumentID }
    }

    func sourceDocument(for sourceFile: SourceDocumentFile, sourceName: String, in trip: Trip?) -> SourceDocument {
        if let existing = trip?.sourceDocuments.first(where: { $0.matches(sourceFile) }) {
            return existing
        }

        let document = SourceDocument(sourceName: sourceName, sourceFile: sourceFile)
        modelContext?.insert(document)

        if let trip, !trip.sourceDocuments.contains(where: { $0.id == document.id }) {
            trip.sourceDocuments.append(document)
        }

        return document
    }

    func attachSourceDocument(_ document: SourceDocument, to trip: Trip) {
        guard !trip.sourceDocuments.contains(where: { $0.id == document.id }) else {
            return
        }

        trip.sourceDocuments.append(document)
    }

    func migrateLegacyTripSourceDocuments() {
        guard let modelContext else { return }
        var didChange = false

        for trip in trips {
            guard let sourceFile = SourceDocumentFile.stored(in: trip.rawData) else {
                continue
            }

            let document = sourceDocument(for: sourceFile, sourceName: trip.sourceName, in: trip)
            for item in trip.items where item.sourceDocumentID == nil && item.sourceName == trip.sourceName {
                item.sourceDocumentID = document.id
                item.updatedAt = Date()
            }
            trip.rawData = nil
            trip.updatedAt = Date()
            didChange = true
        }

        guard didChange else { return }

        do {
            try modelContext.save()
        } catch {
            importMessage = String(localized: "Could not migrate source files")
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

    func backfillFlightBookingDetailsFromSources() {
        guard let modelContext else { return }

        var didChange = false
        var sourceTextCache: [UUID: String] = [:]

        for trip in trips {
            for item in trip.items where item.kind == .flight {
                if item.providerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == nil,
                   let airlineName = FlightCheckInAction.airlineName(in: "\(item.title) \(item.location)") {
                    item.providerName = airlineName
                    item.updatedAt = Date()
                    didChange = true
                }

                guard item.confirmationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == nil,
                      let sourceDocument = sourceDocument(for: item, in: trip) else {
                    continue
                }

                let sourceText: String
                if let cachedText = sourceTextCache[sourceDocument.id] {
                    sourceText = cachedText
                } else {
                    guard let extractedText = text(from: sourceDocument) else {
                        continue
                    }
                    sourceTextCache[sourceDocument.id] = extractedText
                    sourceText = extractedText
                }

                if let confirmationCode = ConfirmationParser.bookingReference(in: sourceText) {
                    item.confirmationCode = confirmationCode
                    item.updatedAt = Date()
                    didChange = true
                }
            }
        }

        guard didChange else { return }

        do {
            try modelContext.save()
        } catch {
            importMessage = String(localized: "Could not update flight booking details")
        }
    }

    private func sourceDocument(for item: ItineraryItem, in trip: Trip) -> SourceDocument? {
        if let sourceDocumentID = item.sourceDocumentID,
           let sourceDocument = trip.sourceDocuments.first(where: { $0.id == sourceDocumentID }) {
            return sourceDocument
        }

        if let sourceName = item.sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
           let sourceDocument = trip.sourceDocuments.first(where: { $0.sourceName == sourceName }) {
            return sourceDocument
        }

        return trip.sourceDocuments.count == 1 ? trip.sourceDocuments.first : nil
    }

    private func text(from sourceDocument: SourceDocument) -> String? {
        guard let data = Data(base64Encoded: sourceDocument.dataBase64) else {
            return nil
        }

        let contentType = sourceDocument.contentType.lowercased()
        let fileExtension = (sourceDocument.fileName as NSString).pathExtension.lowercased()

        if contentType.contains("pdf") || fileExtension == "pdf" {
            guard let document = PDFDocument(data: data) else {
                return nil
            }

            let text = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.nilIfEmpty
        }

        if contentType.hasPrefix("text/")
            || ["txt", "eml", "ics", "csv"].contains(fileExtension) {
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }

        return nil
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
                        sourceName: item.sourceName,
                        confirmationCode: item.confirmationCode,
                        providerName: item.providerName,
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
