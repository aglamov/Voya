import SwiftUI

@MainActor
enum SampleData {
    static let recommendations: [TripRecommendation] = [
        TripRecommendation(
            destination: String(localized: "Lisbon"),
            dates: String(localized: "Sep 18-22"),
            fit: String(localized: "Best balance"),
            estimatedCost: String(localized: "$640 est."),
            details: [String(localized: "Direct evening flights"), String(localized: "Mild weather"), String(localized: "Easy metro from airport")],
            accent: .teal
        ),
        TripRecommendation(
            destination: String(localized: "Rome"),
            dates: String(localized: "Aug 12-16"),
            fit: String(localized: "Culture-heavy"),
            estimatedCost: String(localized: "$710 est."),
            details: [String(localized: "Great food itinerary"), String(localized: "Busy season"), String(localized: "Hotel prices trending up")],
            accent: .indigo
        ),
        TripRecommendation(
            destination: String(localized: "Barcelona"),
            dates: String(localized: "Oct 3-7"),
            fit: String(localized: "Events pick"),
            estimatedCost: String(localized: "$680 est."),
            details: [String(localized: "Strong event weekend"), String(localized: "Warm evenings"), String(localized: "Airport train is simple")],
            accent: .pink
        )
    ]

    static let itinerary: [ItineraryItem] = [
        ItineraryItem(
            kind: .flight,
            title: String(localized: "BA2490 to Rome"),
            location: "LHR Terminal 5",
            status: String(localized: "On time"),
            startsAt: date(month: 8, day: 12, hour: 9, minute: 40),
            endsAt: date(month: 8, day: 12, hour: 13, minute: 10)
        ),
        ItineraryItem(
            kind: .transit,
            title: "Leonardo Express",
            location: "FCO to Termini",
            status: String(localized: "42 min"),
            startsAt: date(month: 8, day: 12, hour: 14, minute: 5),
            endsAt: date(month: 8, day: 12, hour: 14, minute: 47)
        ),
        ItineraryItem(
            kind: .hotel,
            title: "Hotel Artemide",
            location: "Via Nazionale",
            status: String(localized: "Confirmed"),
            startsAt: date(month: 8, day: 12, hour: 15, minute: 0),
            endsAt: date(month: 8, day: 16, hour: 11, minute: 0)
        ),
        ItineraryItem(
            kind: .event,
            title: String(localized: "Trastevere food walk"),
            location: "Piazza Trilussa",
            status: String(localized: "Ticket link saved"),
            startsAt: date(month: 8, day: 13, hour: 19, minute: 30)
        )
    ]

    static let trips: [Trip] = [
        Trip(
            title: String(localized: "Rome"),
            dates: String(localized: "Aug 12-16"),
            summary: String(localized: "4 confirmed items from sample confirmations"),
            items: itinerary,
            sourceName: String(localized: "Sample itinerary")
        )
    ]

    private static func date(month: Int, day: Int, hour: Int, minute: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(
                year: Calendar.current.component(.year, from: Date()),
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        ) ?? Date()
    }
}
