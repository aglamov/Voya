# Voya

Voya is an AI-powered iPhone travel companion for inspiration, planning, and live trip support.

It helps people discover meaningful trips, compare smart travel options, manually import booking confirmations, and stay supported throughout the journey with itinerary timelines, flight alerts, transport guidance, and contextual help.

Voya is not a booking platform. It does not sell flights, hotels, events, or tours directly. Instead, it helps users choose well, book on the platforms they trust, and then brings the trip back into one calm, useful place.

## Product Positioning

Voya is a travel advisor and trip companion.

Before a trip, it helps answer:

- Where should I go?
- What fits my budget, dates, and preferences?
- Which destination gives me the best overall trip, not just the cheapest flight?
- What events, hotels, weather, transit, and local context matter?

During a trip, it helps answer:

- What is next in my itinerary?
- Has my flight, gate, terminal, or departure time changed?
- When should I leave for the airport, hotel, or event?
- How do I get there by public transport?
- What should I do if something changes?

## Core Principles

- No direct booking in the MVP.
- No email inbox connection.
- Users manually import confirmations.
- AI extracts structured trip data from uploaded files, screenshots, photos, PDFs, or pasted text.
- External booking links are used for flights, hotels, events, tours, and transport.
- The app should explain recommendations clearly instead of overwhelming users with endless options.
- The user stays in control whenever AI confidence is low.

## Core Flows

### Inspire Me

The user describes the kind of trip they want, and Voya turns that intent into concrete options.

Examples:

- "I want a warm 4-day trip under $700."
- "Find me a food-focused city with direct flights."
- "Where can I go in November without extreme heat?"
- "Plan a weekend around a concert or festival."

Voya compares destinations using budget, flight availability, hotel prices, weather, seasonality, events, visas, transit, and user preferences.

### Find Options

Voya surfaces strong options and links out to trusted booking platforms.

The app may compare:

- Flights
- Hotels
- Events
- Tours and experiences
- Airport transfer options
- Public transport convenience
- Time-to-leave and transfer reliability
- Weather and seasonality

### Import Confirmations

After booking elsewhere, the user manually uploads confirmations into Voya.

Supported sources can include:

- PDF confirmations
- Screenshots
- Photos
- Pasted text
- Files shared from another app

AI extracts structured data, asks the user to confirm uncertain fields, and adds verified items to the itinerary.

### Live Trip Support

Once the trip exists, Voya monitors and assists.

Examples:

- Flight status and delay alerts
- Gate, terminal, and departure time changes
- Check-in reminders
- Hotel check-in and check-out reminders
- Public transport route to hotel or event
- Time-to-leave notifications
- Comparisons between taxi, driving, public transport, walking, and cycling where relevant
- Contextual suggestions when plans change

## MVP Scope

- iPhone app.
- AI trip inspiration.
- Search and comparison using external APIs and deep links.
- Manual confirmation upload.
- AI parsing into structured itinerary items.
- User confirmation and correction flow.
- Timeline-based itinerary.
- Flight tracking and push notifications.
- Airport-to-hotel public transit guidance.
- Basic event discovery with external ticket links.

## Out of Scope for MVP

- Direct flight, hotel, or event booking.
- Payments.
- Refunds, cancellations, and booking support.
- Email inbox access.
- Full OTA or travel agency functionality.
- Automatic import from Gmail, Apple Mail, or Outlook.

## Product Brief

See [docs/product-brief.md](docs/product-brief.md) for the fuller concept, AI responsibilities, data model direction, and possible API providers.

See [docs/architecture.md](docs/architecture.md) for the initial iPhone app, backend, AI, data, and provider architecture.

See [docs/flight-services.md](docs/flight-services.md) for the recommended flight confirmation, live status, delay prediction, gate-change, and alert provider strategy.

See [docs/mobility-services.md](docs/mobility-services.md) for the recommended route planning, transfer recommendation, maps provider, time-to-leave, and regional mobility strategy.

## Vercel AI Extraction

The app calls a Vercel Function at `POST /api/extract` to recognize pasted or uploaded travel confirmations. The function calls OpenAI directly and returns normalized itinerary JSON for the review screen.

The trip detail screen can also call `POST /api/enrich` for event context cards such as weather, nearby events, warnings, maps, and flight-provider placeholders. Enrichment degrades gracefully: missing provider keys show "not connected" cards instead of breaking the trip view.

Required Vercel environment variables:

- `OPENAI_API_KEY`: OpenAI API key.
- `OPENAI_EXTRACT_MODEL`: optional model for confirmation extraction. Defaults to `gpt-5.5`.
- `OPENAI_REPAIR_MODEL`: optional model for invalid JSON repair. Defaults to `gpt-4o-mini`.
- `OPENAI_LOCATION_MODEL`: optional model for enrichment location normalization. Defaults to `gpt-4o-mini`.
- `OPENAI_BRIEF_MODEL`: optional model for travel brief generation. Defaults to `gpt-4o-mini`.
- `OPENAI_MODEL`: optional global fallback used when a task-specific model variable is not set.

Optional enrichment environment variables:

- `OPENWEATHER_API_KEY`: enables weather cards through OpenWeather geocoding and One Call APIs.
- `TICKETMASTER_API_KEY` or `TICKETMASTER_CONSUMER_KEY`: enables nearby public event cards and Ticketmaster event links through the Discovery API. Use the Consumer Key from Ticketmaster Developer; the Consumer Secret is not needed for Discovery event search.
- `FLIGHTAWARE_AEROAPI_KEY`: enables `GET/POST /api/flight-status` and `POST /api/booking-validation` through FlightAware AeroAPI for flight existence checks, airline schedules, gate assignments, gate times, baggage claim, delay fields, aircraft details, tracking data, and alert capability.
- `GOOGLE_ROUTES_API_KEY` or `GOOGLE_MAPS_API_KEY`: enables `POST /api/mobility` through Google Routes API for live transfer duration, traffic-aware driving, public transit, walking, cycling, route comparison, and time-to-leave planning.
- `VOYA_API_PUBLIC_BASE_URL`: optional public backend URL used to describe the FlightAware alert callback endpoint, for example `https://voya-lime.vercel.app`.

Flight support endpoints:

- `GET /api/flight-status?flightNumber=BA2490&date=2026-08-12&originAirport=LHR&destinationAirport=FCO`
- `POST /api/flight-status` with `{ "flightNumber": "BA2490", "date": "2026-08-12", "originAirport": "LHR", "destinationAirport": "FCO" }`
- `POST /api/booking-validation` combines imported-confirmation evidence, user review, and provider flight existence validation. It does not claim true PNR or ticket validation unless Voya later integrates directly with the airline, OTA, NDC, GDS, or booking provider.
- `GET/POST/DELETE /api/flightaware-alert-subscriptions` proxies FlightAware AeroAPI `/alerts` management calls while keeping the AeroAPI key server-side. Use the exact alert payload shape from FlightAware's `/alerts` documentation.
- `POST /api/flightaware-alerts` receives FlightAware alert callbacks after a FlightAware alert subscription points to this callback URL, then normalizes them for Voya alert generation.

Mobility support endpoints:

- `POST /api/mobility` with origin, destination, target arrival/departure time, candidate modes, and Voya buffer settings. It returns provider-neutral route options, total duration, travel duration, buffer minutes, leave-by time, trade-offs, map handoff URLs, and a recommended mode. Without a Google key, it returns explicit provider warnings and usable map handoff URLs instead of fake ETAs.

iOS configuration:

- Set the Xcode build setting `VOYA_API_BASE_URL` to the deployed Vercel URL, for example `https://your-project.vercel.app`.
- If the URL is not configured or the AI request fails, Voya falls back to the built-in on-device parser so imports still work during development.
