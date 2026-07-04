# Voya Product Brief

## Vision

Voya is an AI travel companion for iPhone that helps people discover inspiring trips, choose smart travel options, manually import their bookings, and feel supported during the journey.

The product exists for travelers who do not want another booking site. They want help deciding where to go, understanding trade-offs, keeping plans organized, and reacting calmly when travel changes.

## One-Liner

Voya helps travelers find better trips, bring their bookings into one place, and get live support before and during the journey.

## Positioning

Voya is not a replacement for airlines, hotels, event platforms, or online travel agencies. It is the intelligent layer around them.

Users book wherever they prefer. Voya helps them decide, then supports the trip after confirmation details are imported manually.

## What Makes Voya Different

Traditional itinerary apps mostly organize what the user already booked. Voya starts earlier and stays useful longer.

- Before booking: inspiration, comparison, and recommendation.
- After booking: confirmation parsing and itinerary building.
- During travel: live alerts, routing, reminders, and contextual guidance.

## Product Principles

- Be a trusted advisor, not a booking gatekeeper.
- Keep the user in control.
- Do not require inbox access.
- Prefer a few strong recommendations over endless search results.
- Explain trade-offs in plain language.
- Treat AI output as helpful but verifiable.
- Ask for confirmation when extracted data is uncertain.
- Keep travel support calm, timely, and actionable.

## Core User Jobs

### 1. Find Inspiration

The user wants to travel but does not know where to go.

Voya should understand vague intent:

- budget
- dates
- departure city or airport
- travel style
- climate preference
- visa constraints
- trip length
- interests
- tolerance for layovers
- desired pace

Then it should propose a small set of trips with clear reasons.

### 2. Compare Practical Options

The user wants to know what is actually worth booking.

Voya should compare the full trip, not only the flight:

- estimated flight price
- estimated hotel price
- destination convenience
- airport-to-city transit
- time-to-leave and transfer reliability
- weather
- events
- seasonality
- safety and practical constraints
- total estimated cost
- hidden trade-offs, such as long transfers or awkward arrival times

### 3. Bring Bookings Into One Place

After booking elsewhere, the user manually uploads confirmation documents.

Voya should support:

- PDF upload
- screenshot upload
- photo upload
- pasted text
- iOS share sheet import

AI should extract structured trip data and present it for review before saving.

### 4. Support the Traveler Live

Voya should monitor itinerary items and help the user act.

Examples:

- "Your gate changed from B12 to C4."
- "Your flight is delayed by 45 minutes."
- "Leave in 25 minutes to reach the airport comfortably."
- "The public transit route to your hotel takes 42 minutes."
- "Your event starts at 19:30. The best route from the hotel leaves at 18:45."

### 5. Move Between Trip Points

The user wants to know the best way to move through the trip, not just where each booking is.

Voya should:

- infer likely origin and destination from confirmed itinerary items
- ask for missing home, hotel, terminal, or venue details only when needed
- compare taxi, driving, public transit, walking, and cycling where available
- include context-aware buffers for airport security, baggage, check-in, weather, late-night arrivals, and unfamiliar cities
- recommend a route with a plain-language reason
- refresh route timing near departure and warn only when the traveler needs to act
- open the selected route in Apple Maps, Google Maps, or a regional map app

## AI Responsibilities

### Inspiration AI

The AI helps translate user intent into travel options.

Responsibilities:

- infer preferences from natural language
- ask concise follow-up questions when necessary
- turn vague desires into structured search parameters
- compare options across multiple dimensions
- explain why a destination fits
- highlight risks and trade-offs

### Confirmation Parsing AI

The AI extracts structured data from unstructured confirmations.

Supported document types:

- flights
- hotels
- trains
- buses
- car rentals
- events
- tours and activities
- restaurant reservations
- travel insurance

Extraction should produce normalized data with confidence scores. Low-confidence fields should be shown to the user for correction.

Example flight structure:

```json
{
  "type": "flight",
  "provider": "British Airways",
  "confirmationCode": "ABC123",
  "segments": [
    {
      "flightNumber": "BA2490",
      "departureAirport": "LHR",
      "arrivalAirport": "FCO",
      "departureTime": "2026-08-12T09:40:00",
      "arrivalTime": "2026-08-12T13:10:00"
    }
  ],
  "confidence": 0.91
}
```

### Trip Support AI

The AI explains live changes and suggests actions.

Examples:

- explain a delay in simple terms
- determine whether a connection is risky
- recommend when to leave
- suggest alternative transport
- identify impacted events or hotel check-in timing

## Manual Import UX

The import experience should feel like a travel inbox inside the app.

Primary entry point:

- `+ Add confirmation`

Import options:

- Photo
- Screenshot
- PDF
- Paste text
- Share from another app

After import, Voya should show a review card:

> I found a flight: BA2490, London Heathrow to Rome Fiumicino, August 12, 09:40. Is this correct?

The user can confirm, edit, or discard before the item enters the itinerary.

## MVP Feature Set

### Must Have

- iPhone app
- trip inspiration flow
- destination recommendation cards
- external booking links
- manual confirmation upload
- AI extraction into structured itinerary items
- confirmation review and edit screen
- timeline itinerary
- flight tracking
- push notifications for key flight changes
- public transit route from airport to hotel

### Should Have

- event discovery
- external ticket links
- hotel and flight price estimate comparisons
- total trip cost estimate
- weather and seasonality context
- time-to-leave reminders

### Later

- collaborative trips
- offline itinerary mode
- wallet integration
- Apple Calendar export
- Apple Maps and Google Maps handoff
- richer disruption handling
- alternative flight suggestions
- loyalty program awareness
- shared family or group travel view

## Explicitly Out of Scope

- direct booking
- payment processing
- refunds and cancellations
- customer support for bookings
- email inbox connection
- automatic email scanning
- operating as a travel agency

## Possible API Categories

### Flights and Inspiration

- Amadeus for Developers
- Duffel
- Skyscanner partner APIs
- Kiwi Tequila
- Sabre or Travelport for later enterprise-grade access

### Flight Status

- FlightAware AeroAPI
- Amadeus Flight Status
- Cirium
- OAG
- FlightStats

### Hotels

- Amadeus Hotels
- Expedia Rapid
- Hotelbeds / HBX
- Booking.com partner or affiliate options

### Events and Experiences

- Ticketmaster Discovery API
- Eventbrite
- GetYourGuide
- Viator
- Klook
- Fever
- Tiqets

### Maps and Transit

- Google Maps Platform
- Apple MapKit
- Google Routes API
- GTFS and GTFS Realtime for supported cities
- Yandex Maps or 2GIS where local coverage is materially stronger

## Early Monetization Ideas

- premium subscription for live monitoring and AI support
- affiliate revenue from external booking links
- premium trip planning packs
- paid event or experience referrals
- family or group travel subscription tier

## Risks

- Recommendation quality depends on API coverage and pricing data freshness.
- Flight status accuracy is critical for user trust.
- Confirmation parsing must be reliable enough to avoid itinerary mistakes.
- Affiliate links may limit control over conversion and availability.
- AI explanations must not overpromise certainty.

## Near-Term Product Question

The most important early question:

> Can Voya consistently give users three better travel options than they would find by opening five separate apps themselves?

If the answer is yes, the product has a reason to exist even before direct booking.

## Architecture

See [architecture.md](architecture.md) for the initial technical architecture.
