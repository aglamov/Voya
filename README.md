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
