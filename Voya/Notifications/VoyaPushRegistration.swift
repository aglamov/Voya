import Foundation
import UIKit

extension Notification.Name {
    static let voyaPushDeviceTokenDidChange = Notification.Name("voya.push-device-token-did-change")
}

final class VoyaAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = VoyaNotificationScheduler.shared
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task {
            await VoyaPushRegistrationService.shared.registerDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("[Voya] Remote notification registration failed: \(error.localizedDescription)")
        #endif
    }
}

@MainActor
final class VoyaPushRegistrationService {
    static let shared = VoyaPushRegistrationService()

    private let session: URLSession
    private let baseURL: URL?
    private let userDefaults: UserDefaults
    private let deviceTokenKey = "voya.apns.device-token"
    private let weatherWatchSignatureKey = "voya.weather-watch.signature"
    private let weatherWatchSyncedAtKey = "voya.weather-watch.synced-at"
    private let flightWatchSignatureKey = "voya.flight-watch.signature"
    private let flightWatchSyncedAtKey = "voya.flight-watch.synced-at"

    init(
        session: URLSession = .shared,
        baseURL: URL? = VoyaAPIConfiguration.baseURL,
        userDefaults: UserDefaults = .standard
    ) {
        self.session = session
        self.baseURL = baseURL
        self.userDefaults = userDefaults
    }

    var currentDeviceToken: String? {
        userDefaults.string(forKey: deviceTokenKey)
    }

    func startFlightAlertSelfTest() async -> FlightAlertSelfTestResponse {
        guard await VoyaNotificationScheduler.shared.requestAuthorizationIfNeeded() else {
            return FlightAlertSelfTestResponse(
                status: "failed",
                error: String(localized: "Notifications are disabled for Voya. Enable them in iPhone Settings and try again.")
            )
        }
        UIApplication.shared.registerForRemoteNotifications()
        if currentDeviceToken == nil {
            for _ in 0..<20 where currentDeviceToken == nil {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        guard let deviceToken = currentDeviceToken else {
            return FlightAlertSelfTestResponse(
                status: "failed",
                error: String(localized: "Voya could not get an APNs token. Run this test on a physical iPhone.")
            )
        }
        return await flightAlertSelfTestRequest(method: "POST", deviceToken: deviceToken)
            ?? FlightAlertSelfTestResponse(
                status: "failed",
                error: String(localized: "The live FlightAware test could not reach the Voya backend.")
            )
    }

    func flightAlertSelfTestStatus() async -> FlightAlertSelfTestResponse? {
        await flightAlertSelfTestRequest(method: "GET", deviceToken: nil)
    }

    func registerDeviceToken(_ data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        let previousToken = userDefaults.string(forKey: deviceTokenKey)
        userDefaults.set(token, forKey: deviceTokenKey)

        if previousToken != token {
            NotificationCenter.default.post(name: .voyaPushDeviceTokenDidChange, object: nil)
        }
    }

    func syncTripWatches(for trips: [Trip], now: Date = Date(), force: Bool = false) async {
        await syncWeatherWatches(for: trips, now: now, force: force)
        await syncFlightWatches(for: trips, now: now, force: force)
    }

    func syncFlightWatches(for trips: [Trip], now: Date = Date(), force: Bool = false) async {
        guard let deviceToken = userDefaults.string(forKey: deviceTokenKey) else {
            return
        }

        let flights: [(tripID: UUID, item: ItineraryItem)] = trips
            .flatMap { trip in
                trip.items.compactMap { item -> (tripID: UUID, item: ItineraryItem)? in
                    guard item.kind == .flight else { return nil }
                    if let endsAt = item.endsAt ?? item.startsAt, endsAt < now.addingTimeInterval(-12 * 60 * 60) {
                        return nil
                    }
                    if let startsAt = item.startsAt, startsAt > now.addingTimeInterval(60 * 24 * 60 * 60) {
                        return nil
                    }
                    guard item.resolvedFlightNumber != nil else {
                        return nil
                    }
                    return (trip.id, item)
                }
            }
            .sorted { $0.item.id.uuidString < $1.item.id.uuidString }

        let signature = Self.flightWatchSignature(for: flights.map { $0.item }, deviceToken: deviceToken)
        let lastSignature = userDefaults.string(forKey: flightWatchSignatureKey)
        let lastSync = userDefaults.object(forKey: flightWatchSyncedAtKey) as? Date
        let isFresh = lastSync.map { now.timeIntervalSince($0) < 12 * 60 * 60 } ?? false
        guard force || signature != lastSignature || !isFresh else {
            return
        }

        var registrationSucceeded = true
        for flight in flights {
            let response = await registerFlightWatch(for: flight.item, tripID: flight.tripID, subscribeToAlerts: true)
            registrationSucceeded = registrationSucceeded
                && response?.stored == true
                && response?.alertWatch?.subscribed == true
        }

        if registrationSucceeded {
            userDefaults.set(signature, forKey: flightWatchSignatureKey)
            userDefaults.set(now, forKey: flightWatchSyncedAtKey)
        }
    }

    func syncWeatherWatches(for trips: [Trip], now: Date = Date(), force: Bool = false) async {
        guard let deviceToken = userDefaults.string(forKey: deviceTokenKey) else {
            return
        }

        let relevantTrips = trips.filter { trip in
            let startsAt = trip.startsAt ?? trip.items.compactMap(\.startsAt).min()
            let endsAt = trip.endsAt ?? trip.items.compactMap { $0.endsAt ?? $0.startsAt }.max()
            if let endsAt, endsAt < now.addingTimeInterval(-12 * 60 * 60) {
                return false
            }
            if let startsAt, startsAt > now.addingTimeInterval(60 * 24 * 60 * 60) {
                return false
            }
            return true
        }

        let signature = Self.weatherWatchSignature(for: relevantTrips, deviceToken: deviceToken)
        let lastSignature = userDefaults.string(forKey: weatherWatchSignatureKey)
        let lastSync = userDefaults.object(forKey: weatherWatchSyncedAtKey) as? Date
        let isFresh = lastSync.map { now.timeIntervalSince($0) < 6 * 60 * 60 } ?? false
        guard force || signature != lastSignature || !isFresh else {
            return
        }

        var registrationSucceeded = true

        for trip in relevantTrips {
            var registeredLocations = Set<String>()
            if let destination = Self.monitorableLocation(trip.destination) {
                registeredLocations.insert(destination.lowercased())
                let response = await registerWeatherWatch(
                    tripID: trip.id,
                    itemID: nil,
                    label: trip.title,
                    location: destination,
                    startsAt: trip.startsAt ?? trip.items.compactMap(\.startsAt).min(),
                    endsAt: trip.endsAt ?? trip.items.compactMap { $0.endsAt ?? $0.startsAt }.max()
                )
                registrationSucceeded = registrationSucceeded && response?.stored == true
            }

            for item in trip.items where item.kind != .flight {
                guard let location = Self.monitorableLocation(item.location) else {
                    continue
                }
                let locationKey = location.lowercased()
                guard registeredLocations.insert(locationKey).inserted else {
                    continue
                }
                let response = await registerWeatherWatch(
                    tripID: trip.id,
                    itemID: item.id,
                    label: item.title,
                    location: location,
                    startsAt: item.startsAt ?? trip.startsAt,
                    endsAt: item.endsAt ?? trip.endsAt
                )
                registrationSucceeded = registrationSucceeded && response?.stored == true
            }
        }

        if registrationSucceeded {
            userDefaults.set(signature, forKey: weatherWatchSignatureKey)
            userDefaults.set(now, forKey: weatherWatchSyncedAtKey)
        }
    }

    func registerFlightWatch(
        for item: ItineraryItem,
        tripID: UUID? = nil,
        candidate: FlightLookupCandidate? = nil,
        subscribeToAlerts: Bool = false
    ) async -> FlightWatchRegistrationResponse? {
        guard item.kind == .flight,
              let flightNumber = candidate?.flightNumber ?? item.resolvedFlightNumber else {
            return nil
        }

        let token = userDefaults.string(forKey: deviceTokenKey)
        return await send(
            path: "api/flight-watch",
            payload: FlightWatchRegistrationPayload(
                appInstallId: installID,
                deviceToken: token,
                tripId: tripID?.uuidString,
                itemId: item.id.uuidString,
                flightNumber: flightNumber,
                date: Self.flightDate(for: item),
                departureAt: item.startsAt,
                originAirport: candidate?.originAirport ?? candidate?.originAirportIcao,
                destinationAirport: candidate?.destinationAirport ?? candidate?.destinationAirportIcao,
                subscribeToAlerts: subscribeToAlerts
            )
        )
    }

    func registerWeatherWatch(
        tripID: UUID,
        itemID: UUID?,
        label: String,
        location: String,
        startsAt: Date?,
        endsAt: Date?
    ) async -> WeatherWatchRegistrationResponse? {
        guard let token = userDefaults.string(forKey: deviceTokenKey) else {
            return nil
        }

        return await sendWeatherWatch(
            payload: WeatherWatchRegistrationPayload(
                appInstallId: installID,
                deviceToken: token,
                tripId: tripID.uuidString,
                itemId: itemID?.uuidString,
                label: label,
                location: location,
                startsAt: startsAt,
                endsAt: endsAt,
                locale: Locale.current.identifier
            )
        )
    }

    private func send<T: Encodable>(path: String, payload: T) async -> FlightWatchRegistrationResponse? {
        guard let baseURL else {
            return nil
        }

        do {
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            VoyaAPIConfiguration.authorize(&request)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(FlightWatchRegistrationResponse.self, from: data)
        } catch {
            #if DEBUG
            print("[Voya] Push registration request failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private func sendWeatherWatch(payload: WeatherWatchRegistrationPayload) async -> WeatherWatchRegistrationResponse? {
        guard let baseURL else {
            return nil
        }

        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/weather-watch"))
            VoyaAPIConfiguration.authorize(&request)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 25
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(payload)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(WeatherWatchRegistrationResponse.self, from: data)
        } catch {
            #if DEBUG
            print("[Voya] Weather watch registration failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private func flightAlertSelfTestRequest(method: String, deviceToken: String?) async -> FlightAlertSelfTestResponse? {
        guard let baseURL else {
            return FlightAlertSelfTestResponse(
                status: "failed",
                error: String(localized: "The Voya backend URL is not configured.")
            )
        }

        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/flight-alert-self-test"))
            VoyaAPIConfiguration.authorize(&request)
            request.httpMethod = method
            request.timeoutInterval = 45
            if let deviceToken {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(FlightAlertSelfTestPayload(deviceToken: deviceToken))
            }
            let (data, _) = try await session.data(for: request)
            return try JSONDecoder().decode(FlightAlertSelfTestResponse.self, from: data)
        } catch {
            #if DEBUG
            print("[Voya] Flight alert self-test failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private var installID: String {
        VoyaAPIConfiguration.installID
    }

    private static func firstFlightNumber(in value: String) -> String? {
        guard let match = value.firstMatch(of: /[A-Z0-9]{2,3}\s?\d{1,4}[A-Z]?/) else {
            return nil
        }

        return String(match.output).replacingOccurrences(of: " ", with: "").uppercased()
    }

    private static func monitorableLocation(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty,
              !normalized.localizedCaseInsensitiveContains("needed"),
              !normalized.localizedCaseInsensitiveContains("unknown") else {
            return nil
        }
        return normalized
    }

    private static func weatherWatchSignature(for trips: [Trip], deviceToken: String) -> String {
        let tripValues = trips
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { trip in
                let itemValues = trip.items
                    .filter { $0.kind != .flight }
                    .sorted { $0.id.uuidString < $1.id.uuidString }
                    .map { item in
                        [
                            item.id.uuidString,
                            item.title,
                            item.location,
                            item.startsAt?.ISO8601Format() ?? "",
                            item.endsAt?.ISO8601Format() ?? "",
                            item.updatedAt.ISO8601Format()
                        ].joined(separator: "|")
                    }
                    .joined(separator: ";")
                return [
                    trip.id.uuidString,
                    trip.title,
                    trip.destination ?? "",
                    trip.startsAt?.ISO8601Format() ?? "",
                    trip.endsAt?.ISO8601Format() ?? "",
                    trip.updatedAt.ISO8601Format(),
                    itemValues
                ].joined(separator: "|")
            }
            .joined(separator: ";;")
        return "\(deviceToken)|\(tripValues)"
    }

    private static func flightWatchSignature(for items: [ItineraryItem], deviceToken: String) -> String {
        let values = items.map { item in
            [
                item.id.uuidString,
                item.title,
                item.location,
                item.startsAt?.ISO8601Format() ?? "",
                item.endsAt?.ISO8601Format() ?? "",
                item.updatedAt.ISO8601Format()
            ].joined(separator: "|")
        }.joined(separator: ";")
        return "\(deviceToken)|\(values)"
    }

    private static func flightDate(for item: ItineraryItem) -> String? {
        guard let startsAt = item.startsAt else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ItineraryDateFormatter.timeZone(
            offsetSeconds: item.startsAtTimeZoneOffsetSeconds
        )
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: startsAt)
    }
}

private struct WeatherWatchRegistrationPayload: Encodable {
    var appInstallId: String
    var deviceToken: String
    var tripId: String
    var itemId: String?
    var label: String
    var location: String
    var startsAt: Date?
    var endsAt: Date?
    var locale: String
}

struct WeatherWatchRegistrationResponse: Decodable {
    var accepted: Bool
    var stored: Bool
    var monitoring: String
}

private struct FlightWatchRegistrationPayload: Encodable {
    var appInstallId: String
    var deviceToken: String?
    var tripId: String?
    var itemId: String
    var flightNumber: String
    var date: String?
    var departureAt: Date?
    var originAirport: String?
    var destinationAirport: String?
    var subscribeToAlerts: Bool
}

struct FlightWatchRegistrationResponse: Decodable {
    var accepted: Bool
    var stored: Bool
    var flightKey: String?
    var deviceLinked: Bool?
    var alertWatch: FlightAlertWatchStatus?
    var monitoring: FlightWatchMonitoringStatus?
    var updatedAt: String?
    var warning: String?
}

struct FlightWatchMonitoringStatus: Decodable {
    var state: String
    var fallbackPolling: Bool
    var nextCheckAt: String?
    var lastCheckedAt: String?
    var lastProviderEventAt: String?
    var lastEventType: String?
    var lastError: String?
}

struct FlightAlertWatchStatus: Decodable {
    var requested: Bool
    var configured: Bool
    var subscribed: Bool
    var existing: Bool
    var alertId: String?
    var location: String?
    var status: Int?
    var error: String?
}

private struct FlightAlertSelfTestPayload: Encodable {
    var deviceToken: String
}

struct FlightAlertSelfTestResponse: Decodable, Equatable {
    var status: String
    var flightNumber: String?
    var flightDate: String?
    var originAirport: String?
    var destinationAirport: String?
    var departureAt: String?
    var terminal: String?
    var gate: String?
    var alertId: String?
    var monitoringState: String?
    var fallbackPolling: Bool?
    var confirmationPushSent: Bool?
    var gatePushSent: Bool?
    var createdAt: String?
    var updatedAt: String?
    var gateReceivedAt: String?
    var eventSummary: String?
    var error: String?

    init(status: String, error: String? = nil) {
        self.status = status
        self.error = error
    }
}
