import Foundation
import SwiftData
import SwiftUI

enum ItineraryDateFormatter {
    static func displayTime(
        start: Date,
        end: Date?,
        startTimeZoneOffsetSeconds: Int? = nil,
        endTimeZoneOffsetSeconds: Int? = nil
    ) -> String {
        let startTimeZone = timeZone(offsetSeconds: startTimeZoneOffsetSeconds)
        let endTimeZone = timeZone(offsetSeconds: endTimeZoneOffsetSeconds ?? startTimeZoneOffsetSeconds)
        let startText = formatter(dateFormat: "MMM d, HH:mm", timeZone: startTimeZone).string(from: start)
        guard let end else {
            return startText
        }

        if localDay(for: start, timeZone: startTimeZone) == localDay(for: end, timeZone: endTimeZone) {
            let endText = formatter(dateFormat: "HH:mm", timeZone: endTimeZone).string(from: end)
            return "\(startText)-\(endText)"
        }

        let endText = formatter(dateFormat: "MMM d, HH:mm", timeZone: endTimeZone).string(from: end)
        return "\(startText)-\(endText)"
    }

    static func displayClock(date: Date, timeZoneOffsetSeconds: Int?) -> String {
        formatter(dateFormat: "HH:mm", timeZone: timeZone(offsetSeconds: timeZoneOffsetSeconds)).string(from: date)
    }

    static func nextAction(date: Date, timeZoneOffsetSeconds: Int?) -> String {
        let formatter = DateFormatter()
        formatter.locale = VoyaAppLocale.current
        formatter.timeZone = timeZone(offsetSeconds: timeZoneOffsetSeconds)
        formatter.setLocalizedDateFormatFromTemplate("EEEjm")
        return formatter.string(from: date)
    }

    static func timeZone(offsetSeconds: Int?) -> TimeZone {
        offsetSeconds.flatMap(TimeZone.init(secondsFromGMT:)) ?? .autoupdatingCurrent
    }

    private static func formatter(dateFormat: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = VoyaAppLocale.current
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        return formatter
    }

    private static func localDay(for date: Date, timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day], from: date)
    }
}

enum DateIntervalFormatter {
    static func localizedDateRange(
        start: Date,
        end: Date,
        startTimeZoneOffsetSeconds: Int? = nil,
        endTimeZoneOffsetSeconds: Int? = nil
    ) -> String {
        let startTimeZone = ItineraryDateFormatter.timeZone(offsetSeconds: startTimeZoneOffsetSeconds)
        let endTimeZone = ItineraryDateFormatter.timeZone(offsetSeconds: endTimeZoneOffsetSeconds ?? startTimeZoneOffsetSeconds)
        let startComponents = localDateComponents(for: start, timeZone: startTimeZone)
        let endComponents = localDateComponents(for: end, timeZone: endTimeZone)

        guard startComponents != endComponents else {
            return monthDayFormatter(timeZone: startTimeZone).string(from: start)
        }

        if startComponents.year == endComponents.year,
           startComponents.month == endComponents.month {
            return "\(dayFormatter(timeZone: startTimeZone).string(from: start))–\(monthDayFormatter(timeZone: endTimeZone).string(from: end))"
        }

        return "\(monthDayFormatter(timeZone: startTimeZone).string(from: start)) – \(monthDayFormatter(timeZone: endTimeZone).string(from: end))"
    }

    private static func monthDayFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = VoyaAppLocale.current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter
    }

    private static func dayFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = VoyaAppLocale.current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }

    private static func localDateComponents(for date: Date, timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

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
    static var current: Locale {
        let identifier = Bundle.main.preferredLocalizations.first ?? Locale.autoupdatingCurrent.identifier
        return Locale(identifier: identifier)
    }

    static var currentIdentifier: String {
        current.identifier
    }

    static var currentLanguageCode: String {
        current.language.languageCode?.identifier ?? "en"
    }

    static var currentLanguageName: String {
        current.localizedString(forLanguageCode: currentLanguageCode) ?? currentLanguageCode
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    static func timeZoneOffsetSeconds(from value: String?) -> Int? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if value.hasSuffix("Z") || value.hasSuffix("z") {
            return 0
        }

        let pattern = #"([+-])(\d{2}):?(\d{2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let signRange = Range(match.range(at: 1), in: value),
              let hourRange = Range(match.range(at: 2), in: value),
              let minuteRange = Range(match.range(at: 3), in: value),
              let hours = Int(value[hourRange]),
              let minutes = Int(value[minuteRange]),
              hours <= 23,
              minutes <= 59 else {
            return nil
        }

        let totalSeconds = (hours * 60 + minutes) * 60
        return value[signRange] == "-" ? -totalSeconds : totalSeconds
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
