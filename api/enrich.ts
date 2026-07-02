import type { VercelRequest, VercelResponse } from "@vercel/node";

type EnrichmentCard = {
  title: string;
  value: string;
  detail?: string;
  kind: "weather" | "flight" | "events" | "maps" | "ai" | "warning";
};

type EnrichmentResponse = {
  summary: string;
  cards: EnrichmentCard[];
  warnings: string[];
};

type EnrichmentRequest = {
  kind?: string;
  title?: string;
  location?: string;
  startsAt?: string | null;
  endsAt?: string | null;
  status?: string;
};

type GeocodeResult =
  | { place: { lat: number; lon: number; name?: string; country?: string } }
  | { error: "missing_input" | "provider_error" | "not_found"; status?: number };

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function firstFlightNumber(value: string) {
  return value.match(/\b[A-Z]{2}\s?\d{2,4}\b/i)?.[0]?.replace(/\s+/g, "").toUpperCase();
}

function stripAirportCode(value: string) {
  return value.replace(/\s*\([A-Z]{3}\)\s*/g, " ").replace(/\s+/g, " ").trim();
}

function destinationFromRoute(location: string) {
  const routeParts = location.split(/\s+\bto\b\s+/i).map((part) => part.trim()).filter(Boolean);
  return routeParts.length > 1 ? routeParts[routeParts.length - 1] : location;
}

function placeForExternalLookup(kind: string, location: string) {
  if (!location) {
    return "";
  }

  const place = kind === "flight" || kind === "transit"
    ? destinationFromRoute(location)
    : location;

  return stripAirportCode(place);
}

async function geocode(location: string) {
  const apiKey = process.env.OPENWEATHER_API_KEY;
  if (!apiKey || !location) {
    return { error: "missing_input" } satisfies GeocodeResult;
  }

  const url = new URL("https://api.openweathermap.org/geo/1.0/direct");
  url.searchParams.set("q", location);
  url.searchParams.set("limit", "1");
  url.searchParams.set("appid", apiKey);

  const response = await fetch(url);
  if (!response.ok) {
    return { error: "provider_error", status: response.status } satisfies GeocodeResult;
  }

  const places = (await response.json()) as Array<{ lat: number; lon: number; name?: string; country?: string }>;
  const place = places[0];

  return place ? { place } : { error: "not_found" } satisfies GeocodeResult;
}

async function weatherCard(location: string): Promise<EnrichmentCard> {
  const apiKey = process.env.OPENWEATHER_API_KEY;
  if (!apiKey) {
    return {
      title: "Weather",
      value: "Not connected",
      detail: "Set OPENWEATHER_API_KEY on Vercel to show live weather.",
      kind: "weather"
    };
  }

  const geocoded = await geocode(location);
  if ("error" in geocoded) {
    if (geocoded.error === "provider_error") {
      return {
        title: "Weather",
        value: "Unavailable",
        detail: `OpenWeather geocoding returned ${geocoded.status}.`,
        kind: "weather"
      };
    }

    return {
      title: "Weather",
      value: "Location needed",
      detail: location
        ? `OpenWeather could not find "${location}".`
        : "Add a clearer city, airport, hotel, or venue address.",
      kind: "weather"
    };
  }

  const place = geocoded.place;

  const url = new URL("https://api.openweathermap.org/data/4.0/onecall/current");
  url.searchParams.set("lat", String(place.lat));
  url.searchParams.set("lon", String(place.lon));
  url.searchParams.set("units", "metric");
  url.searchParams.set("lang", "en");
  url.searchParams.set("appid", apiKey);

  const response = await fetch(url);
  if (!response.ok) {
    return {
      title: "Weather",
      value: "Unavailable",
      detail: `OpenWeather returned ${response.status}.`,
      kind: "weather"
    };
  }

  const data = await response.json() as {
    data?: Array<{
      temp?: number;
      weather?: Array<{ description?: string }>;
      alerts?: string[];
    }>;
  };
  const current = data.data?.[0];
  const temp = current?.temp;
  const description = current?.weather?.[0]?.description;
  const alertCount = current?.alerts?.length ?? 0;

  return {
    title: "Weather",
    value: temp == null ? "Forecast ready" : `${Math.round(temp)} C`,
    detail: [description, alertCount > 0 ? `${alertCount} weather alert${alertCount === 1 ? "" : "s"}` : undefined].filter(Boolean).join(" · "),
    kind: alertCount > 0 ? "warning" : "weather"
  };
}

async function eventsCard(location: string): Promise<EnrichmentCard> {
  const apiKey = process.env.TICKETMASTER_API_KEY;
  if (!apiKey) {
    return {
      title: "Nearby events",
      value: "Not connected",
      detail: "Set TICKETMASTER_API_KEY on Vercel for local event context.",
      kind: "events"
    };
  }

  const url = new URL("https://app.ticketmaster.com/discovery/v2/events.json");
  url.searchParams.set("apikey", apiKey);
  url.searchParams.set("size", "3");
  url.searchParams.set("sort", "date,asc");
  if (location) {
    url.searchParams.set("city", location.split(",")[0]);
  }

  const response = await fetch(url);
  if (!response.ok) {
    return {
      title: "Nearby events",
      value: "Unavailable",
      detail: `Ticketmaster returned ${response.status}.`,
      kind: "events"
    };
  }

  const data = await response.json() as { page?: { totalElements?: number }; _embedded?: { events?: Array<{ name?: string }> } };
  const eventNames = data._embedded?.events?.map((event) => event.name).filter(Boolean).slice(0, 2);
  return {
    title: "Nearby events",
    value: `${data.page?.totalElements ?? 0} found`,
    detail: eventNames?.length ? eventNames.join(" · ") : "No major public events found nearby.",
    kind: "events"
  };
}

function flightCard(title: string, location: string): EnrichmentCard {
  const flightNumber = firstFlightNumber(`${title} ${location}`);
  if (!flightNumber) {
    return {
      title: "Flight",
      value: "No flight number",
      detail: "Add a flight number to enable live status providers later.",
      kind: "flight"
    };
  }

  return {
    title: "Flight",
    value: flightNumber,
    detail: "Ready for FlightAware, Amadeus, or Aviationstack status integration.",
    kind: "flight"
  };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const body = req.body as EnrichmentRequest;
  const kind = clean(body.kind).toLowerCase();
  const title = clean(body.title);
  const location = clean(body.location);
  const lookupPlace = placeForExternalLookup(kind, location);
  const status = clean(body.status);

  const cards: EnrichmentCard[] = [
    {
      title: "Status",
      value: status || "Needs review",
      detail: title || "Add a title for better context.",
      kind: "ai"
    },
    {
      title: "Maps",
      value: location ? "Ready" : "Location needed",
      detail: location || "Add an address, airport, hotel, venue, or city.",
      kind: "maps"
    },
    await weatherCard(lookupPlace),
    await eventsCard(lookupPlace)
  ];

  if (kind === "flight") {
    cards.splice(2, 0, flightCard(title, location));
  }

  const response: EnrichmentResponse = {
    summary: title ? `Useful context for ${title}.` : "Add more details to enrich this trip item.",
    cards,
    warnings: cards.filter((card) => card.kind === "warning").map((card) => `${card.title}: ${card.detail ?? card.value}`)
  };

  return res.status(200).json(response);
}
