import Foundation
import UserNotifications

struct VoyaNotificationTrip: Sendable {
    let id: UUID
    let title: String
    let items: [VoyaNotificationItem]
}

struct VoyaNotificationItem: Sendable {
    let id: UUID
    let kind: ItineraryKind
    let title: String
    let location: String
    let status: String
    let sourceName: String?
    let confirmationCode: String?
    let providerName: String?
    let startsAt: Date?
    let endsAt: Date?
}

@MainActor
final class VoyaNotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = VoyaNotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "voya.trip."
    private var hasRequestedAuthorization = false

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            guard !hasRequestedAuthorization else {
                return false
            }

            hasRequestedAuthorization = true
            do {
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func syncNotifications(for trips: [VoyaNotificationTrip], now: Date = Date()) async {
        await cancelScheduledVoyaNotifications()

        let requests = trips
            .flatMap { trip in
                notificationRequests(for: trip, now: now)
            }
            .prefix(64)

        guard !requests.isEmpty else {
            return
        }

        guard await requestAuthorizationIfNeeded() else {
            return
        }

        for request in requests {
            do {
                try await center.add(request)
            } catch {
                continue
            }
        }
    }

    func cancelNotifications(for tripID: UUID) async {
        let prefix = "\(identifierPrefix)\(tripID.uuidString)."
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelScheduledVoyaNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func scheduleTransferNotification(
        context: MobilityTransferContext,
        option: MobilityRouteOption,
        now: Date = Date()
    ) async {
        guard let leaveBy = option.leaveBy,
              let triggerDate = Self.date(from: leaveBy),
              triggerDate > now.addingTimeInterval(60),
              await requestAuthorizationIfNeeded() else {
            return
        }

        let identifier = "\(identifierPrefix)transfer.\(context.id)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to leave")
        content.subtitle = option.title
        content.body = String(localized: "Open the route and start moving to \(context.destination).")
        content.sound = .default
        content.threadIdentifier = context.id
        content.userInfo = [
            "transferID": context.id,
            "kind": "transfer",
            "mode": option.mode.rawValue
        ]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
            repeats: false
        )

        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: trigger
                )
            )
        } catch {
            return
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private func notificationRequests(for trip: VoyaNotificationTrip, now: Date) -> [UNNotificationRequest] {
        tripStartNotificationRequests(for: trip, now: now) + trip.items.flatMap { item in
            notificationRequests(for: item, in: trip, now: now)
        }
    }

    private func tripStartNotificationRequests(for trip: VoyaNotificationTrip, now: Date) -> [UNNotificationRequest] {
        guard let firstStart = trip.items.compactMap(\.startsAt).min() else {
            return []
        }

        let triggerDate = firstStart.addingTimeInterval(TimeInterval(-3 * 24 * 60 * 60))
        guard triggerDate > now.addingTimeInterval(60) else {
            return []
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Trip starts in 3 days")
        content.subtitle = trip.title
        content.body = String(localized: "Check the plan, documents, route, and buffers before \(trip.title).")
        content.sound = .default
        content.threadIdentifier = trip.id.uuidString
        content.userInfo = [
            "tripID": trip.id.uuidString,
            "kind": "trip"
        ]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
            repeats: false
        )

        return [
            UNNotificationRequest(
                identifier: "\(identifierPrefix)\(trip.id.uuidString).trip-start-3d",
                content: content,
                trigger: trigger
            )
        ]
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func notificationRequests(for item: VoyaNotificationItem, in trip: VoyaNotificationTrip, now: Date) -> [UNNotificationRequest] {
        reminderSpecs(for: item).compactMap { spec in
            guard let triggerDate = spec.triggerDate(for: item),
                  triggerDate > now.addingTimeInterval(60) else {
                return nil
            }

            let content = UNMutableNotificationContent()
            content.title = spec.title(for: item, trip: trip)
            content.subtitle = trip.title
            content.body = spec.body(for: item)
            content.sound = .default
            content.threadIdentifier = trip.id.uuidString
            content.userInfo = [
                "tripID": trip.id.uuidString,
                "itemID": item.id.uuidString,
                "kind": item.kind.rawValue,
                "checkInURL": FlightCheckInAction.checkInURL(for: item)?.absoluteString ?? ""
            ]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
                repeats: false
            )

            return UNNotificationRequest(
                identifier: "\(identifierPrefix)\(trip.id.uuidString).\(item.id.uuidString).\(spec.id)",
                content: content,
                trigger: trigger
            )
        }
    }

    private func reminderSpecs(for item: VoyaNotificationItem) -> [ItineraryReminderSpec] {
        switch item.kind {
        case .flight:
            return [
                .beforeStart(id: "flight-24h", minutes: 24 * 60),
                .beforeStart(id: "flight-3h", minutes: 3 * 60),
                .atStart(id: "flight-departure")
            ]
        case .hotel:
            return [
                .beforeStart(id: "hotel-checkin-3h", minutes: 3 * 60),
                .atStart(id: "hotel-checkin"),
                .beforeEnd(id: "hotel-checkout-1h", minutes: 60)
            ]
        case .event:
            return [
                .beforeStart(id: "event-2h", minutes: 2 * 60),
                .beforeStart(id: "event-30m", minutes: 30),
                .atStart(id: "event-start")
            ]
        case .transit:
            return [
                .beforeStart(id: "transit-leave", minutes: 30),
                .atStart(id: "transit-departure")
            ]
        }
    }
}

private enum ItineraryReminderSpec {
    case beforeStart(id: String, minutes: Int)
    case atStart(id: String)
    case beforeEnd(id: String, minutes: Int)

    var id: String {
        switch self {
        case .beforeStart(let id, _), .atStart(let id), .beforeEnd(let id, _):
            id
        }
    }

    func triggerDate(for item: VoyaNotificationItem) -> Date? {
        switch self {
        case .beforeStart(_, let minutes):
            return item.startsAt?.addingTimeInterval(TimeInterval(-minutes * 60))
        case .atStart:
            return item.startsAt
        case .beforeEnd(_, let minutes):
            return item.endsAt?.addingTimeInterval(TimeInterval(-minutes * 60))
        }
    }

    func title(for item: VoyaNotificationItem, trip: VoyaNotificationTrip) -> String {
        switch self {
        case .beforeStart(let id, let minutes):
            if id == "transit-leave" {
                return String(localized: "Time to leave")
            }
            if id == "flight-24h" {
                return String(localized: "Online check-in opens")
            }
            return String(localized: "\(item.kind.displayName) in \(Self.displayLeadTime(minutes))")
        case .atStart:
            return startTitle(for: item)
        case .beforeEnd(_, let minutes):
            return String(localized: "\(item.kind.displayName) ends in \(Self.displayLeadTime(minutes))")
        }
    }

    func body(for item: VoyaNotificationItem) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = item.status.trimmingCharacters(in: .whitespacesAndNewlines)

        let firstPart = title.isEmpty ? item.kind.displayName : title
        let secondPart = location.isEmpty ? status : location
        if case .beforeStart(let id, _) = self, id == "transit-leave" {
            return secondPart.isEmpty
                ? String(localized: "Open the route and start moving.")
                : String(localized: "Open the route and start moving to \(secondPart).")
        }
        if case .beforeStart(let id, _) = self, id == "flight-24h" {
            return flightCheckInBody(for: item, fallbackTitle: firstPart)
        }

        return secondPart.isEmpty ? firstPart : "\(firstPart) · \(secondPart)"
    }

    private func flightCheckInBody(for item: VoyaNotificationItem, fallbackTitle: String) -> String {
        let booking = item.confirmationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let provider = item.providerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let checkInURL = FlightCheckInAction.checkInURL(for: item)?.absoluteString

        var parts = [String]()
        parts.append(provider.map { String(localized: "Use \($0) check-in for \(fallbackTitle).") } ?? String(localized: "Use airline check-in for \(fallbackTitle)."))
        parts.append(booking.map { String(localized: "PNR: \($0).") } ?? String(localized: "Have your PNR ready."))
        parts.append(String(localized: "You may need passenger last name and passport/ID."))
        if let checkInURL {
            parts.append(checkInURL)
        }
        return parts.joined(separator: " ")
    }

    private func startTitle(for item: VoyaNotificationItem) -> String {
        switch item.kind {
        case .flight:
            return String(localized: "Departure time")
        case .hotel:
            return String(localized: "Check-in time")
        case .event:
            return String(localized: "Event starts")
        case .transit:
            return String(localized: "Transit starts")
        }
    }

    private static func displayLeadTime(_ minutes: Int) -> String {
        if minutes >= 24 * 60, minutes.isMultiple(of: 24 * 60) {
            let days = minutes / (24 * 60)
            return String(localized: "\(days) \(days == 1 ? "day" : "days")")
        }

        if minutes >= 60, minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return String(localized: "\(hours) \(hours == 1 ? "hour" : "hours")")
        }

        return String(localized: "\(minutes) min")
    }
}
