import type { VercelRequest, VercelResponse } from "@vercel/node";

type EnrichmentCard = {
  title: string;
  value: string;
  detail?: string;
  actionURL?: string;
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
  startsAt?: string | number | null;
  endsAt?: string | number | null;
  status?: string;
};

type GeocodeResult =
  | { place: { lat: number; lon: number; name?: string; country?: string } }
  | { error: "missing_input" | "provider_error" | "not_found"; status?: number };

type Coordinates = { lat: number; lon: number; name: string; country?: string };

type TicketmasterEvent = {
  name?: string;
  url?: string;
  dates?: {
    start?: {
      localDate?: string;
      localTime?: string;
    };
  };
  _embedded?: {
    venues?: Array<{
      name?: string;
      city?: { name?: string };
    }>;
  };
};

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function firstFlightNumber(value: string) {
  return value.match(/\b[A-Z]{2}\s?\d{2,4}\b/i)?.[0]?.replace(/\s+/g, "").toUpperCase();
}

function asciiKey(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function stripAirportCode(value: string) {
  return value.replace(/\s*\([A-Z]{3}\)\s*/g, " ").replace(/\s+/g, " ").trim();
}

function parseCoordinatePair(latValue: string, lonValue: string, name = "Map point"): Coordinates | undefined {
  const lat = Number(latValue);
  const lon = Number(lonValue);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    return undefined;
  }
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
    return undefined;
  }

  return { lat, lon, name };
}

function coordinatesFromText(value: string, name = "Map point") {
  const atMatch = value.match(/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)(?:[,/?]|$)/);
  if (atMatch) {
    return parseCoordinatePair(atMatch[1], atMatch[2], name);
  }

  const bangMatch = value.match(/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/);
  if (bangMatch) {
    return parseCoordinatePair(bangMatch[1], bangMatch[2], name);
  }

  const plainMatch = value.match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/);
  if (plainMatch) {
    return parseCoordinatePair(plainMatch[1], plainMatch[2], name);
  }

  return undefined;
}

function isGoogleMapsHost(hostname: string) {
  return [
    "google.com",
    "www.google.com",
    "maps.google.com",
    "maps.app.goo.gl",
    "goo.gl"
  ].some((host) => hostname === host || hostname.endsWith(`.${host}`));
}

function mapURL(value: string) {
  try {
    const url = new URL(value);
    return isGoogleMapsHost(url.hostname) ? url : undefined;
  } catch {
    return undefined;
  }
}

function coordinatesFromMapURL(url: URL) {
  const directCoordinates = coordinatesFromText(decodeURIComponent(url.href));
  if (directCoordinates) {
    return directCoordinates;
  }

  for (const parameter of ["q", "query", "ll", "center"]) {
    const value = url.searchParams.get(parameter);
    if (!value) {
      continue;
    }
    const coordinates = coordinatesFromText(value, "Map point");
    if (coordinates) {
      return coordinates;
    }
  }

  return undefined;
}

function placeNameFromMapURL(url: URL) {
  const query = url.searchParams.get("q") ?? url.searchParams.get("query");
  if (query && !coordinatesFromText(query)) {
    return query;
  }

  const placeMatch = decodeURIComponent(url.pathname).match(/\/place\/([^/]+)/);
  if (!placeMatch) {
    return undefined;
  }

  return placeMatch[1].replace(/\+/g, " ").trim();
}

async function resolvedGoogleMapURL(value: string) {
  const url = mapURL(value);
  if (!url) {
    return undefined;
  }

  if (coordinatesFromMapURL(url) || placeNameFromMapURL(url)) {
    return url;
  }

  if (url.hostname !== "maps.app.goo.gl" && url.hostname !== "goo.gl") {
    return url;
  }

  try {
    for (const method of ["HEAD", "GET"] as const) {
      const response = await fetch(url, { method, redirect: "follow" });
      const resolvedURL = mapURL(response.url);
      if (resolvedURL && resolvedURL.href !== url.href) {
        return resolvedURL;
      }
    }
    return url;
  } catch {
    return url;
  }
}

function cityFromLocation(value: string) {
  const withoutRoute = destinationFromRoute(value);
  const withoutCodes = stripAirportCode(withoutRoute);
  const parts = withoutCodes.split(",").map((part) => part.trim()).filter(Boolean);

  return parts[0] ?? withoutCodes;
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

const knownCoordinates: Record<string, Coordinates> = {
  bio: { lat: 43.3011, lon: -2.9106, name: "Bilbao Airport", country: "ES" },
  bilbao: { lat: 43.263, lon: -2.935, name: "Bilbao", country: "ES" },
  zrh: { lat: 47.4581, lon: 8.5555, name: "Zurich Airport", country: "CH" },
  zurich: { lat: 47.3769, lon: 8.5417, name: "Zurich", country: "CH" },
  "bad ragaz": { lat: 47.006, lon: 9.5027, name: "Bad Ragaz", country: "CH" },
  london: { lat: 51.5072, lon: -0.1276, name: "London", country: "GB" }
};

function localCoordinates(location: string) {
  const directCoordinates = coordinatesFromText(location);
  if (directCoordinates) {
    return directCoordinates;
  }

  const airportCodes = [...location.matchAll(/\(([A-Z]{3})\)/g)].map((match) => match[1].toLowerCase());
  const lastAirportCode = airportCodes.at(-1);
  if (lastAirportCode && knownCoordinates[lastAirportCode]) {
    return knownCoordinates[lastAirportCode];
  }

  const candidates = [
    location,
    cityFromLocation(location),
    destinationFromRoute(location),
    ...location.split(",")
  ];

  for (const candidate of candidates) {
    const key = asciiKey(candidate);
    const coordinates = knownCoordinates[key];
    if (coordinates) {
      return coordinates;
    }
  }

  const locationKey = asciiKey(location);
  for (const [key, coordinates] of Object.entries(knownCoordinates)) {
    if (locationKey.includes(key)) {
      return coordinates;
    }
  }

  return undefined;
}

function ticketmasterApiKey() {
  return process.env.TICKETMASTER_API_KEY ?? process.env.TICKETMASTER_CONSUMER_KEY;
}

function parseRequestDate(value: string | number | null | undefined) {
  if (value == null || value === "") {
    return undefined;
  }

  const date = typeof value === "number"
    ? new Date((value < 1_000_000_000 ? value + 978_307_200 : value) * 1000)
    : new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

function ticketmasterDate(value: Date) {
  return value.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function eventSearchWindow(startsAt?: string | number | null, endsAt?: string | number | null) {
  const now = new Date();
  const start = parseRequestDate(startsAt) ?? now;
  const end = parseRequestDate(endsAt) ?? new Date(start.getTime() + 1000 * 60 * 60 * 24 * 7);
  const cappedEnd = end < start ? new Date(start.getTime() + 1000 * 60 * 60 * 24 * 7) : end;
  const effectiveStart = start < now ? now : start;

  return {
    start: effectiveStart,
    end: cappedEnd < effectiveStart ? new Date(effectiveStart.getTime() + 1000 * 60 * 60 * 24 * 7) : cappedEnd
  };
}

function formatEventDate(event: TicketmasterEvent) {
  const date = event.dates?.start?.localDate;
  const time = event.dates?.start?.localTime;
  if (!date) {
    return undefined;
  }

  const parsed = new Date(`${date}T${time ?? "00:00:00"}`);
  if (Number.isNaN(parsed.getTime())) {
    return time ? `${date} ${time.slice(0, 5)}` : date;
  }

  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "numeric",
    hour: time ? "numeric" : undefined,
    minute: time ? "2-digit" : undefined
  }).format(parsed);
}

function eventDetail(event: TicketmasterEvent) {
  const venue = event._embedded?.venues?.[0];
  const parts = [
    event.name,
    venue?.name,
    venue?.city?.name,
    formatEventDate(event)
  ].filter(Boolean);

  return parts.join(" · ");
}

async function geocode(location: string) {
  if (!location) {
    return { error: "missing_input" } satisfies GeocodeResult;
  }

  const googleMapURL = await resolvedGoogleMapURL(location);
  if (googleMapURL) {
    const coordinates = coordinatesFromMapURL(googleMapURL);
    if (coordinates) {
      return { place: coordinates };
    }

    const placeName = placeNameFromMapURL(googleMapURL);
    if (placeName) {
      const localPlace = localCoordinates(placeName);
      if (localPlace) {
        return { place: localPlace };
      }
      location = placeName;
    }
  }

  const localPlace = localCoordinates(location);
  if (localPlace) {
    return { place: localPlace };
  }

  const apiKey = process.env.OPENWEATHER_API_KEY;
  if (!apiKey) {
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

async function eventsCard(location: string, startsAt?: string | number | null, endsAt?: string | number | null): Promise<EnrichmentCard> {
  const apiKey = ticketmasterApiKey();
  if (!apiKey) {
    return {
      title: "Nearby events",
      value: "Not connected",
      detail: "Set TICKETMASTER_API_KEY or TICKETMASTER_CONSUMER_KEY on Vercel for local event context.",
      kind: "events"
    };
  }

  const url = new URL("https://app.ticketmaster.com/discovery/v2/events.json");
  const window = eventSearchWindow(startsAt, endsAt);
  url.searchParams.set("apikey", apiKey);
  url.searchParams.set("size", "5");
  url.searchParams.set("sort", "date,asc");
  url.searchParams.set("includeTBA", "no");
  url.searchParams.set("includeTBD", "no");
  url.searchParams.set("startDateTime", ticketmasterDate(window.start));
  url.searchParams.set("endDateTime", ticketmasterDate(window.end));

  if (location) {
    const geocoded = await geocode(location);
    const place = "place" in geocoded ? geocoded.place : undefined;
    if (place) {
      url.searchParams.set("latlong", `${place.lat},${place.lon}`);
      url.searchParams.set("radius", "35");
      url.searchParams.set("unit", "km");
      url.searchParams.set("sort", "distance,date,asc");
    } else {
      url.searchParams.set("city", cityFromLocation(location));
    }
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

  const data = await response.json() as { page?: { totalElements?: number }; _embedded?: { events?: TicketmasterEvent[] } };
  const events = data._embedded?.events ?? [];
  const firstEvent = events[0];
  const eventNames = events.map((event) => event.name).filter(Boolean).slice(0, 2);

  return {
    title: "Nearby events",
    value: `${data.page?.totalElements ?? 0} found`,
    detail: firstEvent ? eventDetail(firstEvent) : eventNames?.length ? eventNames.join(" · ") : "No major public events found nearby.",
    actionURL: firstEvent?.url,
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
    await eventsCard(lookupPlace, body.startsAt, body.endsAt)
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
