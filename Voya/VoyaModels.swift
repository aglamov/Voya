import Foundation
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

struct ItineraryItem: Identifiable {
    let id: UUID
    var kind: ItineraryKind
    var title: String
    var time: String
    var location: String
    var status: String

    init(id: UUID = UUID(), kind: ItineraryKind, title: String, time: String, location: String, status: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.time = time
        self.location = location
        self.status = status
    }
}

struct Trip: Identifiable {
    let id: UUID
    var title: String
    var dates: String
    var summary: String
    var items: [ItineraryItem]
    var sourceName: String

    init(id: UUID = UUID(), title: String, dates: String, summary: String, items: [ItineraryItem], sourceName: String) {
        self.id = id
        self.title = title
        self.dates = dates
        self.summary = summary
        self.items = items
        self.sourceName = sourceName
    }
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
    var primaryTime: String
    var confidence: Double
    var fields: [ExtractedField]
    var items: [ItineraryItem]
    var warnings: [String]
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
    @Published var inspirationText = "Warm 4-day trip under $700 with easy transit"
    @Published var selectedMood: TripMood = .warm
    @Published var importText = "BA2490 London Heathrow to Rome Fiumicino, Aug 12, 09:40. Hotel Artemide check-in Aug 12."
    @Published var extractedPreview: ExtractionPreview?
    @Published var importedDocuments: [ImportedDocument] = []
    @Published var trips = SampleData.trips
    @Published var selectedTripID: UUID?
    @Published var importMessage: String?
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

    func extractFromPastedText() {
        extract(text: importText, sourceName: "Pasted confirmation")
    }

    func extract(text: String, sourceName: String) {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            importMessage = ImportErrorMessage.emptyInput.message
            return
        }

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
        extractedPreview?.items[index] = item
        refreshPreviewFields()
    }

    func confirmExtraction() {
        guard let preview = extractedPreview else { return }
        let trip = Trip(
            title: preview.title,
            dates: preview.primaryTime,
            summary: "\(preview.items.count) confirmed item\(preview.items.count == 1 ? "" : "s") from \(preview.sourceName)",
            items: preview.items,
            sourceName: preview.sourceName
        )
        trips.insert(trip, at: 0)
        selectedTripID = trip.id
        extractedPreview = nil
        importMessage = "Trip created: \(trip.title)"
    }

    private func refreshPreviewFields() {
        guard let preview = extractedPreview else { return }
        extractedPreview?.fields = ConfirmationParser.fields(for: preview.items, sourceName: preview.sourceName)
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
        let checkIn = firstMatch(in: text, pattern: #"(?i)check-?in\s+([A-Z][a-z]{2,8}\s+\d{1,2})"#)
        let time = checkIn.map { cleanedPhrase($0.replacingOccurrences(of: "check-in", with: "", options: .caseInsensitive)) } ?? "Check-in time needed"
        let destination = routeParts(in: text)?.to ?? fallbackLocation ?? "Address needed"

        return ItineraryItem(
            kind: .hotel,
            title: hotel,
            time: time.contains(":") ? time : "\(time), 15:00",
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
