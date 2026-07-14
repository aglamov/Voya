import Foundation
import SwiftData
import SwiftUI

@MainActor
extension VoyaStore {
    func extractFromPastedText() {
        extract(text: importText, sourceName: Self.pastedConfirmationSourceName)
    }

    func extract(text: String, sourceName: String, sourceFile: SourceDocumentFile? = nil) {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            beginImportPreparation(sourceName: sourceName, sourceDetail: String(localized: "No source text found"))
            importMessage = ImportErrorMessage.emptyInput.message
            failImportPreparation(with: ImportErrorMessage.emptyInput.message)
            return
        }

        importSuccess = nil
        if importPreparationStatus?.sourceName != sourceName {
            beginImportPreparation(sourceName: sourceName, sourceDetail: String(localized: "Reading source text"))
        }
        updateImportPreparationStep(
            .source,
            state: .completed,
            detail: String(localized: "Text is ready for recognition")
        )
        let document = ImportedDocument(name: sourceName, text: cleanedText, importedAt: Date(), sourceFile: sourceFile)
        importedDocuments.insert(document, at: 0)

        Task {
            await extract(document: document)
        }
    }

    func extract(document: ImportedDocument) async {
        if importPreparationStatus?.sourceName != document.name {
            beginImportPreparation(sourceName: document.name, sourceDetail: String(localized: "Reading source text"))
            updateImportPreparationStep(
                .source,
                state: .completed,
                detail: String(localized: "Text is ready for recognition")
            )
        }

        isExtractingConfirmation = true
        importMessage = String(localized: "Recognizing \(document.name)...")
        updateImportPreparationStep(
            .recognition,
            state: .running,
            detail: String(localized: "Looking for dates, routes, stays, and events")
        )

        do {
            extractedPreview = try await VercelConfirmationExtractor().extract(from: document)
            importMessage = String(localized: "AI recognized \(document.name)")
            updateImportPreparationStep(
                .recognition,
                state: .completed,
                detail: String(localized: "AI recognized the confirmation")
            )
        } catch {
            extractedPreview = ConfirmationParser.extract(from: document)
            importMessage = aiExtractionFailureMessage(for: error)
            updateImportPreparationStep(
                .recognition,
                state: .completed,
                detail: String(localized: "Local recognition prepared the preview")
            )
        }

        if let preview = extractedPreview,
           let suggestedTripID = suggestedImportTripID(for: preview.items) {
            importTripDestination = .existing(suggestedTripID)
        } else {
            importTripDestination = .newTrip
        }

        await enrichExtractedPreviewFlights()
        if let preview = extractedPreview,
           let suggestedTripID = suggestedImportTripID(for: preview.items) {
            importTripDestination = .existing(suggestedTripID)
        } else {
            importTripDestination = .newTrip
        }
        updateImportPreparationStep(
            .preview,
            state: .completed,
            detail: String(localized: "Ready for review and edits")
        )
        updateImportPreparationSummary(String(localized: "Preview ready"))
        isExtractingConfirmation = false
    }

    func aiExtractionFailureMessage(for error: Error) -> String {
        if let extractionError = error as? VercelExtractionError {
            switch extractionError {
            case .notConfigured:
                return String(localized: "Used on-device recognition. Add VOYA_API_BASE_URL to enable AI.")
            case .badResponse:
                return String(localized: "Used on-device recognition because the AI server returned an error.")
            }
        }

        return String(localized: "Used on-device recognition because AI could not be reached.")
    }

    func updatePreviewItem(_ item: ItineraryItem, with draft: ItineraryItemDraft) {
        guard let index = extractedPreview?.items.firstIndex(where: { $0.id == item.id }) else { return }
        apply(draft, to: item)
        extractedPreview?.items[index] = item
        refreshPreviewFields()
    }

    func addPreviewItem() {
        guard extractedPreview != nil else { return }
        let item = ItineraryItem(
            kind: .event,
            title: "",
            location: "",
            status: ""
        )
        extractedPreview?.items.append(item)
        refreshPreviewFields()
    }

    func deletePreviewItem(_ item: ItineraryItem) {
        guard extractedPreview != nil else { return }
        extractedPreview?.items.removeAll { $0.id == item.id }
        refreshPreviewFields()
    }

    func confirmExtraction() {
        guard let preview = extractedPreview, !preview.items.isEmpty else {
            importMessage = String(localized: "Add at least one trip item before saving.")
            return
        }

        if case .existing(let tripID) = importTripDestination,
           !trips.contains(where: { $0.id == tripID }) {
            importMessage = String(localized: "The selected trip is no longer available. Choose another trip or create a new one.")
            return
        }

        saveConfirmedExtraction(preview, destination: importTripDestination)
    }

    func enrichExtractedPreviewFlights() async {
        guard let preview = extractedPreview, !preview.items.isEmpty else {
            updateImportPreparationStep(
                .flightAware,
                state: .skipped,
                detail: String(localized: "Nothing to verify")
            )
            return
        }

        let flightCount = preview.items.filter { $0.kind == .flight }.count
        guard flightCount > 0 else {
            updateImportPreparationStep(
                .flightAware,
                state: .skipped,
                detail: String(localized: "No flights in this confirmation")
            )
            return
        }

        isConfirmingExtraction = true
        importMessage = String(localized: "Filled from source. Checking FlightAware for live schedules.")
        updateImportPreparationStep(
            .flightAware,
            state: .running,
            detail: String(localized: "Checking \(flightCount) flight item\(flightCount == 1 ? "" : "s")")
        )
        defer {
            isConfirmingExtraction = false
        }

        let enrichedCount = await enrichImportedFlights(preview: preview)
        if enrichedCount > 0 {
            refreshPreviewFields()
            importMessage = String(localized: "Updated \(enrichedCount) flight item\(enrichedCount == 1 ? "" : "s") from live schedules.")
            updateImportPreparationStep(
                .flightAware,
                state: .completed,
                detail: String(localized: "Updated \(enrichedCount) flight item\(enrichedCount == 1 ? "" : "s")")
            )
        } else {
            importMessage = String(localized: "Preview ready. FlightAware did not return new schedule details.")
            updateImportPreparationStep(
                .flightAware,
                state: .completed,
                detail: String(localized: "No schedule updates needed")
            )
        }
    }

    func beginImportPreparation(sourceName: String, sourceDetail: String) {
        importPreparationStatus = ImportPreparationStatus(
            sourceName: sourceName,
            summary: String(localized: "Preparing \(sourceName)"),
            steps: [
                ImportPreparationStep(kind: .source, detail: sourceDetail, state: .running),
                ImportPreparationStep(kind: .recognition, detail: String(localized: "Queued"), state: .pending),
                ImportPreparationStep(kind: .flightAware, detail: String(localized: "Waiting for recognized flights"), state: .pending),
                ImportPreparationStep(kind: .preview, detail: String(localized: "Waiting for checks"), state: .pending)
            ]
        )
    }

    func failImportPreparation(with message: String) {
        var status = importPreparationStatus ?? ImportPreparationStatus(
            sourceName: String(localized: "Import"),
            summary: message,
            steps: [
                ImportPreparationStep(kind: .source, detail: message, state: .failed),
                ImportPreparationStep(kind: .recognition, detail: String(localized: "Not started"), state: .pending),
                ImportPreparationStep(kind: .flightAware, detail: String(localized: "Not started"), state: .pending),
                ImportPreparationStep(kind: .preview, detail: String(localized: "Not started"), state: .pending)
            ]
        )

        if let runningIndex = status.steps.firstIndex(where: { $0.state == .running }) {
            status.steps[runningIndex].state = .failed
            status.steps[runningIndex].detail = message
        } else if let sourceIndex = status.steps.firstIndex(where: { $0.id == .source }) {
            status.steps[sourceIndex].state = .failed
            status.steps[sourceIndex].detail = message
        }

        status.summary = message
        importPreparationStatus = status
    }

    func updateImportPreparationStep(
        _ kind: ImportPreparationStepKind,
        state: ImportPreparationStepState,
        detail: String
    ) {
        guard var status = importPreparationStatus,
              let index = status.steps.firstIndex(where: { $0.id == kind }) else {
            return
        }

        status.steps[index].state = state
        status.steps[index].detail = detail
        status.summary = summary(for: status)
        importPreparationStatus = status
    }

    func updateImportPreparationSummary(_ summary: String) {
        guard var status = importPreparationStatus else {
            return
        }

        status.summary = summary
        importPreparationStatus = status
    }

    func summary(for status: ImportPreparationStatus) -> String {
        if let failedStep = status.steps.first(where: { $0.state == .failed }) {
            return failedStep.detail
        }

        if let runningStep = status.steps.first(where: { $0.state == .running }) {
            return runningStep.title
        }

        if status.steps.allSatisfy({ $0.state == .completed || $0.state == .skipped }) {
            return String(localized: "Preview ready")
        }

        return String(localized: "Preparing \(status.sourceName)")
    }

    func saveConfirmedExtraction(_ preview: ExtractionPreview, destination: ImportTripDestination) {
        normalizePreviewItemsForStorage(preview.items)

        if case .existing(let tripID) = destination,
           let matchingTripIndex = trips.firstIndex(where: { $0.id == tripID }) {
            let trip = trips[matchingTripIndex]
            let sourceDocument: SourceDocument?
            if let sourceFile = preview.sourceFile {
                sourceDocument = self.sourceDocument(for: sourceFile, sourceName: preview.sourceName, in: trip)
            } else {
                sourceDocument = nil
            }
            if let sourceDocument {
                attachSourceDocument(sourceDocument, to: trip)
            }
            preparePreviewItemsForStorage(preview.items, sourceName: preview.sourceName, sourceDocumentID: sourceDocument?.id)
            let previousItemCount = trip.items.count
            let deduplicated = deduplicatedItems(from: trip.items + preview.items)
            trip.items = sortedItinerary(deduplicated.unique)
            if let sourceDocument {
                for item in trip.items where item.sourceDocumentID == nil && item.sourceName == preview.sourceName {
                    item.sourceDocumentID = sourceDocument.id
                }
            }
            trip.dates = tripDates(for: trip.items, fallback: trip.dates)
            trip.summary = summaryText(for: trip)
            trip.sourceName = combinedSourceName(trip.sourceName, preview.sourceName)
            trip.rawData = nil
            trip.destination = tripTitle(for: trip.items, fallback: trip.title, preferredDestination: preview.normalizedDestination)
            trip.destinationImageURL = nil
            trip.destinationImageCredit = nil
            trip.updatedAt = Date()
            deleteItems(deduplicated.duplicates)
            selectedTripID = trip.id
            let addedItemCount = max(0, trip.items.count - previousItemCount)
            importMessage = addedItemCount == 0 ? String(localized: "Already in trip: \(trip.title)") : String(localized: "Added to trip: \(trip.title)")
            importSuccess = ImportSuccess(
                tripTitle: trip.title,
                itemCount: addedItemCount,
                sourceName: preview.sourceName,
                didCreateTrip: false
            )
        } else {
            let sourceDocument: SourceDocument?
            if let sourceFile = preview.sourceFile {
                sourceDocument = self.sourceDocument(for: sourceFile, sourceName: preview.sourceName, in: nil)
            } else {
                sourceDocument = nil
            }
            preparePreviewItemsForStorage(preview.items, sourceName: preview.sourceName, sourceDocumentID: sourceDocument?.id)
            let deduplicated = deduplicatedItems(from: preview.items)
            let items = sortedItinerary(deduplicated.unique)
            let trip = Trip(
                title: tripTitle(
                    for: items,
                    fallback: preview.title,
                    preferredDestination: preview.normalizedDestination
                ),
                dates: tripDates(for: items, fallback: preview.primaryTime),
                summary: summaryText(itemCount: items.count, sourceName: preview.sourceName),
                destination: preview.normalizedDestination,
                items: items,
                sourceDocuments: sourceDocument.map { [$0] } ?? [],
                sourceName: preview.sourceName,
                rawData: nil
            )
            modelContext?.insert(trip)
            deleteItems(deduplicated.duplicates)
            trips.insert(trip, at: 0)
            selectedTripID = trip.id
            importMessage = String(localized: "Trip created: \(trip.title)")
            importSuccess = ImportSuccess(
                tripTitle: trip.title,
                itemCount: items.count,
                sourceName: preview.sourceName,
                didCreateTrip: true
            )
        }

        saveTrips()
        extractedPreview = nil
    }

    func enrichImportedFlights(preview: ExtractionPreview) async -> Int {
        var updatedCount = 0
        let service = VercelFlightLookupService()

        for (index, item) in preview.items.enumerated() where item.kind == .flight {
            guard let flightNumber = firstFlightNumber(in: "\(item.title) \(item.location)") else {
                continue
            }

            let route = airportRouteCodes(in: item.location)
            let referenceDate = item.startsAt ?? nearbyFlightDate(for: index, in: preview.items)

            do {
                let response = try await service.lookup(
                    flightNumber: flightNumber,
                    date: referenceDate,
                    originAirport: route?.origin,
                    destinationAirport: route?.destination
                )

                guard let candidate = response.candidate else {
                    continue
                }

                if apply(candidate, toImportedFlight: item) {
                    updatedCount += 1
                }
            } catch {
                continue
            }
        }

        return updatedCount
    }

    func apply(_ candidate: FlightLookupCandidate, toImportedFlight item: ItineraryItem) -> Bool {
        var didChange = false

        if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || item.title.localizedCaseInsensitiveContains("destination")
            || item.title.localizedCaseInsensitiveContains(candidate.flightNumber) {
            let title = candidate.titleText
            if !title.isEmpty, item.title != title {
                item.title = title
                didChange = true
            }
        }

        if !candidate.routeText.isEmpty, item.location != candidate.routeText {
            item.location = candidate.routeText
            didChange = true
        }

        if let departure = candidate.parsedDepartureAt,
           item.startsAt == nil || abs(departure.timeIntervalSince(item.startsAt ?? departure)) > 60 {
            item.startsAt = departure
            didChange = true
        }

        if let arrival = candidate.parsedArrivalAt,
           item.endsAt == nil || abs(arrival.timeIntervalSince(item.endsAt ?? arrival)) > 60 {
            item.endsAt = arrival
            didChange = true
        }

        let status = enrichedFlightStatus(from: candidate)
        if item.status.localizedCaseInsensitiveContains("needs")
            || item.status.localizedCaseInsensitiveContains("terminal")
            || item.status.localizedCaseInsensitiveContains("confirmed") {
            if item.status != status {
                item.status = status
                didChange = true
            }
        }

        if didChange {
            item.updatedAt = Date()
        }

        return didChange
    }

    func enrichedFlightStatus(from candidate: FlightLookupCandidate) -> String {
        var parts = [candidate.statusText]

        if let terminal = candidate.departureTerminal?.trimmingCharacters(in: .whitespacesAndNewlines), !terminal.isEmpty {
            parts.append(String(localized: "Terminal \(terminal)"))
        }

        if let gate = candidate.departureGate?.trimmingCharacters(in: .whitespacesAndNewlines), !gate.isEmpty {
            parts.append(String(localized: "Gate \(gate)"))
        }

        if let baggage = candidate.baggageClaim?.trimmingCharacters(in: .whitespacesAndNewlines), !baggage.isEmpty {
            parts.append(String(localized: "Bags \(baggage)"))
        }

        return parts.joined(separator: " · ")
    }

    func nearbyFlightDate(for index: Int, in items: [ItineraryItem]) -> Date? {
        let nearbyIndices = [index - 1, index + 1]
        for nearbyIndex in nearbyIndices where items.indices.contains(nearbyIndex) {
            if let date = items[nearbyIndex].startsAt ?? items[nearbyIndex].endsAt {
                return date
            }
        }

        return items.compactMap { $0.startsAt ?? $0.endsAt }.min()
    }

    func firstFlightNumber(in value: String) -> String? {
        guard let match = value.firstMatch(of: /[A-Z0-9]{2,3}\s?\d{1,4}[A-Z]?/) else {
            return nil
        }

        return String(match.output).replacingOccurrences(of: " ", with: "").uppercased()
    }

    func airportRouteCodes(in value: String) -> (origin: String, destination: String)? {
        let codes = value
            .uppercased()
            .matches(of: /\b[A-Z]{3,4}\b/)
            .map { String($0.output) }

        guard codes.count >= 2 else {
            return nil
        }

        return (codes[0], codes[1])
    }
}
