import Foundation
import SwiftData
import SwiftUI

enum TripMood: String, CaseIterable, Identifiable {
    case warm = "Warm"
    case food = "Food"
    case culture = "Culture"
    case events = "Events"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warm: String(localized: "Warm")
        case .food: String(localized: "Food")
        case .culture: String(localized: "Culture")
        case .events: String(localized: "Events")
        }
    }
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

enum ItineraryKind: String, CaseIterable, Codable, Sendable {
    case flight = "Flight"
    case hotel = "Hotel"
    case event = "Event"
    case transit = "Transit"

    var displayName: String {
        switch self {
        case .flight: String(localized: "Flight")
        case .hotel: String(localized: "Hotel")
        case .event: String(localized: "Event")
        case .transit: String(localized: "Transit")
        }
    }

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
    var enrichmentCacheKey: String?
    var enrichmentRawData: String?
    var enrichmentUpdatedAt: Date?
    var enrichmentExpiresAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: ItineraryKind,
        title: String,
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
        enrichmentCacheKey: String? = nil,
        enrichmentRawData: String? = nil,
        enrichmentUpdatedAt: Date? = nil,
        enrichmentExpiresAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
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
        self.enrichmentCacheKey = enrichmentCacheKey
        self.enrichmentRawData = enrichmentRawData
        self.enrichmentUpdatedAt = enrichmentUpdatedAt
        self.enrichmentExpiresAt = enrichmentExpiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTime: String {
        startsAt.map { ItineraryDateFormatter.displayTime(start: $0, end: endsAt) } ?? String(localized: "Time needed")
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
    var startLocationName: String?
    var startLocationAddress: String?
    var endLocationName: String?
    var endLocationAddress: String?

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
        rawData: String? = nil,
        startLocationName: String? = nil,
        startLocationAddress: String? = nil,
        endLocationName: String? = nil,
        endLocationAddress: String? = nil
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
        self.startLocationName = startLocationName
        self.startLocationAddress = startLocationAddress
        self.endLocationName = endLocationName
        self.endLocationAddress = endLocationAddress
    }
}

enum VoyaPreferenceKey {
    static let homeLocationName = "voya.homeLocationName"
    static let homeLocationAddress = "voya.homeLocationAddress"
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
            String(localized: "Paste or choose a confirmation first.")
        case .unreadableFile(let name):
            String(localized: "Could not read text from \(name). Try a text-based PDF or paste the confirmation.")
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

enum ItineraryDateFormatter {
    static func displayTime(start: Date, end: Date?) -> String {
        let startText = displayFormatter.string(from: start)
        guard let end else {
            return startText
        }

        if Calendar.current.isDate(start, inSameDayAs: end) {
            return "\(startText)-\(timeOnlyFormatter.string(from: end))"
        }

        return "\(startText)-\(displayFormatter.string(from: end))"
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()

    private static let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

enum DateIntervalFormatter {
    static func localizedDateRange(month: String, day: Int) -> String {
        String(localized: "\(month) \(day)")
    }

    static func localizedDateRange(month: String, startDay: Int, endDay: Int) -> String {
        String(localized: "\(month) \(startDay)-\(endDay)")
    }

    static func localizedDateRange(startMonth: String, startDay: Int, endMonth: String, endDay: Int) -> String {
        String(localized: "\(startMonth) \(startDay)-\(endMonth) \(endDay)")
    }
}

enum VoyaAppLocale {
    static var currentIdentifier: String {
        Locale.autoupdatingCurrent.identifier
    }

    static var currentLanguageCode: String {
        Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"
    }

    static var currentLanguageName: String {
        Locale.autoupdatingCurrent.localizedString(forLanguageCode: currentLanguageCode) ?? currentLanguageCode
    }
}

enum ItineraryDateParser {
    static func startDate(from value: String?) -> Date? {
        dates(from: value).first
    }

    static func endDate(from value: String?) -> Date? {
        let parsedDates = dates(from: value)
        return parsedDates.count > 1 ? parsedDates.last : nil
    }

    static func dates(from value: String?) -> [Date] {
        guard let value else { return [] }
        let normalized = value
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let isoMatches = allMatches(
            in: normalized,
            pattern: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})"#
        )
        let isoDates = isoMatches.compactMap(isoDate)
        if !isoDates.isEmpty {
            return isoDates
        }

        for format in dateFormats {
            let formatter = formatter(format)
            let matches = matchesFor(format: format, in: normalized)
                .compactMap { formatter.date(from: $0) }
            if !matches.isEmpty {
                return matches
            }

            if let date = formatter.date(from: normalized) {
                return [date]
            }
        }

        return []
    }

    private static func isoDate(from value: String) -> Date? {
        if let scheduledDate = scheduledDate(fromISODateTime: value) {
            return scheduledDate
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private static func scheduledDate(fromISODateTime value: String) -> Date? {
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let year = integerCapture(1, in: value, match: match),
              let month = integerCapture(2, in: value, match: match),
              let day = integerCapture(3, in: value, match: match),
              let hour = integerCapture(4, in: value, match: match),
              let minute = integerCapture(5, in: value, match: match) else {
            return nil
        }

        return Calendar.current.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: integerCapture(6, in: value, match: match) ?? 0
            )
        )
    }

    private static func integerCapture(_ index: Int, in value: String, match: NSTextCheckingResult) -> Int? {
        guard let range = Range(match.range(at: index), in: value) else {
            return nil
        }

        return Int(value[range])
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatter.defaultDate = Calendar.current.date(
            from: DateComponents(year: Calendar.current.component(.year, from: Date()))
        )
        return formatter
    }

    private static func matchesFor(format: String, in value: String) -> [String] {
        switch format {
        case "EEEE, MMMM d, yyyy", "EEE, MMM d, yyyy":
            return allMatches(in: value, pattern: #"\b[A-Z][a-z]{2,8},?\s+[A-Z][a-z]{2,8}\s+\d{1,2},\s+\d{4}\b"#)
        case "MMM d, yyyy", "MMMM d, yyyy":
            return allMatches(in: value, pattern: #"\b[A-Z][a-z]{2,8}\s+\d{1,2},\s+\d{4}\b"#)
        case "MMM d, yyyy h:mm a", "MMMM d, yyyy h:mm a":
            return allMatches(in: value, pattern: #"\b[A-Z][a-z]{2,8}\s+\d{1,2},\s+\d{4}\s+\d{1,2}:\d{2}\s?(?:AM|PM|am|pm)\b"#)
        case "MMM d, HH:mm", "MMMM d, HH:mm":
            return allMatches(in: value, pattern: #"\b[A-Z][a-z]{2,8}\s+\d{1,2},\s*\d{1,2}:\d{2}\b"#)
        case "MMM d", "MMMM d":
            return allMatches(in: value, pattern: #"\b[A-Z][a-z]{2,8}\s+\d{1,2}\b"#)
        case "d MMM yyyy HH:mm", "d MMMM yyyy HH:mm":
            return allMatches(in: value, pattern: #"\b\d{1,2}\s+[A-Z][a-z]{2,8}\s+\d{4}\s+\d{1,2}:\d{2}\b"#)
        case "d MMM yyyy", "d MMMM yyyy":
            return allMatches(in: value, pattern: #"\b\d{1,2}\s+[A-Z][a-z]{2,8}\s+\d{4}\b"#)
        case "yyyy-MM-dd HH:mm":
            return allMatches(in: value, pattern: #"\b\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2}\b"#)
        case "yyyy-MM-dd":
            return allMatches(in: value, pattern: #"\b\d{4}-\d{2}-\d{2}\b"#)
        case "dd.MM.yyyy HH:mm":
            return allMatches(in: value, pattern: #"\b\d{1,2}\.\d{1,2}\.\d{4}\s+\d{1,2}:\d{2}\b"#)
        case "dd.MM.yyyy":
            return allMatches(in: value, pattern: #"\b\d{1,2}\.\d{1,2}\.\d{4}\b"#)
        case "MM/dd/yyyy HH:mm", "dd/MM/yyyy HH:mm":
            return allMatches(in: value, pattern: #"\b\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}\b"#)
        case "MM/dd/yyyy", "dd/MM/yyyy":
            return allMatches(in: value, pattern: #"\b\d{1,2}/\d{1,2}/\d{4}\b"#)
        default:
            return []
        }
    }

    private static func allMatches(in value: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }
    }

    private static let dateFormats = [
        "EEEE, MMMM d, yyyy",
        "EEE, MMM d, yyyy",
        "MMM d, yyyy h:mm a",
        "MMMM d, yyyy h:mm a",
        "MMM d, yyyy",
        "MMMM d, yyyy",
        "MMM d, HH:mm",
        "MMMM d, HH:mm",
        "MMM d",
        "MMMM d",
        "d MMM yyyy HH:mm",
        "d MMMM yyyy HH:mm",
        "d MMM yyyy",
        "d MMMM yyyy",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "dd.MM.yyyy HH:mm",
        "dd.MM.yyyy",
        "MM/dd/yyyy HH:mm",
        "MM/dd/yyyy",
        "dd/MM/yyyy HH:mm",
        "dd/MM/yyyy"
    ]
}

@MainActor
final class VoyaStore: ObservableObject {
    static let pastedConfirmationSourceName = String(localized: "Pasted confirmation")

    private var modelContext: ModelContext?

    @Published var inspirationText = String(localized: "Warm 4-day trip under $700 with easy transit")
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

    var activeTrips: [Trip] {
        activeTrips(at: Date())
    }

    var archivedTrips: [Trip] {
        archivedTrips(at: Date())
    }

    var currentOrUpcomingTrip: Trip? {
        currentOrUpcomingTrip(at: Date())
    }

    let recommendations = SampleData.recommendations
    let alerts = SampleData.alerts

    var itinerary: [ItineraryItem] {
        selectedTrip.map { sortedItinerary($0.items) } ?? []
    }

    func itinerary(for trip: Trip) -> [ItineraryItem] {
        sortedItinerary(trip.items)
    }

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
            syncTripNotifications()
        } catch {
            importMessage = String(localized: "Could not load saved trips")
            trips = []
        }
    }

    private func activeTrips(at date: Date) -> [Trip] {
        trips.filter { !isArchived($0, at: date) }
    }

    private func archivedTrips(at date: Date) -> [Trip] {
        trips.filter { isArchived($0, at: date) }
    }

    private func currentOrUpcomingTrip(at date: Date) -> Trip? {
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

    private func isArchived(_ trip: Trip, at date: Date) -> Bool {
        guard let interval = activeInterval(for: trip) else {
            return false
        }

        return interval.end < Calendar.current.startOfDay(for: date)
    }

    private func activeInterval(for trip: Trip) -> DateInterval? {
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

    private func saveTrips() {
        guard let modelContext else { return }

        do {
            try modelContext.save()
            fetchTrips()
        } catch {
            importMessage = String(localized: "Could not save trip changes")
        }
    }

    private func removeDuplicateItemsFromLoadedTrips() {
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

    private func syncTripNotifications() {
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
        importMessage = String(localized: "Recognizing \(document.name)...")

        do {
            extractedPreview = try await VercelConfirmationExtractor().extract(from: document)
            importMessage = String(localized: "AI recognized \(document.name)")
        } catch {
            extractedPreview = ConfirmationParser.extract(from: document)
            importMessage = aiExtractionFailureMessage(for: error)
        }

        isExtractingConfirmation = false
    }

    private func aiExtractionFailureMessage(for error: Error) -> String {
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
        normalizePreviewItemsForStorage(preview.items)
        preparePreviewItemsForStorage(preview.items, sourceName: preview.sourceName)

        if let matchingTripIndex = tripIndexForMerge(with: preview.items) {
            let trip = trips[matchingTripIndex]
            let previousItemCount = trip.items.count
            let deduplicated = deduplicatedItems(from: trip.items + preview.items)
            trip.items = sortedItinerary(deduplicated.unique)
            trip.dates = tripDates(for: trip.items, fallback: trip.dates)
            trip.summary = summaryText(for: trip)
            trip.sourceName = combinedSourceName(trip.sourceName, preview.sourceName)
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
                sourceName: preview.sourceName
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

    private func apply(_ draft: ItineraryItemDraft, to item: ItineraryItem) {
        item.kind = draft.kind
        item.title = draft.title
        item.startsAt = draft.effectiveStartsAt
        item.endsAt = draft.effectiveEndsAt
        item.location = draft.location
        item.status = draft.status
        item.updatedAt = Date()
    }

    private func normalizePreviewItemsForStorage(_ items: [ItineraryItem]) {
        for item in items {
            item.title = normalizedTitle(item.title)
            item.location = normalizedLocation(item.location)
            item.status = normalizedStatus(item.status)
            item.endsAt = item.startsAt == nil ? nil : item.endsAt
        }
    }

    private func normalizedTitle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? String(localized: "Untitled item")
    }

    private func normalizedLocation(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? String(localized: "Location needed")
    }

    private func normalizedStatus(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? String(localized: "Needs review")
    }

    private func preparePreviewItemsForStorage(_ items: [ItineraryItem], sourceName: String) {
        let now = Date()
        for item in items {
            item.sourceName = sourceName
            item.updatedAt = now
            modelContext?.insert(item)
        }
    }

    private func deleteItems(_ items: [ItineraryItem]) {
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
        let incomingDates = Set(incomingItems.flatMap(dateKeys))
        let tripDates = Set(trip.items.flatMap(dateKeys))
        let sharesDate = !incomingDates.isDisjoint(with: tripDates)
        let hasNearbyDates = dateRangesAreNear(incomingItems, trip.items)

        let incomingPlaces = placeTokens(for: incomingItems)
        let tripPlaces = placeTokens(for: trip.items)
        let sharesPlace = !incomingPlaces.isDisjoint(with: tripPlaces)
        let complementaryKinds = hasComplementaryTravelKinds(incomingItems, trip.items)

        return (sharesDate || hasNearbyDates) && (sharesPlace || allowDateOnlyMatch || complementaryKinds)
    }

    private func hasComplementaryTravelKinds(_ incomingItems: [ItineraryItem], _ tripItems: [ItineraryItem]) -> Bool {
        let incomingKinds = Set(incomingItems.map(\.kind))
        let tripKinds = Set(tripItems.map(\.kind))

        return (incomingKinds.contains(.flight) && tripKinds.contains(.hotel))
            || (incomingKinds.contains(.hotel) && tripKinds.contains(.flight))
    }

    private func deduplicatedItems(from items: [ItineraryItem]) -> (unique: [ItineraryItem], duplicates: [ItineraryItem]) {
        var unique: [ItineraryItem] = []
        var duplicates: [ItineraryItem] = []

        for item in items {
            if let existingIndex = unique.firstIndex(where: { areDuplicateItems($0, item) }) {
                let existing = unique[existingIndex]
                if duplicatePreferenceScore(for: item) > duplicatePreferenceScore(for: existing) {
                    unique[existingIndex] = item
                    duplicates.append(existing)
                } else {
                    duplicates.append(item)
                }
            } else {
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

    private func areDuplicateItems(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        guard first.kind == second.kind else { return false }

        switch first.kind {
        case .flight:
            return duplicateFlight(first, second)
        case .hotel:
            return duplicateHotel(first, second)
        case .transit, .event:
            return duplicateGeneralItem(first, second)
        }
    }

    private func duplicateFlight(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        let firstFlightNumbers = flightNumbers(in: first.title)
        let secondFlightNumbers = flightNumbers(in: second.title)
        let sharesFlightNumber = !firstFlightNumbers.isEmpty && !firstFlightNumbers.isDisjoint(with: secondFlightNumbers)
        let sameRoute = routeKey(for: first.location) == routeKey(for: second.location)

        guard sharesFlightNumber && sameRoute else { return false }
        return sameTravelDay(first, second) || timesAreClose(first.startsAt, second.startsAt, tolerance: 6 * 60 * 60)
    }

    private func duplicateHotel(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        let sameName = normalizedKeyText(first.title) == normalizedKeyText(second.title)
        let samePlace = !placeTokens(for: [first]).isDisjoint(with: placeTokens(for: [second]))
            || normalizedKeyText(first.location) == normalizedKeyText(second.location)

        guard sameName && samePlace else { return false }
        return dateRangesOverlap(first, second) || sameTravelDay(first, second)
    }

    private func duplicateGeneralItem(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        normalizedKeyText(first.title) == normalizedKeyText(second.title)
            && normalizedKeyText(first.location) == normalizedKeyText(second.location)
            && (sameTravelDay(first, second) || timesAreClose(first.startsAt, second.startsAt, tolerance: 2 * 60 * 60))
    }

    private func flightNumbers(in value: String) -> Set<String> {
        let pattern = #"\b[A-Z]{2}\s?\d{2,4}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(value.startIndex..., in: value)
        return Set(
            regex.matches(in: value, range: range).compactMap { match in
                Range(match.range, in: value).map {
                    value[$0].uppercased().replacingOccurrences(of: " ", with: "")
                }
            }
        )
    }

    private func routeKey(for location: String) -> String {
        normalizedKeyText(location)
            .replacingOccurrences(of: #"(^|\s)(from|to)($|\s)"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sameTravelDay(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        guard let firstDate = first.startsAt, let secondDate = second.startsAt else {
            return false
        }

        return Calendar.current.isDate(firstDate, inSameDayAs: secondDate)
    }

    private func timesAreClose(_ first: Date?, _ second: Date?, tolerance: TimeInterval) -> Bool {
        guard let first, let second else { return false }
        return abs(first.timeIntervalSince(second)) <= tolerance
    }

    private func dateRangesOverlap(_ first: ItineraryItem, _ second: ItineraryItem) -> Bool {
        guard let firstStart = first.startsAt, let secondStart = second.startsAt else {
            return false
        }

        let firstEnd = first.endsAt ?? firstStart
        let secondEnd = second.endsAt ?? secondStart
        return firstStart <= secondEnd && secondStart <= firstEnd
    }

    private func normalizedKeyText(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        if let startsAt = item.startsAt {
            let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: startsAt)
            return (
                date: (components.month ?? 99) * 100 + (components.day ?? 99),
                time: (components.hour ?? 23) * 60 + (components.minute ?? 59),
                kind: kindSortOrder(item.kind)
            )
        }

        return (
            date: Int.max,
            time: Int.max,
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

                guard let duration = durationMinutes(for: item),
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
        let storedDates = items.flatMap { item in
            [item.startsAt, item.endsAt].compactMap { $0 }
        }

        if let first = storedDates.min(),
           let last = storedDates.max() {
            return tripDates(from: first, to: last)
        }

        return fallback
    }

    private func tripDates(from start: Date, to end: Date) -> String {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.month, .day], from: start)
        let endComponents = calendar.dateComponents([.month, .day], from: end)
        let startMonth = monthAbbreviation(for: startComponents.month)
        let endMonth = monthAbbreviation(for: endComponents.month)
        let startDay = startComponents.day ?? 1
        let endDay = endComponents.day ?? startDay

        guard startComponents.month != endComponents.month || startDay != endDay else {
            return DateIntervalFormatter.localizedDateRange(month: startMonth, day: startDay)
        }

        if startComponents.month == endComponents.month {
            return DateIntervalFormatter.localizedDateRange(month: startMonth, startDay: startDay, endDay: endDay)
        }

        return DateIntervalFormatter.localizedDateRange(startMonth: startMonth, startDay: startDay, endMonth: endMonth, endDay: endDay)
    }

    private func monthAbbreviation(for month: Int?) -> String {
        let monthSymbols = Self.localizedMonthSymbols
        guard let month, monthSymbols.indices.contains(month - 1) else {
            return ""
        }

        return monthSymbols[month - 1]
    }

    private static let localizedMonthSymbols: [String] = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        return formatter.shortMonthSymbols
    }()

    private func summaryText(for trip: Trip) -> String {
        guard !trip.items.isEmpty else {
            return String(localized: "No confirmed items yet")
        }

        return String(localized: "\(trip.items.count) confirmed item\(trip.items.count == 1 ? "" : "s") in one travel chain")
    }

    private func summaryText(itemCount: Int, sourceName: String) -> String {
        String(localized: "\(itemCount) confirmed item\(itemCount == 1 ? "" : "s") from \(sourceName)")
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

    private func dateKeys(for item: ItineraryItem) -> [String] {
        guard let startsAt = item.startsAt else { return [] }
        let calendar = Calendar.current
        let end = item.endsAt ?? startsAt
        let startOfStart = calendar.startOfDay(for: startsAt)
        let startOfEnd = calendar.startOfDay(for: end)
        let dayCount = min(calendar.dateComponents([.day], from: startOfStart, to: startOfEnd).day ?? 0, 30)

        return (0...max(0, dayCount)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfStart).flatMap(dateKey)
        }
    }

    private func dateKey(for date: Date) -> String? {
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return nil }
        return "\(month)-\(day)"
    }

    private func dateRangesAreNear(_ firstItems: [ItineraryItem], _ secondItems: [ItineraryItem]) -> Bool {
        guard let firstRange = overallDateRange(for: firstItems),
              let secondRange = overallDateRange(for: secondItems) else {
            return false
        }

        let tolerance: TimeInterval = 36 * 60 * 60
        return firstRange.start <= secondRange.end.addingTimeInterval(tolerance)
            && secondRange.start <= firstRange.end.addingTimeInterval(tolerance)
    }

    private func overallDateRange(for items: [ItineraryItem]) -> (start: Date, end: Date)? {
        let dates = items.flatMap { item in
            [item.startsAt, item.endsAt].compactMap { $0 }
        }

        guard let start = dates.min(), let end = dates.max() else {
            return nil
        }

        return (start, end)
    }

    private func durationMinutes(for item: ItineraryItem) -> Int? {
        guard let startsAt = item.startsAt,
              let endsAt = item.endsAt else {
            return nil
        }

        return max(0, Int(endsAt.timeIntervalSince(startsAt) / 60))
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
            VercelExtractionRequest(
                sourceName: document.name,
                text: document.text,
                locale: VoyaAppLocale.currentIdentifier,
                languageCode: VoyaAppLocale.currentLanguageCode,
                languageName: VoyaAppLocale.currentLanguageName
            )
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

enum VoyaAPIConfiguration {
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

struct ItemEnrichment: Codable {
    var summary: String
    var cards: [ItemEnrichmentCard]
    var warnings: [String]
    var briefMarkdown: String
    var sections: [TravelBriefSection]
    var actions: [TravelAction]
    var routeLegs: [TravelRouteLeg]
    var imageURLs: [URL]
}

struct ItemEnrichmentCard: Codable, Identifiable {
    var id: String { "\(title)-\(value)-\(kind)" }
    var title: String
    var value: String
    var detail: String?
    var actionURL: URL?
    var kind: String
}

struct TravelBriefSection: Codable, Identifiable {
    var id: String { "\(title)-\(kind)" }
    var title: String
    var body: String
    var kind: String
}

struct TravelAction: Codable, Identifiable {
    var id: String { "\(title)-\(priority)-\(kind)" }
    var title: String
    var detail: String
    var priority: String
    var kind: String
    var actionURL: URL?
}

struct TravelRouteLeg: Codable, Identifiable {
    var id: String { "\(title)-\(destination ?? "")" }
    var title: String
    var origin: String?
    var destination: String?
    var guidance: String
    var bufferMinutes: Int?
    var mapURL: URL?
}

enum MobilityRouteMode: String, Codable {
    case drive
    case taxi
    case transit
    case walk
    case bike

    var displayName: String {
        switch self {
        case .drive: String(localized: "Own car")
        case .taxi: String(localized: "Taxi")
        case .transit: String(localized: "Public transit")
        case .walk: String(localized: "Walk")
        case .bike: String(localized: "Bike")
        }
    }

    var symbol: String {
        switch self {
        case .drive: "car"
        case .taxi: "car.fill"
        case .transit: "tram"
        case .walk: "figure.walk"
        case .bike: "bicycle"
        }
    }
}

struct MobilityPlan: Decodable {
    var providerConnected: Bool
    var provider: String
    var generatedAt: String
    var originLabel: String
    var destinationLabel: String
    var options: [MobilityRouteOption]
    var recommendation: MobilityRecommendation?
    var warnings: [String]

    var recommendedOption: MobilityRouteOption? {
        guard let recommendation else {
            return options.first
        }

        return options.first { $0.mode == recommendation.mode } ?? options.first
    }

    var publicTransitOption: MobilityRouteOption? {
        options.first { $0.mode == .transit && $0.durationMinutes != nil }
            ?? options.first { $0.mode == .transit }
    }

    var defaultOption: MobilityRouteOption? {
        publicTransitOption ?? recommendedOption
    }
}

struct MobilityRouteOption: Decodable, Identifiable {
    var id: String { "\(mode.rawValue)-\(durationMinutes ?? 0)-\(leaveBy ?? "")" }
    var mode: MobilityRouteMode
    var title: String
    var durationMinutes: Int?
    var travelMinutes: Int?
    var bufferMinutes: Int
    var distanceMeters: Int?
    var departureTime: String?
    var arrivalTime: String?
    var leaveBy: String?
    var reliability: String
    var costLevel: String
    var comfortLevel: String
    var emissionsLevel: String
    var provider: String
    var providerAttribution: String?
    var mapURL: URL
    var summary: String
    var tradeoffs: [String]
    var steps: [MobilityRouteStep]?
    var tone: String
}

struct MobilityRouteStep: Decodable, Identifiable {
    var id: String {
        "\(kind)-\(title)-\(departureStop ?? "")-\(arrivalStop ?? "")-\(departureTime ?? "")-\(arrivalTime ?? "")"
    }

    var kind: String
    var title: String
    var detail: String?
    var durationMinutes: Int?
    var distanceMeters: Int?
    var lineName: String?
    var vehicleType: String?
    var departureStop: String?
    var arrivalStop: String?
    var departureTime: String?
    var arrivalTime: String?
}

struct MobilityRecommendation: Decodable {
    var mode: MobilityRouteMode
    var title: String
    var reason: String
    var leaveBy: String?
}

struct MobilityTransferContext: Identifiable {
    var id: String
    var origin: String
    var destination: String
    var targetArrivalAt: Date?
    var targetDepartureAt: Date?
    var airportBufferMinutes: Int
    var taxiPickupBufferMinutes: Int
}

struct VercelMobilityService {
    private let session: URLSession
    private let baseURL: URL?

    init(
        session: URLSession = .shared,
        baseURL: URL? = VoyaAPIConfiguration.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    @MainActor
    func planTransfer(from originItem: ItineraryItem, to destinationItem: ItineraryItem) async throws -> MobilityPlan {
        guard let context = Self.transferContext(from: originItem, to: destinationItem) else {
            throw VercelExtractionError.badResponse
        }

        return try await planTransfer(context: context)
    }

    func planTransfer(context: MobilityTransferContext) async throws -> MobilityPlan {
        guard let baseURL else {
            throw VercelExtractionError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/mobility"))
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 25

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(
            MobilityPlanRequest(
                origin: MobilityPlace(address: context.origin),
                destination: MobilityPlace(address: context.destination),
                arrivalTime: context.targetArrivalAt,
                departureTime: context.targetDepartureAt,
                locale: VoyaAppLocale.currentIdentifier,
                modes: [.transit, .taxi, .drive],
                ownedVehicleAvailable: false,
                airportBufferMinutes: context.airportBufferMinutes,
                taxiPickupBufferMinutes: context.taxiPickupBufferMinutes
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw VercelExtractionError.badResponse
        }

        return try JSONDecoder().decode(MobilityPlan.self, from: data)
    }

    static func transferContext(from originItem: ItineraryItem, to destinationItem: ItineraryItem) -> MobilityTransferContext? {
        guard destinationItem.kind != .transit else {
            return nil
        }

        if originItem.kind == .flight,
           destinationItem.kind == .flight,
           let arrivalAirport = routeParts(in: originItem.location).last,
           let departureAirport = routeParts(in: destinationItem.location).first,
           arrivalAirport.caseInsensitiveCompare(departureAirport) == .orderedSame {
            return nil
        }

        guard let origin = transferOrigin(for: originItem),
              let destination = transferDestination(for: destinationItem),
              origin.caseInsensitiveCompare(destination) != .orderedSame else {
            return nil
        }

        return MobilityTransferContext(
            id: "\(originItem.id.uuidString)-\(destinationItem.id.uuidString)",
            origin: origin,
            destination: destination,
            targetArrivalAt: destinationItem.startsAt,
            targetDepartureAt: nil,
            airportBufferMinutes: airportBufferMinutes(for: destinationItem),
            taxiPickupBufferMinutes: 10
        )
    }

    static func startTransferContext(for trip: Trip, firstItem: ItineraryItem, defaultHomeAddress: String, defaultHomeName: String) -> MobilityTransferContext? {
        guard firstItem.kind != .transit,
              let destination = transferDestination(for: firstItem) else {
            return nil
        }

        let tripStartAddress = trip.startLocationAddress?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let homeAddress = defaultHomeAddress.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let originAddress = tripStartAddress ?? homeAddress,
              originAddress.caseInsensitiveCompare(destination) != .orderedSame else {
            return nil
        }

        let idOrigin = originAddress
            .lowercased()
            .replacingOccurrences(of: #"\W+"#, with: "-", options: .regularExpression)

        return MobilityTransferContext(
            id: "\(trip.id.uuidString)-start-\(firstItem.id.uuidString)-\(idOrigin)",
            origin: originAddress,
            destination: destination,
            targetArrivalAt: firstItem.startsAt,
            targetDepartureAt: nil,
            airportBufferMinutes: airportBufferMinutes(for: firstItem),
            taxiPickupBufferMinutes: 10
        )
    }

    static func endTransferContext(for trip: Trip, lastItem: ItineraryItem, defaultHomeAddress: String, defaultHomeName: String) -> MobilityTransferContext? {
        guard let origin = transferOrigin(for: lastItem) else {
            return nil
        }

        let tripEndAddress = trip.endLocationAddress?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let homeAddress = defaultHomeAddress.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard let destinationAddress = tripEndAddress ?? homeAddress,
              origin.caseInsensitiveCompare(destinationAddress) != .orderedSame else {
            return nil
        }

        let idDestination = destinationAddress
            .lowercased()
            .replacingOccurrences(of: #"\W+"#, with: "-", options: .regularExpression)

        return MobilityTransferContext(
            id: "\(trip.id.uuidString)-end-\(lastItem.id.uuidString)-\(idDestination)",
            origin: origin,
            destination: destinationAddress,
            targetArrivalAt: nil,
            targetDepartureAt: lastItem.endsAt ?? lastItem.startsAt,
            airportBufferMinutes: 0,
            taxiPickupBufferMinutes: 10
        )
    }

    private static func transferOrigin(for item: ItineraryItem) -> String? {
        let value = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if item.kind == .flight || item.kind == .transit {
            let parts = routeParts(in: value)
            if item.kind == .flight, parts.count < 2 {
                return nil
            }
            guard let origin = parts.last ?? value.nilIfEmpty else {
                return nil
            }
            return item.kind == .flight ? airportArrivalsAddress(origin) : origin
        }

        return value
    }

    private static func transferDestination(for item: ItineraryItem) -> String? {
        let value = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if item.kind == .flight || item.kind == .transit {
            guard let destination = routeParts(in: value).first ?? value.nilIfEmpty else {
                return nil
            }
            return item.kind == .flight ? airportDeparturesAddress(destination) : destination
        }

        return value
    }

    private static func routeParts(in value: String) -> [String] {
        value
            .replacingOccurrences(of: "→", with: " to ")
            .components(separatedBy: " to ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func airportDeparturesAddress(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.localizedCaseInsensitiveContains("departure") else {
            return normalized
        }
        return "Departures, \(normalized)"
    }

    private static func airportArrivalsAddress(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.localizedCaseInsensitiveContains("arrival") else {
            return normalized
        }
        return "Arrivals, \(normalized)"
    }

    private static func airportBufferMinutes(for item: ItineraryItem) -> Int {
        item.kind == .flight ? 120 : 0
    }
}

private struct MobilityPlanRequest: Encodable {
    var origin: MobilityPlace
    var destination: MobilityPlace
    var arrivalTime: Date?
    var departureTime: Date?
    var locale: String
    var modes: [MobilityRouteMode]
    var ownedVehicleAvailable: Bool
    var airportBufferMinutes: Int
    var taxiPickupBufferMinutes: Int
}

private struct MobilityPlace: Encodable {
    var address: String
}

enum ItemEnrichmentCache {
    private static let schemaVersion = "travel-brief-v5"

    static func key(for item: ItineraryItem) -> String {
        let dateFormatter = ISO8601DateFormatter()
        return [
            schemaVersion,
            VoyaAppLocale.currentIdentifier,
            item.kind.rawValue,
            normalized(item.title),
            normalized(item.location),
            normalized(item.status),
            item.startsAt.map { dateFormatter.string(from: $0) } ?? "",
            item.endsAt.map { dateFormatter.string(from: $0) } ?? ""
        ].joined(separator: "|")
    }

    static func freshCachedEnrichment(for item: ItineraryItem, now: Date = Date()) -> ItemEnrichment? {
        guard item.enrichmentCacheKey == key(for: item),
              let expiresAt = item.enrichmentExpiresAt,
              expiresAt > now else {
            return nil
        }

        return cachedEnrichment(for: item)
    }

    static func cachedEnrichment(for item: ItineraryItem) -> ItemEnrichment? {
        guard let rawData = item.enrichmentRawData,
              let data = rawData.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(ItemEnrichment.self, from: data)
    }

    static func clear(for item: ItineraryItem) {
        item.enrichmentCacheKey = nil
        item.enrichmentRawData = nil
        item.enrichmentUpdatedAt = nil
        item.enrichmentExpiresAt = nil
    }

    static func store(_ enrichment: ItemEnrichment, for item: ItineraryItem, now: Date = Date()) {
        guard let data = try? JSONEncoder().encode(enrichment),
              let rawData = String(data: data, encoding: .utf8) else {
            return
        }

        item.enrichmentCacheKey = key(for: item)
        item.enrichmentRawData = rawData
        item.enrichmentUpdatedAt = now
        item.enrichmentExpiresAt = expirationDate(for: item, now: now)
    }

    private static func expirationDate(for item: ItineraryItem, now: Date) -> Date {
        guard let startsAt = item.startsAt else {
            return now.addingTimeInterval(60 * 60)
        }

        if startsAt < now {
            return now.addingTimeInterval(60 * 60 * 24)
        }

        let secondsUntilStart = startsAt.timeIntervalSince(now)
        if secondsUntilStart <= 60 * 60 * 24 {
            return now.addingTimeInterval(60 * 30)
        }
        if secondsUntilStart <= 60 * 60 * 24 * 7 {
            return now.addingTimeInterval(60 * 60 * 3)
        }

        return now.addingTimeInterval(60 * 60 * 12)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}

struct VercelItemEnricher {
    private let session: URLSession
    private let baseURL: URL?

    init(
        session: URLSession = .shared,
        baseURL: URL? = VoyaAPIConfiguration.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    @MainActor
    func enrich(item: ItineraryItem, modelContext: ModelContext? = nil, forceRefresh: Bool = false) async throws -> ItemEnrichment {
        if forceRefresh {
            ItemEnrichmentCache.clear(for: item)
            try? modelContext?.save()
        } else if let cached = ItemEnrichmentCache.freshCachedEnrichment(for: item) {
            #if DEBUG
            print("[Voya] Enrichment cache hit item=\(item.id)")
            #endif
            return cached
        }

        #if DEBUG
        if ItemEnrichmentCache.cachedEnrichment(for: item) != nil {
            print("[Voya] Enrichment cache stale item=\(item.id)")
        } else {
            print("[Voya] Enrichment cache miss item=\(item.id)")
        }
        #endif

        guard let baseURL else {
            throw VercelExtractionError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/enrich"))
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 25
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(
            ItemEnrichmentRequest(
                kind: item.kind.rawValue,
                title: item.title,
                location: item.location,
                startsAt: item.startsAt,
                endsAt: item.endsAt,
                status: item.status,
                locale: VoyaAppLocale.currentIdentifier,
                languageCode: VoyaAppLocale.currentLanguageCode,
                languageName: VoyaAppLocale.currentLanguageName
            )
        )

        #if DEBUG
        if let body = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) }) {
            print("[Voya] Enrichment request \(request.url?.absoluteString ?? "<nil>") body=\(body)")
        } else {
            print("[Voya] Enrichment request \(request.url?.absoluteString ?? "<nil>")")
        }
        #endif

        let (data, response) = try await session.data(for: request)
        #if DEBUG
        if let httpResponse = response as? HTTPURLResponse {
            print("[Voya] Enrichment response status=\(httpResponse.statusCode)")
        }
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("[Voya] Enrichment response body=\(rawResponse)")
        }
        #endif
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw VercelExtractionError.badResponse
        }

        do {
            let enrichment = try JSONDecoder().decode(ItemEnrichment.self, from: data)
            ItemEnrichmentCache.store(enrichment, for: item)
            try? modelContext?.save()
            return enrichment
        } catch {
            #if DEBUG
            print("[Voya] Enrichment decode failed: \(error)")
            #endif
            throw error
        }
    }
}

struct FlightLookupCandidate: Decodable {
    var flightNumber: String
    var flightIata: String?
    var flightIcao: String?
    var operatingFlightNumber: String?
    var originAirport: String?
    var originAirportIcao: String?
    var destinationAirport: String?
    var destinationAirportIcao: String?
    var departureAt: String?
    var arrivalAt: String?
    var durationMinutes: Int?
    var departureTerminal: String?
    var departureGate: String?
    var arrivalTerminal: String?
    var arrivalGate: String?
    var baggageClaim: String?
    var aircraftType: String?
    var providerStatus: String?
    var dataMode: String?
    var confidence: Double?

    var parsedDepartureAt: Date? {
        Self.parseDate(departureAt)
    }

    var parsedArrivalAt: Date? {
        Self.parseDate(arrivalAt)
    }

    var routeText: String {
        let origin = originAirport ?? originAirportIcao
        let destination = destinationAirport ?? destinationAirportIcao
        return [origin, destination]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: " to ")
    }

    var titleText: String {
        guard let destination = destinationAirport?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return flightNumber
        }

        return "\(flightNumber) to \(destination)"
    }

    var statusText: String {
        providerStatus?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Confirmed"
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct FlightLookupResponse: Decodable {
    struct Validation: Decodable {
        var state: String
        var confidence: Double
        var reasons: [String]
    }

    var validation: Validation
    var candidate: FlightLookupCandidate?
    var warnings: [String]
}

struct VercelFlightLookupService {
    private let session: URLSession
    private let baseURL: URL?

    init(
        session: URLSession = .shared,
        baseURL: URL? = VoyaAPIConfiguration.baseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    func lookup(flightNumber: String, date: Date) async throws -> FlightLookupResponse {
        guard let baseURL else {
            throw VercelExtractionError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/flight-lookup"))
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 25
        request.httpBody = try JSONEncoder().encode(
            FlightLookupRequest(
                flightNumber: flightNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                date: Self.flightDateFormatter.string(from: date)
            )
        )

        #if DEBUG
        if let body = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) }) {
            print("[Voya] Flight lookup request \(request.url?.absoluteString ?? "<nil>") body=\(body)")
        }
        #endif

        let (data, response) = try await session.data(for: request)
        #if DEBUG
        if let httpResponse = response as? HTTPURLResponse {
            print("[Voya] Flight lookup response status=\(httpResponse.statusCode)")
        }
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("[Voya] Flight lookup response body=\(rawResponse)")
        }
        #endif

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw VercelExtractionError.badResponse
        }

        return try JSONDecoder().decode(FlightLookupResponse.self, from: data)
    }

    private static let flightDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct FlightLookupRequest: Encodable {
    var flightNumber: String
    var date: String
}

private struct ItemEnrichmentRequest: Encodable {
    var kind: String
    var title: String
    var location: String
    var startsAt: Date?
    var endsAt: Date?
    var status: String
    var locale: String
    var languageCode: String
    var languageName: String
}

private struct VercelExtractionRequest: Encodable {
    let sourceName: String
    let text: String
    let locale: String
    let languageCode: String
    let languageName: String
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
    let time: String?
    let startsAt: String?
    let endsAt: String?
    let location: String
    let status: String

    var itineraryItem: ItineraryItem {
        let parsedStartsAt = ItineraryDateParser.startDate(from: startsAt) ?? ItineraryDateParser.startDate(from: time)
        let parsedEndsAt = ItineraryDateParser.startDate(from: endsAt) ?? ItineraryDateParser.endDate(from: time)
        return ItineraryItem(
            kind: itineraryKind,
            title: title,
            location: location,
            status: status,
            startsAt: parsedStartsAt,
            endsAt: parsedEndsAt
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

        if let event = parseEvent(from: text) {
            items.append(event)
        }

        if items.isEmpty {
            warnings.append(String(localized: "No clear flight, hotel, or event was detected. Review the text and edit the draft."))
            items.append(
                ItineraryItem(
                    kind: .event,
                    title: firstUsefulLine(in: text) ?? String(localized: "Imported confirmation"),
                    location: String(localized: "Location needed"),
                    status: String(localized: "Needs review"),
                    startsAt: ItineraryDateParser.startDate(from: firstDateTime(in: text))
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
            primaryTime: items.first?.displayTime ?? String(localized: "Date needed"),
            confidence: confidence,
            fields: fields(for: items, sourceName: document.name),
            items: items,
            warnings: warnings
        )
    }

    static func fields(for items: [ItineraryItem], sourceName: String) -> [ExtractedField] {
        var fields = [ExtractedField(label: String(localized: "Source"), value: sourceName)]
        for item in items {
            fields.append(ExtractedField(label: item.kind.displayName, value: item.title))
            fields.append(ExtractedField(label: String(localized: "Time"), value: item.displayTime))
            fields.append(ExtractedField(label: String(localized: "Place"), value: item.location))
        }
        return fields
    }

    private static func parseFlights(from text: String) -> [ItineraryItem] {
        let flightNumbers = allMatches(in: text, pattern: #"\b[A-Z]{2}\s?\d{2,4}\b"#)
            .map { $0.value.replacingOccurrences(of: " ", with: "") }
        guard !flightNumbers.isEmpty else { return [] }

        let routes = allRouteParts(in: text)
        let departures = departureDateTimes(in: text)
        let arrivals = arrivalDateTimes(in: text)
        let segmentCount = inferredFlightSegmentCount(flightNumberCount: flightNumbers.count, routeCount: routes.count)

        return flightNumbers.prefix(segmentCount).enumerated().map { index, flightNumber in
            let route = routeForFlight(at: index, flightCount: flightNumbers.count, routes: routes)
            let destination = route?.to ?? String(localized: "destination")
            let title = "\(flightNumber) to \(destination)"
            let location = route.map { "\($0.from) to \($0.to)" } ?? String(localized: "Airport details needed")
            let departure = departures[safe: index] ?? firstDateTime(in: text)
            let arrival = arrivals[safe: index]
            let startsAt = ItineraryDateParser.startDate(from: departure)
            let endsAt = ItineraryDateParser.startDate(from: arrival)

            return ItineraryItem(
                kind: .flight,
                title: title,
                location: location,
                status: String(localized: "Needs terminal check"),
                startsAt: startsAt,
                endsAt: endsAt
            )
        }
    }

    private static func inferredFlightSegmentCount(flightNumberCount: Int, routeCount: Int) -> Int {
        guard routeCount > 0 else {
            return flightNumberCount
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
        let stayRange = hotelStayRange(in: text)
        let destination = routeParts(in: text)?.to ?? fallbackLocation ?? String(localized: "Address needed")

        return ItineraryItem(
            kind: .hotel,
            title: hotel,
            location: destination,
            status: String(localized: "Confirmed"),
            startsAt: stayRange?.startsAt,
            endsAt: stayRange?.endsAt
        )
    }

    private static func parseEvent(from text: String) -> ItineraryItem? {
        guard text.localizedCaseInsensitiveContains("ticket") || text.localizedCaseInsensitiveContains("reservation") else {
            return nil
        }

        let event = firstMatch(in: text, pattern: #"(?i)(ticket|reservation)\s*[:#-]?\s*[A-Za-z0-9 '&.-]{3,50}"#)
        return ItineraryItem(
            kind: .event,
            title: cleanedPhrase(event ?? String(localized: "Event reservation")),
            location: routeParts(in: text)?.to ?? String(localized: "Venue needed"),
            status: String(localized: "Ticket saved"),
            startsAt: ItineraryDateParser.startDate(from: firstDateTime(in: text))
        )
    }

    private static func tripTitle(from items: [ItineraryItem]) -> String {
        if let flight = items.first(where: { $0.kind == .flight }),
           let destination = flight.location.components(separatedBy: " to ").last {
            return String(localized: "Trip to \(destination)")
        }

        if let hotel = items.first(where: { $0.kind == .hotel }) {
            return String(localized: "Stay at \(hotel.title)")
        }

        return items.first?.title ?? String(localized: "Imported trip")
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
        let uniqueKinds = Array(Set(items.map(\.kind.displayName))).sorted()
        return uniqueKinds.joined(separator: " + ")
    }

    private static func confidenceScore(for items: [ItineraryItem], warnings: [String]) -> Double {
        let missingCount = items.flatMap { [$0.title, $0.location] }
            .filter { $0.localizedCaseInsensitiveContains("needed") }
            .count + items.filter { $0.startsAt == nil }.count
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

    private static func hotelStayRange(in text: String) -> (startsAt: Date?, endsAt: Date?)? {
        let checkInDates = labeledDates(
            in: text,
            labelPattern: #"check\W*in"#,
            defaultTime: "15:00"
        )
        let checkOutDates = labeledDates(
            in: text,
            labelPattern: #"check\W*out"#,
            defaultTime: "11:00"
        )

        guard !checkInDates.isEmpty || !checkOutDates.isEmpty else {
            return nil
        }

        return (checkInDates.min(), checkOutDates.max())
    }

    private static func labeledDates(in text: String, labelPattern: String, defaultTime: String) -> [Date] {
        labelWindows(in: text, labelPattern: labelPattern).flatMap { window -> [Date] in
            let dates = dateOnlyMatches(in: window)
            let times = timeMatches(in: window)

            guard !dates.isEmpty else {
                return []
            }

            return dates.flatMap { date -> [Date] in
                if times.isEmpty {
                    return [dateTime(from: date, time: defaultTime)].compactMap { $0 }
                }

                return times.compactMap { time in
                    dateTime(from: date, hour: time.hour, minute: time.minute)
                }
            }
        }
    }

    private static func labelWindows(in text: String, labelPattern: String) -> [String] {
        allMatches(
            in: text,
            pattern: #"(?i)"# + labelPattern
        )
        .map { match in
            let matchStart = match.range.lowerBound
            let end = text.index(matchStart, offsetBy: 260, limitedBy: text.endIndex) ?? text.endIndex
            return String(text[matchStart..<end])
        }
    }

    private static func dateOnlyMatches(in text: String) -> [Date] {
        let patterns = [
            #"\b(?:Mon|Monday|Tue|Tuesday|Wed|Wednesday|Thu|Thursday|Fri|Friday|Sat|Saturday|Sun|Sunday),?\s+[A-Z][a-z]{2,8}\s+\d{1,2},\s+\d{4}\b"#,
            #"\b[A-Z][a-z]{2,8}\s+\d{1,2},\s+\d{4}\b"#,
            #"\b\d{1,2}\s+[A-Z][a-z]{2,8}\s+\d{4}\b"#,
            #"\b\d{4}-\d{2}-\d{2}\b"#,
            #"\b\d{1,2}[./]\d{1,2}[./]\d{4}\b"#,
            #"\b[A-Z][a-z]{2,8}\s+\d{1,2}\b"#
        ]

        return patterns.flatMap { pattern in
            allMatches(in: text, pattern: pattern)
                .compactMap { ItineraryDateParser.startDate(from: $0.value) }
        }
    }

    private static func timeMatches(in text: String) -> [(hour: Int, minute: Int)] {
        allMatches(
            in: text,
            pattern: #"\b\d{1,2}(?::\d{2})?\s?(?:AM|PM|am|pm)\b|\b\d{1,2}:\d{2}\b"#
        )
        .compactMap { timeComponents(from: $0.value) }
    }

    private static func timeComponents(from value: String) -> (hour: Int, minute: Int)? {
        let lowercased = value.lowercased()
        let numbers = allMatches(in: value, pattern: #"\d{1,2}"#).compactMap { Int($0.value) }
        guard var hour = numbers.first else { return nil }
        let minute = numbers.dropFirst().first ?? 0

        if lowercased.contains("pm"), hour < 12 {
            hour += 12
        } else if lowercased.contains("am"), hour == 12 {
            hour = 0
        }

        guard (0..<24).contains(hour), (0..<60).contains(minute) else {
            return nil
        }

        return (hour, minute)
    }

    private static func dateTime(from date: Date, time: String) -> Date? {
        timeComponents(from: time).flatMap { dateTime(from: date, hour: $0.hour, minute: $0.minute) }
    }

    private static func dateTime(from date: Date, hour: Int, minute: Int) -> Date? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(
            from: DateComponents(
                year: components.year,
                month: components.month,
                day: components.day,
                hour: hour,
                minute: minute
            )
        )
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

    private static func arrivalDateTimes(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .filter { line in
                let lowercasedLine = line.lowercased()
                return lowercasedLine.contains("arrival") || lowercasedLine.contains("arrive")
            }
            .flatMap(allDateTimes)
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
