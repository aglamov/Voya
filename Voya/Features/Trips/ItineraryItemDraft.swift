import SwiftUI
import SwiftData
import ImageIO
import PDFKit
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import UIKit
import Vision

enum ItineraryPhase: Equatable {
    case past
    case current
    case future
    case undated

    init(item: ItineraryItem, now: Date = Date()) {
        guard let start = item.startsAt else {
            self = .undated
            return
        }

        let end = item.endsAt ?? start
        if now >= start && now <= end {
            self = .current
            return
        }

        if end < now {
            self = .past
            return
        }

        self = .future
    }

    var label: String {
        switch self {
        case .past: String(localized: "Done")
        case .current: String(localized: "Now")
        case .future: String(localized: "Next")
        case .undated: String(localized: "Review")
        }
    }

    var accent: Color {
        switch self {
        case .past: Color.voyaMuted
        case .current: Color.voyaTeal
        case .future: Color.voyaInk
        case .undated: Color.voyaGold
        }
    }

    func timeColor(accent: Color) -> Color {
        switch self {
        case .current: accent
        case .undated: Color.voyaGold
        case .past: Color.voyaMuted
        case .future: accent
        }
    }

    var titleColor: Color {
        self == .past ? Color.voyaMuted : Color.voyaInk
    }

    var secondaryColor: Color {
        self == .past ? Color.voyaMuted.opacity(0.76) : Color.voyaMuted
    }

    func rowBackground(accent: Color) -> Color {
        switch self {
        case .current: accent.opacity(0.13)
        case .future: accent.opacity(0.055)
        case .undated: Color.voyaGold.opacity(0.08)
        case .past: Color.clear
        }
    }

    var badgeBackground: Color {
        switch self {
        case .current: Color.voyaTeal.opacity(0.13)
        case .undated: Color.voyaGold.opacity(0.13)
        case .past: Color.voyaSurface
        case .future: Color.voyaSurface
        }
    }

    var contentOpacity: Double {
        self == .past ? 0.62 : 1
    }

    var iconOpacity: Double {
        self == .past ? 0.72 : 1
    }

    var lineOpacity: Double {
        self == .past ? 0.18 : 0.42
    }

    var kindBadgeOpacity: Double {
        self == .past ? 0.08 : 0.12
    }

    var insightText: String {
        switch self {
        case .past: String(localized: "Already behind")
        case .current: String(localized: "Focus now")
        case .future: String(localized: "Coming up")
        case .undated: String(localized: "Needs time")
        }
    }
}

struct ItineraryItemDraft {
    var kind: ItineraryKind
    var title: String
    var hasStartDate: Bool
    var startsAt: Date
    var startsAtTimeZoneOffsetSeconds: Int?
    var endsAt: Date
    var endsAtTimeZoneOffsetSeconds: Int?
    var hasEndDate: Bool
    var location: String
    var status: String
    var confirmationCode: String
    var providerName: String

    init(item: ItineraryItem) {
        kind = item.kind
        title = item.title
        hasStartDate = item.startsAt != nil
        startsAt = item.startsAt ?? Date()
        startsAtTimeZoneOffsetSeconds = item.startsAtTimeZoneOffsetSeconds
        endsAt = item.endsAt ?? item.startsAt ?? Date()
        endsAtTimeZoneOffsetSeconds = item.endsAtTimeZoneOffsetSeconds
        hasEndDate = item.endsAt != nil
        location = item.location
        status = item.status
        confirmationCode = item.confirmationCode ?? ""
        providerName = item.providerName ?? ""
    }

    init() {
        kind = .event
        title = ""
        hasStartDate = true
        startsAt = Date()
        startsAtTimeZoneOffsetSeconds = nil
        endsAt = Date()
        endsAtTimeZoneOffsetSeconds = nil
        hasEndDate = false
        location = ""
        status = ""
        confirmationCode = ""
        providerName = ""
    }

    var effectiveStartsAt: Date? {
        hasStartDate ? startsAt : nil
    }

    var effectiveEndsAt: Date? {
        hasStartDate && hasEndDate ? max(endsAt, startsAt) : nil
    }

    var displayTime: String {
        effectiveStartsAt.map {
            ItineraryDateFormatter.displayTime(
                start: $0,
                end: effectiveEndsAt,
                startTimeZoneOffsetSeconds: startsAtTimeZoneOffsetSeconds,
                endTimeZoneOffsetSeconds: endsAtTimeZoneOffsetSeconds
            )
        } ?? String(localized: "Date needed")
    }

    var startTimeZone: TimeZone {
        ItineraryDateFormatter.timeZone(offsetSeconds: startsAtTimeZoneOffsetSeconds)
    }

    var endTimeZone: TimeZone {
        ItineraryDateFormatter.timeZone(offsetSeconds: endsAtTimeZoneOffsetSeconds ?? startsAtTimeZoneOffsetSeconds)
    }

    func matches(_ other: ItineraryItemDraft) -> Bool {
        kind == other.kind
            && title == other.title
            && hasStartDate == other.hasStartDate
            && startsAt == other.startsAt
            && startsAtTimeZoneOffsetSeconds == other.startsAtTimeZoneOffsetSeconds
            && endsAt == other.endsAt
            && endsAtTimeZoneOffsetSeconds == other.endsAtTimeZoneOffsetSeconds
            && hasEndDate == other.hasEndDate
            && location == other.location
            && status == other.status
            && confirmationCode == other.confirmationCode
            && providerName == other.providerName
    }
}

enum LocationLinkResolver {
    static func mapURL(for value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let directURL = directURL(from: trimmed) {
            return directURL
        }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(encoded)")
    }

    static func directURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "comgooglemaps", "maps"].contains(scheme) else {
            return nil
        }

        return url
    }
}

enum LocationDisplayResolver {
    static func immediateDisplayName(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        guard let url = googleMapsURL(from: trimmed) else {
            return trimmed
        }

        return placeName(from: url) ?? coordinates(from: url).map { _ in String(localized: "Map point") } ?? String(localized: "Map point")
    }

    static func resolvedDisplayName(for value: String) async -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        guard let url = googleMapsURL(from: trimmed) else {
            return trimmed
        }

        if let displayName = placeName(from: url) ?? coordinates(from: url).map({ _ in String(localized: "Map point") }) {
            return displayName
        }

        guard isShortGoogleMapsURL(url),
              let resolvedURL = await resolvedURL(from: url),
              resolvedURL != url else {
            return String(localized: "Map point")
        }

        return placeName(from: resolvedURL) ?? coordinates(from: resolvedURL).map { _ in String(localized: "Map point") } ?? String(localized: "Map point")
    }

    private static func googleMapsURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              let host = url.host?.lowercased(),
              isGoogleMapsHost(host) else {
            return nil
        }

        return url
    }

    private static func isGoogleMapsHost(_ host: String) -> Bool {
        [
            "google.com",
            "www.google.com",
            "maps.google.com",
            "maps.app.goo.gl",
            "goo.gl"
        ].contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static func isShortGoogleMapsURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "maps.app.goo.gl" || host == "goo.gl"
    }

    private static func placeName(from url: URL) -> String? {
        if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "q" || $0.name == "query" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !query.isEmpty,
           coordinates(from: query) == nil {
            return cleanPlaceName(query)
        }

        let path = url.path.removingPercentEncoding ?? url.path
        guard let range = path.range(of: #"/place/([^/]+)"#, options: .regularExpression) else {
            return nil
        }

        let rawName = String(path[range])
            .replacingOccurrences(of: "/place/", with: "")
        return cleanPlaceName(rawName)
    }

    private static func cleanPlaceName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func coordinates(from url: URL) -> (Double, Double)? {
        coordinates(from: url.absoluteString.removingPercentEncoding ?? url.absoluteString)
    }

    private static func coordinates(from value: String) -> (Double, Double)? {
        let patterns = [
            #"@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)(?:[,/?]|$)"#,
            #"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)"#,
            #"^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  match.numberOfRanges >= 3,
                  let latRange = Range(match.range(at: 1), in: value),
                  let lonRange = Range(match.range(at: 2), in: value),
                  let latitude = Double(value[latRange]),
                  let longitude = Double(value[lonRange]),
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude) else {
                continue
            }

            return (latitude, longitude)
        }

        return nil
    }

    private static func resolvedURL(from url: URL) async -> URL? {
        for method in ["HEAD", "GET"] {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 8
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let resolvedURL = response.url,
                   resolvedURL != url,
                   googleMapsURL(from: resolvedURL.absoluteString) != nil {
                    return resolvedURL
                }
            } catch {
                continue
            }
        }

        return nil
    }
}

enum ItineraryItemEditorMode {
    case add
    case edit
}
