import Foundation

struct FlightCheckInAction: Identifiable {
    let id: UUID
    let item: ItineraryItem
    let flightNumber: String
    let airlineName: String?
    let confirmationCode: String?
    let opensAt: Date
    let departsAt: Date
    let checkInURL: URL
    let requiredDetails: [String]

    init?(item: ItineraryItem, now: Date = Date()) {
        guard item.kind == .flight,
              let departsAt = item.startsAt,
              departsAt > now else {
            return nil
        }

        let opensAt = departsAt.addingTimeInterval(-24 * 60 * 60)
        guard now >= opensAt else {
            return nil
        }

        let flightNumber = Self.flightNumber(in: "\(item.title) \(item.location)") ?? item.title
        let airlineName = item.providerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? Self.airlineName(forFlightNumber: flightNumber)
        let confirmationCode = item.confirmationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        self.id = item.id
        self.item = item
        self.flightNumber = flightNumber
        self.airlineName = airlineName
        self.confirmationCode = confirmationCode
        self.opensAt = opensAt
        self.departsAt = departsAt
        self.checkInURL = Self.checkInURL(flightNumber: flightNumber, airlineName: airlineName)
        self.requiredDetails = Self.requiredDetails(confirmationCode: confirmationCode)
    }

    static func checkInURL(for item: VoyaNotificationItem) -> URL? {
        guard item.kind == .flight else { return nil }
        let flightNumber = flightNumber(in: "\(item.title) \(item.location)") ?? item.title
        return checkInURL(
            flightNumber: flightNumber,
            airlineName: item.providerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? airlineName(forFlightNumber: flightNumber)
        )
    }

    static func airlineName(in value: String) -> String? {
        guard let flightNumber = flightNumber(in: value) else {
            return nil
        }

        return airlineName(forFlightNumber: flightNumber)
    }

    private static func requiredDetails(confirmationCode: String?) -> [String] {
        var details = [String]()
        if let confirmationCode {
            details.append(String(localized: "Booking reference: \(confirmationCode)"))
        } else {
            details.append(String(localized: "Booking reference / PNR"))
        }
        details.append(String(localized: "Passenger last name"))
        details.append(String(localized: "Passport or ID, if the airline asks for it"))
        return details
    }

    private static func flightNumber(in value: String) -> String? {
        guard let match = value.firstMatch(of: /[A-Z0-9]{2,3}\s?\d{1,4}[A-Z]?/) else {
            return nil
        }

        return String(match.output).replacingOccurrences(of: " ", with: "").uppercased()
    }

    private static func airlineName(forFlightNumber flightNumber: String) -> String? {
        guard let carrier = flightNumber.firstMatch(of: /^[A-Z0-9]{2,3}/).map({ String($0.output).uppercased() }) else {
            return nil
        }

        return airlineNames[carrier]
    }

    private static func checkInURL(flightNumber: String, airlineName: String?) -> URL {
        if let carrier = flightNumber.firstMatch(of: /^[A-Z0-9]{2,3}/).map({ String($0.output).uppercased() }),
           let directURL = airlineCheckInURLs[carrier] {
            return directURL
        }

        let query = [
            airlineName,
            flightNumber.isEmpty ? nil : flightNumber,
            String(localized: "online check-in")
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .joined(separator: " ")

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "online%20check-in"
        return URL(string: "https://www.google.com/search?q=\(encoded)") ?? URL(string: "https://www.google.com/search?q=online%20check-in")!
    }

    private static let airlineCheckInURLs: [String: URL] = [
        "AA": URL(string: "https://www.aa.com/reservation/flightCheckInViewReservationsAccess.do")!,
        "AC": URL(string: "https://www.aircanada.com/check-in")!,
        "AF": URL(string: "https://wwws.airfrance.com/check-in")!,
        "BA": URL(string: "https://www.britishairways.com/travel/olcilandingpageauthreq/public/en_gb")!,
        "DL": URL(string: "https://www.delta.com/us/en/check-in-security/check-in-time-requirements/online-check-in")!,
        "EK": URL(string: "https://www.emirates.com/english/manage-booking/online-check-in/")!,
        "IB": URL(string: "https://www.iberia.com/us/online-check-in/")!,
        "KL": URL(string: "https://www.klm.com/check-in")!,
        "LH": URL(string: "https://www.lufthansa.com/check-in")!,
        "QR": URL(string: "https://www.qatarairways.com/en/check-in.html")!,
        "TK": URL(string: "https://www.turkishairlines.com/en-int/flights/manage-booking/")!,
        "UA": URL(string: "https://www.united.com/checkin")!,
        "U2": URL(string: "https://www.easyjet.com/en/manage-booking/check-in")!,
        "W6": URL(string: "https://wizzair.com/en-gb/information-and-services/booking-information/check-in-and-boarding")!
    ]

    private static let airlineNames: [String: String] = [
        "AA": "American Airlines",
        "AC": "Air Canada",
        "AF": "Air France",
        "BA": "British Airways",
        "DL": "Delta Air Lines",
        "EK": "Emirates",
        "IB": "Iberia",
        "KL": "KLM",
        "LH": "Lufthansa",
        "QR": "Qatar Airways",
        "TK": "Turkish Airlines",
        "UA": "United Airlines",
        "U2": "easyJet",
        "W6": "Wizz Air"
    ]
}
