import Foundation
import UIKit

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
        userDefaults.set(token, forKey: deviceTokenKey)
    }

    func registerFlightWatch(for item: ItineraryItem, candidate: FlightLookupCandidate? = nil) async {
        guard item.kind == .flight,
              let flightNumber = candidate?.flightNumber ?? Self.firstFlightNumber(in: "\(item.title) \(item.location)") else {
            return
        }

        let token = userDefaults.string(forKey: deviceTokenKey)
        await send(
            path: "api/flight-watch",
            payload: FlightWatchRegistrationPayload(
                appInstallId: installID,
                deviceToken: token,
                itemId: item.id.uuidString,
                flightNumber: flightNumber,
                date: item.startsAt.map { Self.flightDateFormatter.string(from: $0) },
                originAirport: candidate?.originAirport ?? candidate?.originAirportIcao,
                destinationAirport: candidate?.destinationAirport ?? candidate?.destinationAirportIcao
            )
        )
    }

    private func send<T: Encodable>(path: String, payload: T) async {
        guard let baseURL else {
            return
        }

        do {
            var request = URLRequest(url: baseURL.appendingPathComponent(path))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15
            request.httpBody = try JSONEncoder().encode(payload)
            _ = try await session.data(for: request)
        } catch {
            #if DEBUG
            print("[Voya] Push registration request failed: \(error.localizedDescription)")
            #endif
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

    private static let flightDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct FlightWatchRegistrationPayload: Encodable {
    var appInstallId: String
    var deviceToken: String?
    var itemId: String
    var flightNumber: String
    var date: String?
    var originAirport: String?
    var destinationAirport: String?
}
