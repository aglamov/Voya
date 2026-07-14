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
        Task { @MainActor in
            guard await VoyaNotificationScheduler.shared.requestAuthorizationIfNeeded() else {
                return
            }
            application.registerForRemoteNotifications()
        }
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
    private let installIDKey = "voya.install-id"
    private let weatherWatchSignatureKey = "voya.weather-watch.signature"
    private let weatherWatchSyncedAtKey = "voya.weather-watch.synced-at"

    init(
        session: URLSession = .shared,
        baseURL: URL? = VoyaAPIConfiguration.baseURL,
        userDefaults: UserDefaults = .standard
    ) {
        self.session = session
        self.baseURL = baseURL
        self.userDefaults = userDefaults
    }

    func registerDeviceToken(_ data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        let previousToken = userDefaults.string(forKey: deviceTokenKey)
        userDefaults.set(token, forKey: deviceTokenKey)

        if previousToken != token {
            NotificationCenter.default.post(name: .voyaPushDeviceTokenDidChange, object: nil)
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
        candidate: FlightLookupCandidate? = nil,
        subscribeToAlerts: Bool = false
    ) async -> FlightWatchRegistrationResponse? {
        guard item.kind == .flight,
              let flightNumber = candidate?.flightNumber ?? Self.firstFlightNumber(in: "\(item.title) \(item.location)") else {
            return nil
        }

        let token = userDefaults.string(forKey: deviceTokenKey)
        return await send(
            path: "api/flight-watch",
            payload: FlightWatchRegistrationPayload(
                appInstallId: installID,
                deviceToken: token,
                itemId: item.id.uuidString,
                flightNumber: flightNumber,
                date: item.startsAt.map { Self.flightDateFormatter.string(from: $0) },
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

    private var installID: String {
        if let existing = userDefaults.string(forKey: installIDKey) {
            return existing
        }

        let value = UUID().uuidString
        userDefaults.set(value, forKey: installIDKey)
        return value
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

    private static let flightDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
    var itemId: String
    var flightNumber: String
    var date: String?
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
    var updatedAt: String?
    var warning: String?
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
