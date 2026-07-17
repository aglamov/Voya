import Foundation
import SwiftData
import SwiftUI

struct FlightLookupCandidate: Codable {
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
    var aircraftRegistration: String?
    var providerStatus: String?
    var dataMode: String?
    var progressPercent: Double?
    var position: FlightPosition?
    var inboundProviderFlightId: String?
    var confidence: Double?

    var parsedDepartureAt: Date? {
        Self.parseDate(departureAt)
    }

    var parsedArrivalAt: Date? {
        Self.parseDate(arrivalAt)
    }

    var departureTimeZoneOffsetSeconds: Int? {
        ItineraryDateParser.timeZoneOffsetSeconds(from: departureAt)
    }

    var arrivalTimeZoneOffsetSeconds: Int? {
        ItineraryDateParser.timeZoneOffsetSeconds(from: arrivalAt)
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

struct FlightPosition: Codable {
    var lat: Double
    var lon: Double
    var altitudeFeet: Double?
    var groundspeedKnots: Double?
    var headingDegrees: Double?
    var updatedAt: String?
}

struct FlightPlaneSegment: Codable {
    var flightNumber: String?
    var originAirport: String?
    var destinationAirport: String?
    var status: String
    var providerStatus: String?
    var scheduledDepartureAt: String?
    var estimatedDepartureAt: String?
    var actualDepartureAt: String?
    var scheduledArrivalAt: String?
    var estimatedArrivalAt: String?
    var actualArrivalAt: String?
    var progressPercent: Double?
    var position: FlightPosition?
}

struct FlightPlaneContext: Codable {
    var state: String
    var headline: String
    var detail: String
    var aircraftType: String?
    var aircraftRegistration: String?
    var currentFlight: FlightPlaneSegment?
    var inboundFlight: FlightPlaneSegment?
    var position: FlightPosition?
    var progressPercent: Double?
    var sourceUpdatedAt: String?
    var confidence: Double
}

struct FlightSnapshot: Codable {
    var provider: String
    var dataMode: String?
    var providerFlightId: String?
    var providerStatus: String?
    var airlineCode: String?
    var flightNumber: String
    var flightIata: String?
    var flightIcao: String?
    var operatingAirlineCode: String?
    var codeshares: [String]?
    var originAirport: String?
    var originAirportIcao: String?
    var destinationAirport: String?
    var destinationAirportIcao: String?
    var scheduledDepartureAt: String?
    var scheduledTakeoffAt: String?
    var scheduledLandingAt: String?
    var scheduledArrivalAt: String?
    var estimatedDepartureAt: String?
    var estimatedTakeoffAt: String?
    var estimatedLandingAt: String?
    var estimatedArrivalAt: String?
    var actualDepartureAt: String?
    var actualTakeoffAt: String?
    var actualLandingAt: String?
    var actualArrivalAt: String?
    var departureTerminal: String?
    var departureGate: String?
    var departureDelayMinutes: Int?
    var arrivalTerminal: String?
    var arrivalGate: String?
    var arrivalDelayMinutes: Int?
    var baggageClaim: String?
    var aircraftType: String?
    var aircraftRegistration: String?
    var status: String
    var delayMinutes: Int?
    var cancellationReason: String?
    var diversionAirport: String?
    var inboundProviderFlightId: String?
    var progressPercent: Double?
    var routeDistanceNm: Double?
    var filedAirspeedKnots: Double?
    var filedAltitudeFeet: Double?
    var filedRoute: String?
    var filedEte: Int?
    var position: FlightPosition?
    var onTimeProbability: Double?
    var confidence: Double
    var sourceUpdatedAt: String?
    var fetchedAt: String
}

struct FlightSchedule: Codable {
    var scheduledDepartureAt: String?
    var scheduledTakeoffAt: String?
    var scheduledLandingAt: String?
    var scheduledArrivalAt: String?
    var estimatedDepartureAt: String?
    var estimatedTakeoffAt: String?
    var estimatedLandingAt: String?
    var estimatedArrivalAt: String?
    var actualDepartureAt: String?
    var actualTakeoffAt: String?
    var actualLandingAt: String?
    var actualArrivalAt: String?
}

struct FlightAirportWeather: Codable {
    var airport: String?
    var observedAt: String?
    var raw: String?
    var summary: String?
    var temperatureC: Double?
    var wind: String?
    var visibility: String?
    var forecastIssuedAt: String?
    var forecastSummary: String?
}

struct FlightDisruptionStats: Codable, Identifiable {
    var id: String { "\(entityType)-\(entityId ?? entityName ?? "unknown")" }
    var entityType: String
    var entityId: String?
    var entityName: String?
    var cancellations: Int?
    var delays: Int?
    var total: Int?
    var delayRate: Double?
    var cancellationRate: Double?
    var timePeriod: String
}

struct FlightRouteInsight: Codable {
    var route: String?
    var routeDistance: String?
    var count: Int?
    var aircraftTypes: [String]?
    var filedAltitudeMinFeet: Double?
    var filedAltitudeMaxFeet: Double?
    var lastDepartureAt: String?
}

struct FlightIntelligence: Codable {
    struct Weather: Codable {
        var origin: FlightAirportWeather?
        var destination: FlightAirportWeather?
    }

    var mode: String
    var scheduleAvailableUntil: String?
    var liveDataAvailableFrom: String?
    var disruptions: [FlightDisruptionStats]
    var history: FlightReliabilityStats?
    var weather: Weather
    var route: FlightRouteInsight?
}

struct FlightProviderStatus: Codable {
    var name: String
    var connected: Bool
    var attribution: String
}

struct FlightLookupResponse: Codable {
    struct Validation: Codable {
        var state: String
        var confidence: Double
        var reasons: [String]
    }

    var validation: Validation
    var candidate: FlightLookupCandidate?
    var snapshot: FlightSnapshot?
    var plane: FlightPlaneContext?
    var delayStats: FlightDelayStats?
    var reliability: FlightReliabilityStats?
    var gate: FlightGateStatus?
    var alerting: FlightAlertingStatus?
    var intelligence: FlightIntelligence?
    var schedule: FlightSchedule?
    var nextActions: [String]?
    var warnings: [String]
    var provider: FlightProviderStatus?
}

struct FlightDelayStats: Codable {
    var headline: String
    var delayMinutes: Int?
    var onTimeProbability: Double?
    var reasons: [String]
}

struct FlightReliabilityStats: Codable {
    var sampleSize: Int
    var averageDepartureDelayMinutes: Double?
    var averageArrivalDelayMinutes: Double?
    var delayed15Rate: Double?
    var cancelledCount: Int
    var divertedCount: Int
    var typicalDepartureGate: String?
    var typicalArrivalGate: String?
    var typicalAircraftTypes: [String]
    var since: String?
    var until: String?
}

struct FlightGateStatus: Codable {
    var departureTerminal: String?
    var departureGate: String?
    var arrivalTerminal: String?
    var arrivalGate: String?
    var baggageClaim: String?
    var changed: Bool
    var guidance: [String]
}

struct FlightAlertingStatus: Codable {
    var supported: Bool
    var source: String
    var events: [String]
    var webhookEndpoint: String
    var managementEndpoint: String
}

enum FlightLookupCache {
    private static let schemaVersion = "flight-lookup-v1"

    static func cachedResponse(for item: ItineraryItem) -> FlightLookupResponse? {
        guard item.flightLookupCacheKey == key(for: item),
              let rawData = item.flightLookupRawData,
              let data = rawData.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(FlightLookupResponse.self, from: data)
    }

    static func freshCachedResponse(for item: ItineraryItem, now: Date = Date()) -> FlightLookupResponse? {
        guard let expiresAt = item.flightLookupExpiresAt, expiresAt > now else {
            return nil
        }
        return cachedResponse(for: item)
    }

    static func store(_ response: FlightLookupResponse, for item: ItineraryItem, now: Date = Date()) {
        guard let data = try? JSONEncoder().encode(response),
              let rawData = String(data: data, encoding: .utf8) else {
            return
        }

        item.flightLookupCacheKey = key(for: item)
        item.flightLookupRawData = rawData
        item.flightLookupUpdatedAt = now
        item.flightLookupExpiresAt = expirationDate(for: item, now: now)
    }

    static func clear(for item: ItineraryItem) {
        item.flightLookupCacheKey = nil
        item.flightLookupRawData = nil
        item.flightLookupUpdatedAt = nil
        item.flightLookupExpiresAt = nil
    }

    static func isFresh(for item: ItineraryItem, now: Date = Date()) -> Bool {
        item.flightLookupCacheKey == key(for: item) && (item.flightLookupExpiresAt ?? .distantPast) > now
    }

    private static func key(for item: ItineraryItem) -> String {
        let formatter = ISO8601DateFormatter()
        return [
            schemaVersion,
            item.resolvedFlightNumber?.lowercased() ?? "",
            item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            item.location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            item.startsAt.map(formatter.string(from:)) ?? ""
        ].joined(separator: "|")
    }

    private static func expirationDate(for item: ItineraryItem, now: Date) -> Date {
        guard let startsAt = item.startsAt else {
            return now.addingTimeInterval(30 * 60)
        }

        let secondsUntilStart = startsAt.timeIntervalSince(now)
        if secondsUntilStart < -12 * 60 * 60 {
            return now.addingTimeInterval(24 * 60 * 60)
        }
        if secondsUntilStart <= 48 * 60 * 60 {
            return now.addingTimeInterval(10 * 60)
        }
        if secondsUntilStart <= 7 * 24 * 60 * 60 {
            return now.addingTimeInterval(60 * 60)
        }
        return now.addingTimeInterval(12 * 60 * 60)
    }
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

    func lookup(
        flightNumber: String,
        date: Date?,
        dateTimeZoneOffsetSeconds: Int? = nil,
        originAirport: String? = nil,
        destinationAirport: String? = nil
    ) async throws -> FlightLookupResponse {
        guard let baseURL else {
            throw VercelExtractionError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/flight-lookup"))
        VoyaAPIConfiguration.authorize(&request)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 25
        request.httpBody = try JSONEncoder().encode(
            FlightLookupRequest(
                flightNumber: flightNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date.map {
                    Self.flightDateString(from: $0, timeZoneOffsetSeconds: dateTimeZoneOffsetSeconds)
                },
                originAirport: originAirport?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                destinationAirport: destinationAirport?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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

    func discover(
        originAirport: String,
        destinationAirport: String,
        departureAt: Date
    ) async throws -> FlightLookupResponse {
        guard let baseURL else {
            throw VercelExtractionError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/flight-discovery"))
        VoyaAPIConfiguration.authorize(&request)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 25
        request.httpBody = try JSONEncoder().encode(
            FlightDiscoveryRequest(
                originAirport: originAirport.trimmingCharacters(in: .whitespacesAndNewlines),
                destinationAirport: destinationAirport.trimmingCharacters(in: .whitespacesAndNewlines),
                departureAt: Self.flightTimestamp(from: departureAt)
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw VercelExtractionError.badResponse
        }

        return try JSONDecoder().decode(FlightLookupResponse.self, from: data)
    }

    private static func flightDateString(from date: Date, timeZoneOffsetSeconds: Int?) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ItineraryDateFormatter.timeZone(offsetSeconds: timeZoneOffsetSeconds)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func flightTimestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

struct FlightLookupRequest: Encodable {
    var flightNumber: String
    var date: String?
    var originAirport: String?
    var destinationAirport: String?
}

struct FlightDiscoveryRequest: Encodable {
    var originAirport: String
    var destinationAirport: String
    var departureAt: String
}

struct ItemEnrichmentRequest: Encodable {
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
