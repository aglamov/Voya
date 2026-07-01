import Foundation
import SwiftData
import SwiftUI

enum TripMood: String, CaseIterable, Identifiable {
    case warm = "Warm"
    case food = "Food"
    case culture = "Culture"
    case events = "Events"

    var id: String { rawValue }
}

struct TripRecommendation: Identifiable {
    let id = UUID()
    let destination: String
    let dates: String
    let fit: String
    let estimatedCost: String
    let details: [String]
    let accent: Color
}

enum ItineraryKind: String, Codable {
    case flight = "Flight"
    case hotel = "Hotel"
    case event = "Event"
    case transit = "Transit"

    var symbol: String {
        switch self {
        case .flight: "airplane"
        case .hotel: "bed.double"
        case .event: "ticket"
        case .transit: "tram"
        }
    }
}

@Model
final class ItineraryItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var kind: ItineraryKind
    var title: String
    var time: String
    var location: String
    var status: String
    var startsAt: Date?
    var endsAt: Date?
    var sourceName: String?
    var sourceDocumentID: UUID?
    var confirmationCode: String?
    var providerName: String?
    var rawData: String?
    var normalizedData: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: ItineraryKind,
        title: String,
        time: String,
        location: String,
        status: String,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        sourceName: String? = nil,
        sourceDocumentID: UUID? = nil,
        confirmationCode: String? = nil,
        providerName: String? = nil,
        rawData: String? = nil,
        normalizedData: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.time = time
        self.location = location
        self.status = status
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.sourceName = sourceName
        self.sourceDocumentID = sourceDocumentID
        self.confirmationCode = confirmationCode
        self.providerName = providerName
        self.rawData = rawData
        self.normalizedData = normalizedData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Trip: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var dates: String
    var summary: String
    var destination: String?
    var startsAt: Date?
    var endsAt: Date?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var items: [ItineraryItem]
    var sourceName: String
    var destinationImageURL: URL?
    var destinationImageCredit: String?
    var notes: String?
    var rawData: String?

    init(
        id: UUID = UUID(),
        title: String,
        dates: String,
        summary: String,
        destination: String? = nil,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        items: [ItineraryItem],
        sourceName: String,
        destinationImageURL: URL? = nil,
        destinationImageCredit: String? = nil,
        notes: String? = nil,
        rawData: String? = nil
    ) {
        self.id = id
        self.title = title
        self.dates = dates
        self.summary = summary
        self.destination = destination
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = items
        self.sourceName = sourceName
        self.destinationImageURL = destinationImageURL
        self.destinationImageCredit = destinationImageCredit
        self.notes = notes
        self.rawData = rawData
    }
}

struct DestinationHeroImage {
    let url: URL
    let credit: String
}

struct DestinationImageResolver {
    func image(for destination: String) async throws -> DestinationHeroImage {
        let pageTitle = Self.normalizedDestination(destination)
            .replacingOccurrences(of: "Trip to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " ", with: "_")

        guard let encodedTitle = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Voya travel companion", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let summary = try JSONDecoder().decode(WikipediaPageSummary.self, from: data)
        guard let imageURL = summary.originalimage?.source ?? summary.thumbnail?.source else {
            throw URLError(.fileDoesNotExist)
        }

        return DestinationHeroImage(url: imageURL, credit: "Image: Wikipedia")
    }

    private static func normalizedDestination(_ destination: String) -> String {
        destination
            .replacingOccurrences(of: #"\s*\([A-Z]{3}\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WikipediaPageSummary: Decodable {
    struct PageImage: Decodable {
        let source: URL
    }

    let thumbnail: PageImage?
    let originalimage: PageImage?
}

struct ImportedDocument: Identifiable {
    let id = UUID()
    var name: String
    var text: String
    var importedAt: Date
}

struct ExtractedField: Identifiable {
    let id = UUID()
    var label: String
    var value: String
}

struct ExtractionPreview: Identifiable {
    let id = UUID()
    var sourceName: String
    var type: String
    var title: String
    var normalizedDestination: String?
    var primaryTime: String
    var confidence: Double
    var fields: [ExtractedField]
    var items: [ItineraryItem]
    var warnings: [String]
}

struct ImportSuccess: Identifiable {
    let id = UUID()
    var tripTitle: String
    var itemCount: Int
    var sourceName: String
    var didCreateTrip: Bool
}

enum ImportErrorMessage: Identifiable {
    case emptyInput
    case unreadableFile(String)

    var id: String { message }

    var message: String {
        switch self {
        case .emptyInput:
            "Paste or choose a confirmation first."
        case .unreadableFile(let name):
            "Could not read text from \(name). Try a text-based PDF or paste the confirmation."
        }
    }
}

struct TravelAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let severity: AlertSeverity
}

enum AlertSeverity {
    case calm
    case watch
    case action

    var color: Color {
        switch self {
        case .calm: .teal
        case .watch: .orange
        case .action: .red
        }
    }
}

@MainActor
final class VoyaStore: ObservableObject {
    static let pastedConfirmationSourceName = "Pasted confirmation"

    private var modelContext: ModelContext?

    @Published var inspirationText = "Warm 4-day trip under $700 with easy transit"
    @Published var selectedMood: TripMood = .warm
    @Published var importText = ""
    @Published var extractedPreview: ExtractionPreview?
    @Published var importedDocuments: [ImportedDocument] = []
    @Published var trips: [Trip] = []
    @Published var selectedTripID: UUID?
    @Published var importMessage: String?
    @Published var importSuccess: ImportSuccess?
    @Published var isExtractingConfirmation = false

    var selectedTrip: Trip? {
        guard let selectedTripID else { return trips.first }
        return trips.first { $0.id == selectedTripID } ?? trips.first
    }

    let recommendations = SampleData.recommendations
    let alerts = SampleData.alerts

    var itinerary: [ItineraryItem] {
        selectedTrip?.items ?? []
    }

    func configure(modelContext: ModelContext) {
        guard self.modelContext !== modelContext else { return }
        self.modelContext = modelContext
        fetchTrips()
    }

    private func fetchTrips() {
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
        } catch {
            importMessage = "Could not load saved trips"
            trips = []
        }
    }

    private func saveTrips() {
        guard let modelContext else { return }

        do {
            try modelContext.save()
            fetchTrips()
        } catch {
            importMessage = "Could not save trip changes"
        }
    }

    private func removeDuplicateItemsFromLoadedTrips() {
        guard let modelContext else { return }
        var removedItems: [ItineraryItem] = []

        for trip in trips {
            let deduplicated = deduplicatedItems(from: trip.items)
            guard !deduplicated.duplicates.isEmpty else { continue }

            trip.items = sortedItinerary(deduplicated.unique)
            trip.summary = "\(trip.items.count) confirmed item\(trip.items.count == 1 ? "" : "s") in one travel chain"
            trip.updatedAt = Date()
            removedItems.append(contentsOf: deduplicated.duplicates)
        }

        guard !removedItems.isEmpty else { return }

        for item in removedItems {
            modelContext.delete(item)
        }

        do {
            try modelContext.save()
        } catch {
            importMessage = "Could not clean up duplicate trip items"
        }
    }

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

    func extractFromPastedText() {
        extract(text: importText, sourceName: Self.pastedConfirmationSourceName)
    }

    func extract(text: String, sourceName: String) {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            importMessage = ImportErrorMessage.emptyInput.message
            return
        }

        importSuccess = nil
        let document = ImportedDocument(name: sourceName, text: cleanedText, importedAt: Date())
        importedDocuments.insert(document, at: 0)

        Task {
            await extract(document: document)
        }
    }

    private func extract(document: ImportedDocument) async {
        isExtractingConfirmation = true
        importMessage = "Recognizing \(document.name)..."

        do {
            extractedPreview = try await VercelConfirmationExtractor().extract(from: document)
            importMessage = "AI recognized \(document.name)"
        } catch {
            extractedPreview = ConfirmationParser.extract(from: document)
            importMessage = "Imported \(document.name) with on-device parser"
        }

        isExtractingConfirmation = false
    }

    func updatePreviewItem(_ item: ItineraryItem) {
        guard let index = extractedPreview?.items.firstIndex(where: { $0.id == item.id }) else { return }
        item.updatedAt = Date()
        extractedPreview?.items[index] = item
        refreshPreviewFields()
    }

    func confirmExtraction() {
        guard let preview = extractedPreview else { return }
        preparePreviewItemsForStorage(preview.items, sourceName: preview.sourceName)

        if let matchingTripIndex = tripIndexForMerge(with: preview.items) {
            let trip = trips[matchingTripIndex]
            trip.items = sortedItinerary(uniqueItems(from: trip.items + preview.items))
            trip.dates = tripDates(for: trip.items, fallback: trip.dates)
            trip.summary = "\(trip.items.count) confirmed item\(trip.items.count == 1 ? "" : "s") in one travel chain"
            trip.sourceName = combinedSourceName(trip.sourceName, preview.sourceName)
            trip.destination = tripTitle(for: trip.items, fallback: trip.title, preferredDestination: preview.normalizedDestination)
            trip.destinationImageURL = nil
            trip.destinationImageCredit = nil
            trip.updatedAt = Date()
            selectedTripID = trip.id
            importMessage = "Added to trip: \(trip.title)"
            importSuccess = ImportSuccess(
                tripTitle: trip.title,
                itemCount: preview.items.count,
                sourceName: preview.sourceName,
                didCreateTrip: false
            )
        } else {
            let items = sortedItinerary(uniqueItems(from: preview.items))
            let trip = Trip(
                title: tripTitle(
                    for: items,
                    fallback: preview.title,
                    preferredDestination: preview.normalizedDestination
                ),
                dates: tripDates(for: items, fallback: preview.primaryTime),
                summary: "\(items.count) confirmed item\(items.count == 1 ? "" : "s") from \(preview.sourceName)",
                destination: preview.normalizedDestination,
                items: items,
                sourceName: preview.sourceName
            )
            modelContext?.insert(trip)
            trips.insert(trip, at: 0)
            selectedTripID = trip.id
            importMessage = "Trip created: \(trip.title)"
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

    private func preparePreviewItemsForStorage(_ items: [ItineraryItem], sourceName: String) {
        let now = Date()
        for item in items {
            item.sourceName = sourceName
            item.updatedAt = now
            modelContext?.insert(item)
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

    private func refreshPreviewFields() {
        guard let preview = extractedPreview else { return }
        extractedPreview?.fields = ConfirmationParser.fields(for: preview.items, sourceName: preview.sourceName)
    }

    private func tripIndexForMerge(with incomingItems: [ItineraryItem]) -> Int? {
        if let selectedTripID,
           let selectedIndex = trips.firstIndex(where: { $0.id == selectedTripID }),
           shouldMerge(incomingItems, into: trips[selectedIndex], allowDateOnlyMatch: true) {
            return selectedIndex
        }

        return trips.indices.first { index in
            shouldMerge(incomingItems, into: trips[index], allowDateOnlyMatch: false)
        }
    }

    private func shouldMerge(_ incomingItems: [ItineraryItem], into trip: Trip, allowDateOnlyMatch: Bool) -> Bool {
        let incomingDates = Set(incomingItems.compactMap { dateKey(from: $0.time) })
        let tripDates = Set(trip.items.compactMap { dateKey(from: $0.time) })
        let sharesDate = !incomingDates.isDisjoint(with: tripDates)

        let incomingPlaces = placeTokens(for: incomingItems)
        let tripPlaces = placeTokens(for: trip.items)
        let sharesPlace = !incomingPlaces.isDisjoint(with: tripPlaces)

        return sharesDate && (sharesPlace || allowDateOnlyMatch || hasComplementaryTravelKinds(incomingItems, trip.items))
    }

    private func hasComplementaryTravelKinds(_ incomingItems: [ItineraryItem], _ tripItems: [ItineraryItem]) -> Bool {
        let incomingKinds = Set(incomingItems.map(\.kind))
        let tripKinds = Set(tripItems.map(\.kind))

        return (incomingKinds.contains(.flight) && tripKinds.contains(.hotel))
            || (incomingKinds.contains(.hotel) && tripKinds.contains(.flight))
    }

    private func uniqueItems(from items: [ItineraryItem]) -> [ItineraryItem] {
        deduplicatedItems(from: items).unique
    }

    private func deduplicatedItems(from items: [ItineraryItem]) -> (unique: [ItineraryItem], duplicates: [ItineraryItem]) {
        var indexesByKey: [String: Int] = [:]
        var unique: [ItineraryItem] = []
        var duplicates: [ItineraryItem] = []

        for item in items {
            let key = normalizedItemKey(for: item)
            if let existingIndex = indexesByKey[key] {
                let existing = unique[existingIndex]
                if duplicatePreferenceScore(for: item) > duplicatePreferenceScore(for: existing) {
                    unique[existingIndex] = item
                    duplicates.append(existing)
                } else {
                    duplicates.append(item)
                }
            } else {
                indexesByKey[key] = unique.count
                unique.append(item)
            }
        }

        return (unique, duplicates)
    }

    private func duplicatePreferenceScore(for item: ItineraryItem) -> Int {
        normalizedKeyText(item.location).count
            + (item.status.localizedCaseInsensitiveContains("needs") ? 0 : 50)
            + (item.confirmationCode?.isEmpty == false ? 25 : 0)
    }

    private func normalizedItemKey(for item: ItineraryItem) -> String {
        let title = normalizedKeyText(item.title)
        let time = normalizedTimeKey(item.time)

        switch item.kind {
        case .hotel:
            return [item.kind.rawValue, title, time].joined(separator: "|")
        case .flight, .transit, .event:
            return [
                item.kind.rawValue,
                title,
                time,
                normalizedKeyText(item.location)
            ]
            .joined(separator: "|")
        }
    }

    private func normalizedKeyText(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedTimeKey(_ value: String) -> String {
        normalizedKeyText(
            value
                .replacingOccurrences(of: #"(?i)\bcheck\s*-?\s*in\s*:?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\bcheck\s*-?\s*out\s*:?"#, with: "", options: .regularExpression)
        )
    }

    private func sortedItinerary(_ items: [ItineraryItem]) -> [ItineraryItem] {
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

    private func sortKey(for item: ItineraryItem) -> (date: Int, time: Int, kind: Int) {
        let parsedDate = parsedDateTime(from: item.time)
        return (
            date: parsedDate.map { $0.month * 100 + $0.day } ?? Int.max,
            time: parsedDate.map { $0.hour * 60 + $0.minute } ?? Int.max,
            kind: kindSortOrder(item.kind)
        )
    }

    private func kindSortOrder(_ kind: ItineraryKind) -> Int {
        switch kind {
        case .flight: 0
        case .transit: 1
        case .hotel: 2
        case .event: 3
        }
    }

    private func tripTitle(for items: [ItineraryItem], fallback: String, preferredDestination: String? = nil) -> String {
        if let longestStayPlace = longestStayPlaceName(from: items) {
            return longestStayPlace
        }

        if let destination = destinationName(from: items) {
            return destination
        }

        if let preferredDestination = normalizedPlaceName(preferredDestination), !preferredDestination.isEmpty {
            return preferredDestination
        }

        return fallback
            .replacingOccurrences(of: "Trip to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Stay at ", with: "", options: .caseInsensitive)
    }

    private func destinationName(from items: [ItineraryItem]) -> String? {
        if let flight = items.first(where: { $0.kind == .flight }),
           let destination = flight.location.components(separatedBy: " to ").last {
            return cityName(from: destination)
        }

        if let hotel = items.first(where: { $0.kind == .hotel }) {
            return cityName(from: hotel.location)
        }

        return nil
    }

    private func heroImageSearchTerms(for trip: Trip) -> [String] {
        uniquePlaceNames([
            trip.title,
            longestStayPlaceName(from: trip.items),
            firstTripPointName(from: trip.items),
            destinationName(from: trip.items)
        ])
    }

    private func firstTripPointName(from items: [ItineraryItem]) -> String? {
        guard let firstItem = items.first else { return nil }

        if firstItem.kind == .flight,
           let destination = firstItem.location.components(separatedBy: " to ").last {
            return cityName(from: destination)
        }

        return cityName(from: firstItem.location)
    }

    private func longestStayPlaceName(from items: [ItineraryItem]) -> String? {
        items
            .compactMap { item -> (place: String, duration: Int)? in
                guard item.kind == .hotel else {
                    return nil
                }

                guard let duration = durationMinutes(from: item.time),
                      let place = placeName(for: item) else {
                    return nil
                }

                return (place, duration)
            }
            .max { $0.duration < $1.duration }
            .map(\.place)
    }

    private func placeName(for item: ItineraryItem) -> String? {
        switch item.kind {
        case .flight, .transit:
            if let destination = item.location.components(separatedBy: " to ").last {
                return cityName(from: destination)
            }
        case .hotel, .event:
            return cityName(from: item.location)
        }

        return normalizedPlaceName(item.location)
    }

    private func uniquePlaceNames(_ values: [String?]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap(normalizedPlaceName).filter { value in
            seen.insert(value.lowercased()).inserted
        }
    }

    private func tripDates(for items: [ItineraryItem], fallback: String) -> String {
        let dates = items.flatMap { parsedDateTimes(from: $0.time) }
        guard let first = dates.min(by: { ($0.month, $0.day) < ($1.month, $1.day) }) else {
            return fallback
        }

        guard let last = dates.max(by: { ($0.month, $0.day) < ($1.month, $1.day) }),
              first.month != last.month || first.day != last.day else {
            return "\(first.monthName) \(first.day)"
        }

        if first.month == last.month {
            return "\(first.monthName) \(first.day)-\(last.day)"
        }

        return "\(first.monthName) \(first.day)-\(last.monthName) \(last.day)"
    }

    private func summaryText(for trip: Trip) -> String {
        guard !trip.items.isEmpty else {
            return "No confirmed items yet"
        }

        return "\(trip.items.count) confirmed item\(trip.items.count == 1 ? "" : "s") in one travel chain"
    }

    private func combinedSourceName(_ existing: String, _ incoming: String) -> String {
        existing.localizedCaseInsensitiveContains(incoming) ? existing : "\(existing) + \(incoming)"
    }

    private func placeTokens(for items: [ItineraryItem]) -> Set<String> {
        let ignoredWords: Set<String> = [
            "airport", "terminal", "hotel", "flight", "check", "needed", "confirmed",
            "the", "and", "from", "with", "to", "at", "in", "on"
        ]

        return Set(
            items
                .flatMap { [$0.title, $0.location] }
                .flatMap { value in
                    value
                        .lowercased()
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { $0.count > 2 && !ignoredWords.contains($0) }
                }
        )
    }

    private func dateKey(from time: String) -> String? {
        parsedDateTime(from: time).map { "\($0.month)-\($0.day)" }
    }

    private func parsedDateTime(from value: String) -> (month: Int, monthName: String, day: Int, hour: Int, minute: Int)? {
        let pattern = #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{1,2})(?:,\s*(\d{1,2}):(\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let monthRange = Range(match.range(at: 1), in: value),
              let dayRange = Range(match.range(at: 2), in: value) else {
            return nil
        }

        let monthName = String(value[monthRange]).prefix(3).capitalized
        guard let month = monthNumbers[String(monthName)],
              let day = Int(value[dayRange]) else {
            return nil
        }

        let hour = Range(match.range(at: 3), in: value).flatMap { Int(value[$0]) } ?? 23
        let minute = Range(match.range(at: 4), in: value).flatMap { Int(value[$0]) } ?? 59
        return (month, String(monthName), day, hour, minute)
    }

    private func durationMinutes(from value: String) -> Int? {
        let dateTimes = parsedDateTimes(from: value)
        guard let first = dateTimes.first, let last = dateTimes.dropFirst().last else {
            return nil
        }

        let firstMinutes = first.month * 31 * 24 * 60 + first.day * 24 * 60 + first.hour * 60 + first.minute
        let lastMinutes = last.month * 31 * 24 * 60 + last.day * 24 * 60 + last.hour * 60 + last.minute
        return max(0, lastMinutes - firstMinutes)
    }

    private func parsedDateTimes(from value: String) -> [(month: Int, monthName: String, day: Int, hour: Int, minute: Int)] {
        let pattern = #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{1,2})(?:,\s*(\d{1,2}):(\d{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
            guard let monthRange = Range(match.range(at: 1), in: value),
                  let dayRange = Range(match.range(at: 2), in: value) else {
                return nil
            }

            let monthName = String(value[monthRange]).prefix(3).capitalized
            guard let month = monthNumbers[String(monthName)],
                  let day = Int(value[dayRange]) else {
                return nil
            }

            let hour = Range(match.range(at: 3), in: value).flatMap { Int(value[$0]) } ?? 23
            let minute = Range(match.range(at: 4), in: value).flatMap { Int(value[$0]) } ?? 59
            return (month, String(monthName), day, hour, minute)
        }
    }

    private var monthNumbers: [String: Int] {
        [
            "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4,
            "May": 5, "Jun": 6, "Jul": 7, "Aug": 8,
            "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12
        ]
    }

    private func cityName(from location: String) -> String {
        let suffixes = [
            " Fiumicino", " Heathrow", " Gatwick", " Airport", " Terminal 1",
            " Terminal 2", " Terminal 3", " Terminal 4", " Terminal 5"
        ]

        return suffixes.reduce(location) { result, suffix in
            result.replacingOccurrences(of: suffix, with: "", options: .caseInsensitive)
        }
        .replacingOccurrences(of: #".*,\s*\d{4,6}\s+([^,]+),.*"#, with: "$1", options: .regularExpression)
        .replacingOccurrences(of: #"\s*\([A-Z]{3}\)"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func normalizedPlaceName(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = cityName(from: value)
            .replacingOccurrences(of: "Trip to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Stay at ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        return normalized.isEmpty ? nil : normalized
    }
}

private struct VercelConfirmationExtractor {
    private let session: URLSession
    private let baseURL: URL?

    init(
        session: URLSession = .shared,
        baseURL: URL? = VoyaAPIConfiguration.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func extract(from document: ImportedDocument) async throws -> ExtractionPreview {
        guard let baseURL else {
            throw VercelExtractionError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/extract"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 35
        request.httpBody = try JSONEncoder().encode(
            VercelExtractionRequest(sourceName: document.name, text: document.text)
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw VercelExtractionError.badResponse
        }

        let decoded = try JSONDecoder().decode(VercelExtractionResponse.self, from: data)
        let items = decoded.items.map(\.itineraryItem)

        return ExtractionPreview(
            sourceName: document.name,
            type: decoded.type,
            title: decoded.title,
            normalizedDestination: decoded.normalizedDestination,
            primaryTime: decoded.primaryTime,
            confidence: decoded.confidence,
            fields: ConfirmationParser.fields(for: items, sourceName: document.name),
            items: items,
            warnings: decoded.warnings
        )
    }
}

private enum VoyaAPIConfiguration {
    static var baseURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "VOYA_API_BASE_URL") as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return nil
        }

        return URL(string: trimmed)
    }
}

private struct VercelExtractionRequest: Encodable {
    let sourceName: String
    let text: String
}

private struct VercelExtractionResponse: Decodable {
    let type: String
    let title: String
    let normalizedDestination: String?
    let primaryTime: String
    let confidence: Double
    let items: [VercelItineraryItem]
    let warnings: [String]
}

private struct VercelItineraryItem: Decodable {
    let kind: String
    let title: String
    let time: String
    let location: String
    let status: String

    var itineraryItem: ItineraryItem {
        ItineraryItem(
            kind: itineraryKind,
            title: title,
            time: time,
            location: location,
            status: status
        )
    }

    private var itineraryKind: ItineraryKind {
        switch kind.lowercased() {
        case "flight":
            .flight
        case "hotel", "accommodation", "stay":
            .hotel
        case "transit", "train", "bus", "car":
            .transit
        default:
            .event
        }
    }
}

private enum VercelExtractionError: Error {
    case notConfigured
    case badResponse
}

enum ConfirmationParser {
    static func extract(from document: ImportedDocument) -> ExtractionPreview {
        let text = document.text
        var items: [ItineraryItem] = []
        var warnings: [String] = []

        items.append(contentsOf: parseFlights(from: text))

        if let hotel = parseHotel(from: text, fallbackLocation: items.first?.location) {
            items.append(hotel)
        }

        if let event = parseEvent(from: text, fallbackTime: items.first?.time) {
            items.append(event)
        }

        if items.isEmpty {
            warnings.append("No clear flight, hotel, or event was detected. Review the text and edit the draft.")
            items.append(
                ItineraryItem(
                    kind: .event,
                    title: firstUsefulLine(in: text) ?? "Imported confirmation",
                    time: firstDateTime(in: text) ?? "Date needed",
                    location: "Location needed",
                    status: "Needs review"
                )
            )
        }

        let title = tripTitle(from: items)
        let confidence = confidenceScore(for: items, warnings: warnings)

        return ExtractionPreview(
            sourceName: document.name,
            type: typeLabel(for: items),
            title: title,
            normalizedDestination: normalizedDestination(from: items),
            primaryTime: items.first?.time ?? "Date needed",
            confidence: confidence,
            fields: fields(for: items, sourceName: document.name),
            items: items,
            warnings: warnings
        )
    }

    static func fields(for items: [ItineraryItem], sourceName: String) -> [ExtractedField] {
        var fields = [ExtractedField(label: "Source", value: sourceName)]
        for item in items {
            fields.append(ExtractedField(label: item.kind.rawValue, value: item.title))
            fields.append(ExtractedField(label: "Time", value: item.time))
            fields.append(ExtractedField(label: "Place", value: item.location))
        }
        return fields
    }

    private static func parseFlights(from text: String) -> [ItineraryItem] {
        let flightNumbers = allMatches(in: text, pattern: #"\b[A-Z]{2}\s?\d{2,4}\b"#)
            .map { $0.value.replacingOccurrences(of: " ", with: "") }
        guard !flightNumbers.isEmpty else { return [] }

        let routes = allRouteParts(in: text)
        let dateTimes = departureDateTimes(in: text)
        let segmentCount = inferredFlightSegmentCount(flightNumberCount: flightNumbers.count, routeCount: routes.count)

        return flightNumbers.prefix(segmentCount).enumerated().map { index, flightNumber in
            let route = routeForFlight(at: index, flightCount: flightNumbers.count, routes: routes)
            let destination = route?.to ?? "destination"
            let title = "\(flightNumber) to \(destination)"
            let location = route.map { "\($0.from) to \($0.to)" } ?? "Airport details needed"

            return ItineraryItem(
                kind: .flight,
                title: title,
                time: dateTimes[safe: index] ?? firstDateTime(in: text) ?? "Departure time needed",
                location: location,
                status: "Needs terminal check"
            )
        }
    }

    private static func inferredFlightSegmentCount(flightNumberCount: Int, routeCount: Int) -> Int {
        guard routeCount > 0 else {
            return min(flightNumberCount, 1)
        }

        if flightNumberCount == 2, routeCount == 1 {
            return 2
        }

        return min(flightNumberCount, routeCount)
    }

    private static func parseHotel(from text: String, fallbackLocation: String?) -> ItineraryItem? {
        let patterns = [
            #"(?i)\bHotel\s+[A-Za-z0-9 '&.-]{2,40}"#,
            #"(?i)\b[A-Za-z0-9 '&.-]{2,40}\s+(Hotel|Inn|Suites|Resort)\b"#
        ]

        guard let rawHotel = patterns.compactMap({ firstMatch(in: text, pattern: $0) }).first else { return nil }
        let hotel = cleanedPhrase(rawHotel)
        let checkIn = labeledDateTime(in: text, labelPattern: #"check\s*-?\s*in"#)
        let checkOut = labeledDateTime(in: text, labelPattern: #"check\s*-?\s*out"#)
        let time: String
        if let checkIn, let checkOut {
            time = "\(dateTimeWithDefault(checkIn, time: "15:00")) - \(dateTimeWithDefault(checkOut, time: "11:00"))"
        } else if let checkIn {
            time = dateTimeWithDefault(checkIn, time: "15:00")
        } else {
            time = "Check-in time needed"
        }
        let destination = routeParts(in: text)?.to ?? fallbackLocation ?? "Address needed"

        return ItineraryItem(
            kind: .hotel,
            title: hotel,
            time: time,
            location: destination,
            status: "Confirmed"
        )
    }

    private static func parseEvent(from text: String, fallbackTime: String?) -> ItineraryItem? {
        guard text.localizedCaseInsensitiveContains("ticket") || text.localizedCaseInsensitiveContains("reservation") else {
            return nil
        }

        let event = firstMatch(in: text, pattern: #"(?i)(ticket|reservation)\s*[:#-]?\s*[A-Za-z0-9 '&.-]{3,50}"#)
        return ItineraryItem(
            kind: .event,
            title: cleanedPhrase(event ?? "Event reservation"),
            time: firstDateTime(in: text) ?? fallbackTime ?? "Event time needed",
            location: routeParts(in: text)?.to ?? "Venue needed",
            status: "Ticket saved"
        )
    }

    private static func tripTitle(from items: [ItineraryItem]) -> String {
        if let flight = items.first(where: { $0.kind == .flight }),
           let destination = flight.location.components(separatedBy: " to ").last {
            return "Trip to \(destination)"
        }

        if let hotel = items.first(where: { $0.kind == .hotel }) {
            return "Stay at \(hotel.title)"
        }

        return items.first?.title ?? "Imported trip"
    }

    private static func normalizedDestination(from items: [ItineraryItem]) -> String? {
        if let hotel = items.first(where: { $0.kind == .hotel }) {
            return cleanedPhrase(hotel.location)
        }

        if let flight = items.first(where: { $0.kind == .flight }),
           let destination = flight.location.components(separatedBy: " to ").last {
            return cleanedPhrase(destination)
        }

        return items.first.map { cleanedPhrase($0.location) }
    }

    private static func typeLabel(for items: [ItineraryItem]) -> String {
        let uniqueKinds = Array(Set(items.map(\.kind.rawValue))).sorted()
        return uniqueKinds.joined(separator: " + ")
    }

    private static func confidenceScore(for items: [ItineraryItem], warnings: [String]) -> Double {
        let missingCount = items.flatMap { [$0.title, $0.time, $0.location] }
            .filter { $0.localizedCaseInsensitiveContains("needed") }
            .count
        let score = 0.94 - Double(missingCount) * 0.14 - Double(warnings.count) * 0.18
        return max(0.42, min(score, 0.96))
    }

    private static func routeParts(in text: String) -> (from: String, to: String)? {
        allRouteParts(in: text).first
    }

    private static func allRouteParts(in text: String) -> [(from: String, to: String)] {
        allMatches(in: text, pattern: #"(?i)(from\s+)?([A-Za-z ]{3,45})\s+to\s+([A-Za-z ]{3,45})(,|\.|\n|$)"#)
            .compactMap { match in
                let normalized = match.value
            .replacingOccurrences(of: "from ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
                let parts = splitRoute(normalized)
                guard parts.count >= 2 else { return nil }

                return (
                    from: cleanedPhrase(parts[0]),
                    to: cleanedPhrase(parts[1])
                )
            }
    }

    private static func splitRoute(_ value: String) -> [String] {
        guard let range = value.range(of: " to ", options: .caseInsensitive) else {
            return []
        }

        return [
            String(value[..<range.lowerBound]),
            String(value[range.upperBound...])
        ]
    }

    private static func routeForFlight(
        at index: Int,
        flightCount: Int,
        routes: [(from: String, to: String)]
    ) -> (from: String, to: String)? {
        if let route = routes[safe: index] {
            return route
        }

        guard flightCount == 2, routes.count == 1, index == 1, let outbound = routes.first else {
            return nil
        }

        return (from: outbound.to, to: outbound.from)
    }

    private static func firstDateTime(in text: String) -> String? {
        allDateTimes(in: text).first
    }

    private static func labeledDateTime(in text: String, labelPattern: String) -> String? {
        let match = firstMatch(
            in: text,
            pattern: #"(?i)"# + labelPattern + #"[:\s]+[A-Z][a-z]{2,8}\s+\d{1,2}(?:,\s*\d{1,2}:\d{2})?"#
        )
        return match.flatMap(firstDateTime)
    }

    private static func dateTimeWithDefault(_ value: String, time: String) -> String {
        value.contains(":") ? value : "\(value), \(time)"
    }

    private static func departureDateTimes(in text: String) -> [String] {
        let departureLines = text.components(separatedBy: .newlines)
            .filter { line in
                let lowercasedLine = line.lowercased()
                return lowercasedLine.contains("departure")
                    || lowercasedLine.contains("depart")
                    || lowercasedLine.contains("outbound")
            }
            .flatMap(allDateTimes)

        return departureLines.isEmpty ? allDateTimes(in: text) : departureLines
    }

    private static func allDateTimes(in text: String) -> [String] {
        let dates = allMatches(in: text, pattern: #"\b[A-Z][a-z]{2,8}\s+\d{1,2}(,\s*\d{1,2}:\d{2})?"#)
            .map(\.value)
        let numericTimes = allMatches(in: text, pattern: #"\b\d{1,2}:\d{2}\b"#)
            .map(\.value)

        return dates.enumerated().map { index, date in
            if date.contains(":") {
                return cleanedPhrase(date)
            }

            if let numericTime = numericTimes[safe: index] {
                return "\(cleanedPhrase(date)), \(numericTime)"
            }

            return cleanedPhrase(date)
        }
    }

    private static func firstUsefulLine(in text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map(cleanedPhrase)
            .first { $0.count > 5 }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        allMatches(in: text, pattern: pattern).first?.value
    }

    private static func allMatches(in text: String, pattern: String) -> [(value: String, range: Range<String.Index>)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return (String(text[swiftRange]), swiftRange)
        }
    }

    private static func cleanedPhrase(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
