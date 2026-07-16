import Foundation
import SwiftData
import SwiftUI

struct VercelExtractionRequest: Encodable {
    let sourceName: String
    let text: String
    let locale: String
    let languageCode: String
    let languageName: String
}

struct VercelExtractionResponse: Codable {
    let type: String
    let title: String
    let normalizedDestination: String?
    let primaryTime: String
    let confidence: Double
    let items: [VercelItineraryItem]
    let warnings: [String]
}

struct VercelItineraryItem: Codable {
    let kind: String
    let title: String
    let time: String?
    let startsAt: String?
    let endsAt: String?
    let location: String
    let status: String
    let confirmationCode: String?
    let providerName: String?

    var itineraryItem: ItineraryItem {
        let parsedStartsAt = ItineraryDateParser.startDate(from: startsAt) ?? ItineraryDateParser.startDate(from: time)
        let parsedEndsAt = ItineraryDateParser.startDate(from: endsAt) ?? ItineraryDateParser.endDate(from: time)
        return ItineraryItem(
            kind: itineraryKind,
            title: title,
            location: location,
            status: status,
            startsAt: parsedStartsAt,
            endsAt: parsedEndsAt,
            startsAtTimeZoneOffsetSeconds: ItineraryDateParser.timeZoneOffsetSeconds(from: startsAt),
            endsAtTimeZoneOffsetSeconds: ItineraryDateParser.timeZoneOffsetSeconds(from: endsAt),
            confirmationCode: confirmationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            providerName: providerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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

enum VercelExtractionError: Error {
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
            sourceFile: document.sourceFile,
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
            if item.kind == .flight, let confirmationCode = item.confirmationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                fields.append(ExtractedField(label: String(localized: "Booking reference"), value: confirmationCode))
            }
            if item.kind == .flight, let providerName = item.providerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                fields.append(ExtractedField(label: String(localized: "Provider"), value: providerName))
            }
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
        let confirmationCode = bookingReference(in: text)

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
                status: String(localized: "Filled from source. Not enough details yet, checking tracking services."),
                startsAt: startsAt,
                endsAt: endsAt,
                confirmationCode: confirmationCode,
                providerName: FlightCheckInAction.airlineName(in: flightNumber)
            )
        }
    }

    static func bookingReference(in text: String) -> String? {
        let patterns = [
            #"(?i)\b(?:booking reference|booking ref|record locator|reservation code|confirmation code|pnr)\s*[:#-]?\s*([A-Z0-9]{5,8})\b"#,
            #"(?i)\b(?:airline confirmation|confirmation)\s*[:#-]?\s*([A-Z0-9]{5,8})\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[matchRange]).uppercased()
        }

        return nil
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

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
