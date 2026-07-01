import SwiftUI

@MainActor
enum SampleData {
    static let recommendations: [TripRecommendation] = [
        TripRecommendation(
            destination: "Lisbon",
            dates: "Sep 18-22",
            fit: "Best balance",
            estimatedCost: "$640 est.",
            details: ["Direct evening flights", "Mild weather", "Easy metro from airport"],
            accent: .teal
        ),
        TripRecommendation(
            destination: "Rome",
            dates: "Aug 12-16",
            fit: "Culture-heavy",
            estimatedCost: "$710 est.",
            details: ["Great food itinerary", "Busy season", "Hotel prices trending up"],
            accent: .indigo
        ),
        TripRecommendation(
            destination: "Barcelona",
            dates: "Oct 3-7",
            fit: "Events pick",
            estimatedCost: "$680 est.",
            details: ["Strong event weekend", "Warm evenings", "Airport train is simple"],
            accent: .pink
        )
    ]

    static let itinerary: [ItineraryItem] = [
        ItineraryItem(
            kind: .flight,
            title: "BA2490 to Rome",
            location: "LHR Terminal 5",
            status: "On time",
            startsAt: date(month: 8, day: 12, hour: 9, minute: 40),
            endsAt: date(month: 8, day: 12, hour: 13, minute: 10)
        ),
        ItineraryItem(
            kind: .transit,
            title: "Leonardo Express",
            location: "FCO to Termini",
            status: "42 min",
            startsAt: date(month: 8, day: 12, hour: 14, minute: 5),
            endsAt: date(month: 8, day: 12, hour: 14, minute: 47)
        ),
        ItineraryItem(
            kind: .hotel,
            title: "Hotel Artemide",
            location: "Via Nazionale",
            status: "Confirmed",
            startsAt: date(month: 8, day: 12, hour: 15, minute: 0),
            endsAt: date(month: 8, day: 16, hour: 11, minute: 0)
        ),
        ItineraryItem(
            kind: .event,
            title: "Trastevere food walk",
            location: "Piazza Trilussa",
            status: "Ticket link saved",
            startsAt: date(month: 8, day: 13, hour: 19, minute: 30)
        )
    ]

    static let trips: [Trip] = [
        Trip(
            title: "Rome",
            dates: "Aug 12-16",
            summary: "4 confirmed items from sample confirmations",
            items: itinerary,
            sourceName: "Sample itinerary"
        )
    ]

    static let alerts: [TravelAlert] = [
        TravelAlert(title: "Leave at 06:50", message: "Traffic is normal. This keeps 35 minutes of airport buffer.", severity: .calm),
        TravelAlert(title: "Gate not posted yet", message: "Voya will check again 2 hours before departure.", severity: .watch),
        TravelAlert(title: "Hotel route ready", message: "Fastest public transit option takes 42 minutes from FCO.", severity: .calm)
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
