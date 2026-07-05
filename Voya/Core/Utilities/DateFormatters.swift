import Foundation
import SwiftData
import SwiftUI

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
