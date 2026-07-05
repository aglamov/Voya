import Foundation
import SwiftData
import SwiftUI

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

struct MobilityPlanRequest: Encodable {
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

struct MobilityPlace: Encodable {
    var address: String
}
