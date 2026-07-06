import Foundation
import SwiftData
import SwiftUI

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
    var delayStats: FlightDelayStats?
    var reliability: FlightReliabilityStats?
    var gate: FlightGateStatus?
    var alerting: FlightAlertingStatus?
    var warnings: [String]
}

struct FlightDelayStats: Decodable {
    var headline: String
    var delayMinutes: Int?
    var onTimeProbability: Double?
    var reasons: [String]
}

struct FlightReliabilityStats: Decodable {
    var sampleSize: Int
    var averageDepartureDelayMinutes: Double?
    var averageArrivalDelayMinutes: Double?
    var delayed15Rate: Double?
    var cancelledCount: Int
    var divertedCount: Int
    var typicalDepartureGate: String?
    var typicalArrivalGate: String?
    var typicalAircraftTypes: [String]
}

struct FlightGateStatus: Decodable {
    var departureTerminal: String?
    var departureGate: String?
    var arrivalTerminal: String?
    var arrivalGate: String?
    var baggageClaim: String?
    var changed: Bool
    var guidance: [String]
}

struct FlightAlertingStatus: Decodable {
    var supported: Bool
    var source: String
    var events: [String]
    var webhookEndpoint: String
    var managementEndpoint: String
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
        originAirport: String? = nil,
        destinationAirport: String? = nil
    ) async throws -> FlightLookupResponse {
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
                date: date.map { Self.flightDateFormatter.string(from: $0) },
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

    private static let flightDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct FlightLookupRequest: Encodable {
    var flightNumber: String
    var date: String?
    var originAirport: String?
    var destinationAirport: String?
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
