# Voya

Voya is an AI-powered iPhone travel companion for organizing bookings and live trip support.

It helps people import booking confirmations, keep an itinerary, and stay supported throughout the journey with flight and weather alerts, transport guidance, and contextual help.

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

## OpenAI Build Week: Codex and GPT-5.6

Voya was developed for OpenAI Build Week with Codex as the primary engineering collaborator and GPT-5.6 as the reasoning layer behind the product's agentic travel workflows.

Codex was used to:

- Implement and refine the SwiftUI experience for Inspiration, Trips, Import, and Assistant.
- Design the bounded multi-agent architecture behind Trip Guardian.
- Build and debug the Vercel API routes and provider adapters.
- Add tests, simulator validation, production diagnostics, and operational documentation.
- Review failure states so missing provider data degrades visibly instead of becoming fabricated travel advice.

GPT-5.6 is used at runtime to:

- Extract structured itinerary data from pasted text and uploaded confirmations.
- Repair malformed extraction output while preserving confidence and review flags.
- Create concise trip briefs from itinerary and provider context.
- Perform a second-pass risk assessment after deterministic itinerary checks.
- Support specialist agents that reason over grounded flight, weather, mobility, place, air-quality, and pollen signals.

The model does not book travel, make payments, or silently overwrite uncertain details. Provider facts and deterministic checks are kept separate from model judgment, and low-confidence fields remain visible for user review.

## Quick Start for Judges

Requirements: macOS with Xcode and an iOS 18+ simulator.

1. Open `Voya.xcodeproj` in Xcode.
2. Select the `Voya` scheme and an iPhone simulator.
3. Build and run the app.
4. Try Inspiration, import a confirmation as text or a file, then inspect the generated trip and Trip Guardian.

The checked-in build configuration points to the deployed Vercel backend. If it is unavailable, confirmation import falls back to the built-in on-device parser so the core review flow remains testable. No judge credentials are required.

## Vercel AI Extraction

The app calls a Vercel Function at `POST /api/extract` to recognize pasted or uploaded travel confirmations. The function calls OpenAI directly and returns normalized itinerary JSON for the review screen.

The trip detail screen can also call `POST /api/enrich` for event context cards such as weather, nearby events, warnings, maps, and flight-provider placeholders. Enrichment degrades gracefully: missing provider keys show "not connected" cards instead of breaking the trip view.

Required Vercel environment variables:

- `OPENAI_API_KEY`: OpenAI API key.
- `OPENAI_EXTRACT_MODEL`: optional model for confirmation extraction. Defaults to `gpt-5.5`.
- `OPENAI_REPAIR_MODEL`: optional model for invalid JSON repair. Defaults to `gpt-5.4-mini`.
- `OPENAI_LOCATION_MODEL`: optional model for enrichment location normalization. Defaults to `gpt-5.4-mini`.
- `OPENAI_BRIEF_MODEL`: optional model for travel brief and second-pass risk assessment. Defaults to `gpt-5.6-terra`.
- `OPENAI_MODEL`: optional global fallback used when a task-specific model variable is not set.

Optional enrichment environment variables:

- `OPENWEATHER_API_KEY`: enables weather cards through OpenWeather geocoding and One Call APIs.
- `WEATHER_MONITOR_SECRET`: protects the QStash invocation of `/api/weather-monitor`.
- `WEATHER_MONITOR_SECRET`: optional separate secret for manual weather-monitor diagnostics.
- `WEATHER_MAX_GROUPS_PER_RUN`: optional OpenWeather cost ceiling; defaults to 12 coordinate groups per run.
- `TICKETMASTER_API_KEY` or `TICKETMASTER_CONSUMER_KEY`: enables nearby public event cards and Ticketmaster event links through the Discovery API. Use the Consumer Key from Ticketmaster Developer; the Consumer Secret is not needed for Discovery event search.
- `PEXELS_API_KEY`: enables curated landscape hero photos for trip destinations. The app falls back to Wikipedia when Pexels is unavailable or has no matching photo.
- `FLIGHTAWARE_AEROAPI_KEY`: enables `GET/POST /api/flight-status` and `POST /api/booking-validation` through FlightAware AeroAPI for flight existence checks, airline schedules, gate assignments, gate times, baggage claim, delay fields, aircraft details, tracking data, and alert capability.
- `GOOGLE_ROUTES_API_KEY` or `GOOGLE_MAPS_API_KEY`: enables `POST /api/mobility` through Google Routes API for live transfer duration, traffic-aware driving, public transit, walking, cycling, route comparison, and time-to-leave planning.
- `GOOGLE_PLACES_API_KEY`, `GOOGLE_AIR_QUALITY_API_KEY`, and `GOOGLE_POLLEN_API_KEY`: optionally enable separate Google credentials for place verification, current Universal AQI, and the three-day pollen outlook. If they are absent, Voya reuses the existing server-side `GOOGLE_MAPS_API_KEY` or `GOOGLE_ROUTES_API_KEY`, so one key can power all Google integrations when Places API (New), Air Quality API, Pollen API, and Routes API are enabled for it.
- `UBER_CLIENT_ID` and `UBER_CLIENT_SECRET`: optional Uber developer credentials. `GET /api/uber-diagnostics` checks whether OAuth and estimates/products endpoints are accessible without exposing secrets.
- `VOYA_API_PUBLIC_BASE_URL`: required public backend URL used for the FlightAware callback endpoint, for example `https://voya-lime.vercel.app`.
- `FLIGHTAWARE_ALERT_WEBHOOK_SECRET`: required shared secret for `POST /api/flightaware-alerts`.
- `VOYA_ADMIN_SECRET`: required for provider management and `/api/health` diagnostics.
- `VOYA_CLIENT_API_KEY`: recommended release-client key used together with anonymous installation IDs and rate limits. This is an abuse deterrent, not a replacement for App Attest.
- `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN`: required production Redis storage for rate limiting, watches, and deduplication.
- `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRIVATE_KEY`, and `APNS_ENV`: required push credentials. Use `APNS_ENV=production` for TestFlight/App Store builds.
- `VOYA_PUSH_TEST_DEVICE_TOKENS`: optional comma-separated APNs token fallback for testing webhook delivery before Redis-backed device registration is enabled.
- `FLIGHT_MONITOR_MAX_PER_RUN`: optional cap for adaptive FlightAware fallback checks performed by the existing agent-monitor schedule; defaults to 12.

Flight support endpoints:

- `GET /api/flight-status?flightNumber=BA2490&date=2026-08-12&originAirport=LHR&destinationAirport=FCO`
- `POST /api/flight-status` with `{ "flightNumber": "BA2490", "date": "2026-08-12", "originAirport": "LHR", "destinationAirport": "FCO" }`
- `POST /api/booking-validation` combines imported-confirmation evidence, user review, and provider flight existence validation. It does not claim true PNR or ticket validation unless Voya later integrates directly with the airline, OTA, NDC, GDS, or booking provider.
- `GET/POST/DELETE /api/flightaware-alert-subscriptions` proxies FlightAware AeroAPI `/alerts` management calls while keeping the AeroAPI key server-side. Use the exact alert payload shape from FlightAware's `/alerts` documentation.
- `POST /api/flight-watch` stores device-to-flight watch records, including the APNs token when supplied, so one provider callback can fan out to multiple travelers on the same flight. Pass `subscribeToAlerts: true` to create and remember a FlightAware alert rule for that watched flight.
- `GET/POST /api/flight-alert-self-test` powers the in-app live gate test. It selects a real upcoming flight without a departure gate, creates a FlightAware alert with impending-departure callbacks, registers fallback polling, sends an APNs confirmation, and exposes the persisted result for the current app installation.
- `POST /api/flightaware-alerts` receives FlightAware alert callbacks after a FlightAware alert subscription points to this callback URL, normalizes them, deduplicates gate/status changes, and sends APNs alerts to matching watched devices when APNs credentials are configured. If `FLIGHTAWARE_ALERT_WEBHOOK_SECRET` is set, use a callback URL such as `https://your-domain.vercel.app/api/flightaware-alerts?secret=...`.

Mobility support endpoints:

- `POST /api/mobility` with origin, destination, target arrival/departure time, candidate modes, and Voya buffer settings. Send `arrivalTimeZoneOffsetSeconds` or `departureTimeZoneOffsetSeconds` with a target so Voya can preserve its wall-clock time when the route is in another time zone. It returns provider-neutral route options, total duration, travel duration, buffer minutes, leave-by time, route time-zone identifiers, trade-offs, map handoff URLs, and a recommended mode. Without a Google key, it returns explicit provider warnings and usable map handoff URLs instead of fake ETAs.

Google travel context:

- `POST /api/enrich` resolves a hotel, venue, airport, or destination through Places Text Search and adds Google Places, air-quality, and pollen cards when the corresponding APIs are configured.
- `POST /api/guardian` evaluates the most relevant upcoming itinerary location and attributes air and pollen findings to Sentinel. Provider failures are omitted instead of replacing deterministic itinerary checks.
- Inspiration stories are enriched with a verified Google Maps destination handoff after the Curator orders the collection. Recurring missions receive the same provider context before a specialist runs.
- Results use short-lived in-memory caches and narrow Places field masks. Keep the shared Google key server-side, restrict it to the four enabled APIs, and preserve Google attribution in the UI. The protected `/api/health` endpoint makes real low-volume probe requests and reports reachability for Places, Air Quality, and Pollen separately.

Destination image endpoint:

- `POST /api/destination-image` with `{ "destination": "Bad Ragaz, Switzerland" }` searches Pexels for a high-resolution landscape image suited to the trip hero, returns photographer attribution, and keeps the provider key off-device. The iOS client falls back to Wikipedia.

Weather alert endpoints:

- `POST /api/weather-watch` registers an upcoming destination or non-flight itinerary location for an APNs device. It geocodes the location with OpenWeather and stores a short-lived watch in Redis.
- `GET/POST /api/weather-monitor` is the protected background job. It groups nearby watch points, resolves active OpenWeather alerts, deduplicates deliveries, and sends APNs notifications.
- See [docs/weather-alerts.md](docs/weather-alerts.md) for the QStash schedule, alert behavior, and operational limitations.

iOS configuration:

- Set the Xcode build setting `VOYA_API_BASE_URL` to the deployed Vercel URL, for example `https://your-project.vercel.app`.
- If `VOYA_CLIENT_API_KEY` is enabled in Vercel, inject the same value into the Release build setting without committing the secret.
- If the URL is not configured or the AI request fails, Voya falls back to the built-in on-device parser so imports still work during development.

Production setup and smoke tests are documented in [docs/production-runbook.md](docs/production-runbook.md).
