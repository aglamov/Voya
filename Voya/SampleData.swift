import SwiftUI

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
        ItineraryItem(kind: .flight, title: "BA2490 to Rome", time: "Aug 12, 09:40", location: "LHR Terminal 5", status: "On time"),
        ItineraryItem(kind: .transit, title: "Leonardo Express", time: "Aug 12, 14:05", location: "FCO to Termini", status: "42 min"),
        ItineraryItem(kind: .hotel, title: "Hotel Artemide", time: "Aug 12, 15:00", location: "Via Nazionale", status: "Confirmed"),
        ItineraryItem(kind: .event, title: "Trastevere food walk", time: "Aug 13, 19:30", location: "Piazza Trilussa", status: "Ticket link saved")
    ]

    static let alerts: [TravelAlert] = [
        TravelAlert(title: "Leave at 06:50", message: "Traffic is normal. This keeps 35 minutes of airport buffer.", severity: .calm),
        TravelAlert(title: "Gate not posted yet", message: "Voya will check again 2 hours before departure.", severity: .watch),
        TravelAlert(title: "Hotel route ready", message: "Fastest public transit option takes 42 minutes from FCO.", severity: .calm)
    ]
}
