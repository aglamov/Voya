# Mobility Services Strategy

## Goal

Voya should treat movement between itinerary points as a first-class trip-support feature, not as a note in the timeline.

The mobility layer needs to answer seven product questions:

- How do I get from this place to the next one?
- How long will it take at the relevant time of day?
- When should I leave?
- Is public transport, taxi, driving, walking, or cycling the better choice?
- What buffer should I keep for airports, luggage, late-night arrivals, children, accessibility, or unfamiliar cities?
- What changed since the last forecast?
- Which map or transport app should open when the traveler is ready to go?

## Product Boundary

Voya should recommend and monitor transfers, but it should not pretend to operate the transport service.

For the first production version, "recommended transfer" means:

1. Voya knows the origin, destination, and timing from confirmed itinerary items or user-provided addresses.
2. A routing provider returns one or more route options.
3. Voya adds traveler-aware buffers and explains trade-offs.
4. The user can open the final route in Google Maps, Apple Maps, or a regional app.

Booking taxis, buying transit tickets, changing train reservations, and guaranteeing vehicle availability are separate provider or partnership tracks.

## Recommended Provider Stack

### 1. Server-Side Primary Routing

Use Google Routes API as the first global production provider.

Why it fits:

- Driving, traffic-aware driving, walking, cycling, and public transit routing.
- Duration and distance in a provider-neutral response.
- Route matrix support later for comparing many trip legs.
- Broad international coverage.
- Easy backend integration while keeping API keys off-device.

Use it through a Voya-owned `MobilityProvider` interface. The iOS app should never consume Google-specific payloads directly.

### 2. Native iOS Handoff

Use Apple MapKit for native map display and Apple Maps handoff.

Best uses:

- Showing a route preview inside the app.
- Opening Apple Maps with origin and destination.
- Using the platform-standard iOS experience when the traveler taps "Navigate".

Apple should be a presentation and handoff layer at first. Server-side route forecasting should remain provider-neutral so Android, web, jobs, and background refresh can use the same logic later.

### 3. Regional Providers

Add regional providers where they materially improve accuracy:

| Region / Use | Candidate | Why |
| --- | --- | --- |
| Russia / CIS | Yandex Maps or 2GIS | Better local addresses, traffic, public transport, and taxi ecosystem in many cities |
| UAE / some CIS cities | 2GIS / Urbi | Strong local POI and building-entrance data |
| Cities with open transit data | GTFS + GTFS Realtime | Cheaper refreshes and better station/stop detail where feeds are reliable |

Provider choice should be automatic by geography and capability, not a user-facing technical setting.

## Internal Model

Add normalized transfer entities on the backend.

```text
TransferPlan
- id
- tripId
- originItemId
- destinationItemId
- originLabel
- destinationLabel
- originPlace
- destinationPlace
- targetArrivalAt
- targetDepartureAt
- purpose: airport_departure | airport_arrival | hotel_checkin | event | station | free_move
- travelerContext
- selectedOptionId
- generatedAt
- expiresAt
- providerSet
```

```text
RouteOption
- id
- transferPlanId
- mode: taxi | drive | transit | walk | bike
- provider
- durationMinutes
- travelMinutes
- bufferMinutes
- distanceMeters
- departureTime
- arrivalTime
- leaveBy
- reliability: high | medium | low | unknown
- costLevel: low | medium | high | unknown
- comfortLevel: low | medium | high
- emissionsLevel: low | medium | high | unknown
- summary
- tradeoffs
- mapURL
- rawProviderPayload
```

```text
MobilityRecommendation
- transferPlanId
- recommendedRouteOptionId
- reason
- confidence
- nextRefreshAt
- alertThresholds
```

## Traveler Context

The recommendation engine should consider context that pure maps APIs do not know:

- flight departure and boarding time
- airport terminal and check-in deadline
- baggage and group size
- hotel check-in or checkout window
- late-night or early-morning arrival
- accessibility needs
- user preference for low cost, low stress, or low walking
- local language/script familiarity
- roaming/data availability
- weather and severe weather warnings

This belongs in Voya's ranking layer, not in the provider adapter.

## Recommendation Rules

Voya should rank options by a weighted score:

```text
score =
  travel_time_score
  + reliability_score
  + comfort_score
  + context_fit_score
  - cost_penalty
  - transfer_complexity_penalty
  - walking_luggage_penalty
  - late_night_penalty
```

Examples:

- Early airport departure with luggage: taxi may beat transit even if transit is cheaper.
- City-center airport with direct train: transit may beat taxi because it is reliable and cheaper.
- Late-night arrival: taxi may be recommended if transit has long waits or unsafe walking.
- Short hotel-to-event leg: walking may be recommended if weather is good and luggage is irrelevant.

The UI should explain the trade-off, not only label one option as "best".

## Buffers

Buffers should be explicit and visible.

Default starting points:

```text
Airport international departure: 120-180 min before scheduled departure
Airport domestic departure: 90-120 min before scheduled departure
Airport arrival to hotel: route duration + 20-45 min for baggage / immigration
Train station departure: 20-45 min
Event arrival: 10-30 min
Taxi pickup: 5-15 min
Unfamiliar city: +10-20 min
Bad weather or known disruption: +15-45 min
```

The app should say "Leave by 06:40" and show why: "38 min taxi + 10 min pickup + 120 min airport buffer."

## Refresh Cadence

Use cached route plans for planning, then refresh more aggressively near travel time.

```text
More than 7 days away: cache for 24-72 hours
7 days to 24 hours away: refresh daily
24 to 6 hours away: refresh every 3-6 hours
6 hours to 90 minutes away: refresh every 30-60 minutes
Less than 90 minutes away: refresh every 10-20 minutes if notifications are enabled
After target arrival: stop unless the user is actively navigating
```

Refreshes should generate alerts only when the traveler needs to act:

- leave-by time moved earlier by 10 minutes or more
- selected route becomes unavailable
- route duration increases by 15 minutes or more
- transit service disruption appears
- flight delay changes the needed departure time

## API Surface

The initial implemented slice is:

```text
POST /api/mobility
```

Example request:

```json
{
  "origin": { "address": "Hotel Artemide, Via Nazionale, Rome" },
  "destination": { "address": "Fiumicino Airport Terminal 3" },
  "arrivalTime": "2026-08-16T08:40:00Z",
  "modes": ["taxi", "transit", "drive"],
  "ownedVehicleAvailable": false,
  "airportBufferMinutes": 120,
  "taxiPickupBufferMinutes": 10,
  "locale": "en-US"
}
```

Example response shape:

```json
{
  "providerConnected": true,
  "provider": "google_routes",
  "originLabel": "Hotel Artemide, Via Nazionale, Rome",
  "destinationLabel": "Fiumicino Airport Terminal 3",
  "options": [
    {
      "mode": "taxi",
      "title": "Taxi",
      "durationMinutes": 158,
      "travelMinutes": 28,
      "bufferMinutes": 130,
      "leaveBy": "2026-08-16T06:02:00.000Z",
      "summary": "158 min total including 130 min buffer."
    }
  ],
  "recommendation": {
    "mode": "taxi",
    "title": "Taxi",
    "reason": "Best balance when time, luggage, or arrival stress matter more than price.",
    "leaveBy": "2026-08-16T06:02:00.000Z"
  },
  "warnings": []
}
```

Set `GOOGLE_ROUTES_API_KEY` or `GOOGLE_MAPS_API_KEY` in Vercel to enable live route duration, traffic-aware driving, and transit planning. Without a key, the endpoint still returns map handoff URLs and explicit warnings so the app can degrade gracefully.

## iOS UX

Each relevant gap between itinerary items should show a compact transfer module:

```text
Hotel -> Airport
Recommended: Taxi, leave by 06:02
28 min drive + 10 min pickup + 120 min airport buffer

Other options:
- Public transit: 54 min travel + 120 min buffer, cheaper, more walking
- Own car: 31 min travel + 120 min buffer, only recommended when a personal or rental car is available
```

Tapping opens:

- detailed route comparison
- refresh button
- "Open in Apple Maps"
- "Open in Google Maps"
- "Remind me when to leave"
- selected route for time-to-leave alerts

## Privacy And Cost Controls

- Keep provider keys server-side.
- Do not send booking references, passenger names, or ticket numbers to map providers.
- Cache route responses by coarse origin/destination/time bucket when allowed by provider terms.
- Store raw provider payloads only on the backend and redact logs.
- Use field masks for Google Routes to avoid paying for unused data.
- Prefer route matrix calls when comparing many legs in batch.
- Add per-user and per-trip refresh limits before enabling frequent background monitoring.

## Build Order

1. Backend `MobilityProvider` interface and `GoogleRoutesMobilityProvider`.
2. `POST /api/mobility` for on-demand route comparison.
3. iOS transfer comparison card on item detail and trip timeline gaps.
4. Store selected `TransferPlan` and `RouteOption` per itinerary gap.
5. Background refresh and time-to-leave alerts.
6. Apple Maps and Google Maps handoff buttons.
7. Regional provider routing by geography.
8. GTFS/GTFS Realtime enrichment in high-value cities.
