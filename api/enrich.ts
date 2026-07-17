import type { VercelRequest, VercelResponse } from "@vercel/node";
import { openai } from "@ai-sdk/openai";
import { generateObject } from "ai";
import { z } from "zod";
import { getFlightStatus } from "./_flight.js";
import { openAIModelFor } from "./_ai-models.js";
import { weatherAlertDetails } from "./_weather.js";
import { protectPublicEndpoint } from "./_security.js";

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
  briefMarkdown: string;
  sections: TravelBriefSection[];
  actions: TravelAction[];
  routeLegs: TravelRouteLeg[];
  imageURLs: string[];
  nearbyEvents: NearbyEvent[];
};

type NearbyEvent = {
  id: string;
  name: string;
  url?: string;
  localDate?: string;
  localTime?: string;
  venue?: string;
  city?: string;
};

type TravelBriefSection = {
  title: string;
  body: string;
  kind: "overview" | "route" | "weather" | "event" | "flight" | "place" | "risk" | "action";
};

type TravelAction = {
  title: string;
  detail: string;
  priority: "now" | "soon" | "later";
  kind: "route" | "weather" | "booking" | "flight" | "event" | "safety" | "context";
  actionURL?: string;
};

type TravelRouteLeg = {
  title: string;
  origin?: string;
  destination?: string;
  guidance: string;
  bufferMinutes?: number;
  mapURL?: string;
};

type EnrichmentRequest = {
  kind?: string;
  title?: string;
  location?: string;
  startsAt?: string | number | null;
  endsAt?: string | number | null;
  status?: string;
  locale?: string;
  languageCode?: string;
  languageName?: string;
};

type GeocodeResult =
  | { place: { lat: number; lon: number; name?: string; country?: string } }
  | { error: "missing_input" | "provider_error" | "not_found"; status?: number };

type Coordinates = { lat: number; lon: number; name: string; country?: string };

type LocationLookup = {
  query: string;
  coordinates?: Coordinates;
  source: "deterministic" | "ai" | "raw";
};

type TicketmasterEvent = {
  id?: string;
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

const locationNormalizationSchema = z.object({
  displayName: z.string().min(1).describe("Short human-readable place or venue name."),
  city: z.string().min(1).describe("City or locality containing the itinerary location."),
  country: z.string().optional().nullable(),
  weatherQuery: z.string().min(1).describe("Nearest major city and country for provider lookups, not the venue or street address."),
  eventsQuery: z.string().min(1).describe("The same nearest major city and country used for nearby event discovery."),
  coordinates: z.object({
    lat: z.number().min(-90).max(90),
    lon: z.number().min(-180).max(180)
  }).optional().nullable().describe("Only include coordinates if they are explicit in the input, not guessed."),
  confidence: z.number().min(0).max(1)
});

const travelBriefSchema = z.object({
  summary: z.string().min(1).describe("A concise human travel-assistant summary."),
  briefMarkdown: z.string().min(1).describe("Formatted Markdown travel brief with short sections and bullets."),
  sections: z.array(z.object({
    title: z.string().min(1),
    body: z.string().min(1),
    kind: z.enum(["overview", "route", "weather", "event", "flight", "place", "risk", "action"])
  })).min(3).max(7),
  actions: z.array(z.object({
    title: z.string().min(1),
    detail: z.string().min(1),
    priority: z.enum(["now", "soon", "later"]),
    kind: z.enum(["route", "weather", "booking", "flight", "event", "safety", "context"]),
    actionURL: z.string().url().optional().nullable()
  })).min(2).max(5),
  routeLegs: z.array(z.object({
    title: z.string().min(1),
    origin: z.string().optional().nullable(),
    destination: z.string().optional().nullable(),
    guidance: z.string().min(1),
    bufferMinutes: z.number().int().min(0).max(240).optional().nullable(),
    mapURL: z.string().url().optional().nullable()
  })).max(4)
});

type TravelBriefGenerated = z.infer<typeof travelBriefSchema>;

const locationModelName = () => openAIModelFor("location");
const briefModelName = () => openAIModelFor("brief");

function responseLanguageInstruction(languageCode?: string, languageName?: string, locale?: string) {
  const code = clean(languageCode) || "en";
  const name = clean(languageName) || code;
  const region = clean(locale) || code;

  if (code.toLowerCase().startsWith("en")) {
    return "Write all human-facing assistant text in English.";
  }

  return [
    `Write all human-facing assistant text in ${name} (locale ${region}).`,
    "This includes summary, briefMarkdown, section titles/bodies, action titles/details, route-leg titles/guidance, card titles you create, and warnings you create.",
    "Keep airline codes, flight numbers, airport codes, confirmation codes, URLs, hotel/venue names, street addresses, provider values, and proper nouns as shown unless a localized form is obvious.",
    "Do not translate machine enum values such as priority, kind, or URLs."
  ].join(" ");
}

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function firstFlightNumber(value: string) {
  return value.match(/\b[A-Z0-9]{2}\s?\d{2,4}\b/i)?.[0]?.replace(/\s+/g, "").toUpperCase();
}

function allFlightNumbers(value: string) {
  return [...new Set(
    [...value.matchAll(/\b[A-Z0-9]{2}\s?\d{2,4}\b/gi)]
      .map((match) => match[0].replace(/\s+/g, "").toUpperCase())
  )];
}

function airportCodesFromText(value: string) {
  return [...value.matchAll(/\b[A-Z]{3}\b/g)].map((match) => match[0].toUpperCase());
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
  const withoutCodes = stripAirportCode(withoutRoute)
    .replace(/\b(?:airport|aeroport|flughafen|terminal\s+\d+|main station|station)\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
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

async function deterministicLocationLookup(kind: string, location: string): Promise<LocationLookup | undefined> {
  const query = placeForExternalLookup(kind, location);
  if (!query) {
    return undefined;
  }

  const googleMapURL = await resolvedGoogleMapURL(query);
  if (googleMapURL) {
    const coordinates = coordinatesFromMapURL(googleMapURL);
    if (coordinates) {
      return { query, coordinates, source: "deterministic" };
    }

    const placeName = placeNameFromMapURL(googleMapURL);
    if (placeName) {
      const localPlace = localCoordinates(placeName);
      if (localPlace) {
        return { query: placeName, coordinates: localPlace, source: "deterministic" };
      }
      return { query: placeName, source: "deterministic" };
    }
  }

  const coordinates = localCoordinates(query);
  if (coordinates) {
    return { query, coordinates, source: "deterministic" };
  }

  return { query, source: "raw" };
}

async function aiLocationLookup(kind: string, title: string, location: string): Promise<LocationLookup | undefined> {
  if (!process.env.OPENAI_API_KEY || !location) {
    return undefined;
  }

  try {
    const { object } = await generateObject({
      model: openai(locationModelName()),
      schema: locationNormalizationSchema,
      schemaName: "LocationNormalization",
      schemaDescription: "Normalized provider lookup location for a travel itinerary item.",
      system: [
        "You normalize a travel itinerary item's location for weather and nearby event provider lookups.",
        "Return concise structured JSON only.",
        "For flight or transit routes, use the destination as the weather/events location, not the origin.",
        "Use one shared provider location for both weather and nearby-event lookups.",
        "Use the nearest major city with reliable city-level provider coverage, never a venue, neighborhood, suburb, or street address.",
        "For example, use 'Bilbao, Spain' for Getxo and 'Zurich, Switzerland' for a Zurich venue.",
        "Return the same major-city value in weatherQuery and eventsQuery.",
        "If the input is a Google Maps URL or long address, extract the venue, city, and country if visible.",
        "Do not invent precise coordinates. Include coordinates only if they are explicitly present in the input.",
        "If coordinates are not explicit, still return both provider queries."
      ].join(" "),
      prompt: [
        `Kind: ${kind || "unknown"}`,
        `Title: ${title || "unknown"}`,
        `Location: ${location}`,
        "",
        "Normalize this location for weather and nearby public event lookup."
      ].join("\n")
    });

    const fallbackQuery = [object.city, object.country].filter(Boolean).join(", ");
    const query = object.weatherQuery || object.eventsQuery || fallbackQuery;

    return query ? { query, source: "ai" } : undefined;
  } catch (error) {
    console.error("Location normalization failed", error);
    return undefined;
  }
}

async function normalizeLocationForProviders(kind: string, title: string, location: string): Promise<LocationLookup | undefined> {
  const deterministic = await deterministicLocationLookup(kind, location);
  const ai = await aiLocationLookup(kind, title, location);
  if (ai?.query) {
    const localPlace = localCoordinates(ai.query);
    if (localPlace) {
      return { ...ai, coordinates: localPlace };
    }
  }

  const prefersMajorCity = kind === "hotel" || kind === "event";
  if (prefersMajorCity) {
    return majorProviderCityLookup(deterministic?.query ?? location) ?? ai ?? deterministic;
  }

  return deterministic?.coordinates ? deterministic : ai ?? deterministic;
}

const knownCoordinates: Record<string, Coordinates> = {
  bio: { lat: 43.3011, lon: -2.9106, name: "Bilbao Airport", country: "ES" },
  bilbao: { lat: 43.263, lon: -2.935, name: "Bilbao", country: "ES" },
  zrh: { lat: 47.4581, lon: 8.5555, name: "Zurich Airport", country: "CH" },
  zurich: { lat: 47.3769, lon: 8.5417, name: "Zurich", country: "CH" },
  "bad ragaz": { lat: 47.006, lon: 9.5027, name: "Bad Ragaz", country: "CH" },
  london: { lat: 51.5072, lon: -0.1276, name: "London", country: "GB" }
};

const majorProviderCityAliases: Record<string, Coordinates> = {
  getxo: knownCoordinates.bilbao,
  algorta: knownCoordinates.bilbao
};

function majorProviderCityLookup(location: string): LocationLookup | undefined {
  const key = asciiKey(location);
  for (const [alias, coordinates] of Object.entries(majorProviderCityAliases)) {
    if (key.includes(alias)) {
      return { query: `${coordinates.name}, ${coordinates.country}`, coordinates, source: "deterministic" };
    }
  }
  return undefined;
}

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

function eventSearchWindow(kind: string, startsAt?: string | number | null, endsAt?: string | number | null) {
  const oneDay = 1000 * 60 * 60 * 24;
  const now = new Date();
  const parsedStart = parseRequestDate(startsAt);
  const parsedEnd = parseRequestDate(endsAt);
  const lowerKind = kind.toLowerCase();

  if (lowerKind === "flight" || lowerKind === "transit") {
    const arrival = parsedEnd ?? parsedStart ?? now;
    const start = arrival < now ? now : arrival;
    return {
      start,
      end: new Date(start.getTime() + oneDay * 7)
    };
  }

  const start = parsedStart ?? now;
  const minimumDays = lowerKind === "event" ? 2 : 7;
  const fallbackEnd = new Date(start.getTime() + oneDay * minimumDays);
  const requestedEnd = parsedEnd && parsedEnd > start ? parsedEnd : fallbackEnd;
  const effectiveStart = start < now ? now : start;

  return {
    start: effectiveStart,
    end: requestedEnd < effectiveStart ? new Date(effectiveStart.getTime() + oneDay * minimumDays) : requestedEnd
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

function weatherGeocodeCandidates(location: string) {
  const candidates = [location.trim()];
  const parts = location.split(",").map((part) => part.trim()).filter(Boolean);
  if (parts.length > 2) {
    candidates.push(parts.slice(-2).join(", "));
  }

  return [...new Set(candidates.filter(Boolean))];
}

async function geocode(locationLookup: string | LocationLookup) {
  let location = typeof locationLookup === "string" ? locationLookup : locationLookup.query;
  if (typeof locationLookup !== "string" && locationLookup.coordinates) {
    return { place: locationLookup.coordinates };
  }

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

  for (const candidate of weatherGeocodeCandidates(location)) {
    const url = new URL("https://api.openweathermap.org/geo/1.0/direct");
    url.searchParams.set("q", candidate);
    url.searchParams.set("limit", "1");
    url.searchParams.set("appid", apiKey);

    const response = await fetch(url);
    if (!response.ok) {
      return { error: "provider_error", status: response.status } satisfies GeocodeResult;
    }

    const places = (await response.json()) as Array<{ lat: number; lon: number; name?: string; country?: string }>;
    const place = places[0];
    if (place) {
      return { place };
    }
  }

  return { error: "not_found" } satisfies GeocodeResult;
}

async function weatherCard(location: string | LocationLookup | undefined, isRussian = false): Promise<EnrichmentCard> {
  const apiKey = process.env.OPENWEATHER_API_KEY;
  if (!apiKey) {
    return {
      title: isRussian ? "Погода" : "Weather",
      value: isRussian ? "Не подключено" : "Not connected",
      detail: isRussian ? "Добавьте OPENWEATHER_API_KEY в Vercel, чтобы показывать живую погоду." : "Set OPENWEATHER_API_KEY on Vercel to show live weather.",
      kind: "weather"
    };
  }

  if (!location) {
    return {
      title: isRussian ? "Погода" : "Weather",
      value: isRussian ? "Нужно место" : "Location needed",
      detail: isRussian ? "Добавьте более точный город, аэропорт, отель, адрес места или ссылку на карту." : "Add a clearer city, airport, hotel, venue address, or map link.",
      kind: "weather"
    };
  }

  const geocoded = await geocode(location);
  if ("error" in geocoded) {
    if (geocoded.error === "provider_error") {
      return {
        title: isRussian ? "Погода" : "Weather",
        value: isRussian ? "Недоступно" : "Unavailable",
        detail: isRussian ? `Геокодинг OpenWeather вернул ${geocoded.status}.` : `OpenWeather geocoding returned ${geocoded.status}.`,
        kind: "weather"
      };
    }

    return {
      title: isRussian ? "Погода" : "Weather",
      value: isRussian ? "Нужно место" : "Location needed",
      detail: (typeof location === "string" ? location : location.query)
        ? (isRussian ? `OpenWeather не нашёл "${typeof location === "string" ? location : location.query}".` : `OpenWeather could not find "${typeof location === "string" ? location : location.query}".`)
        : (isRussian ? "Добавьте более точный город, аэропорт, отель или адрес места." : "Add a clearer city, airport, hotel, or venue address."),
      kind: "weather"
    };
  }

  const place = geocoded.place;

  const url = new URL("https://api.openweathermap.org/data/4.0/onecall/current");
  url.searchParams.set("lat", String(place.lat));
  url.searchParams.set("lon", String(place.lon));
  url.searchParams.set("units", "metric");
  url.searchParams.set("lang", isRussian ? "ru" : "en");
  url.searchParams.set("appid", apiKey);

  const response = await fetch(url);
  if (!response.ok) {
    return {
      title: isRussian ? "Погода" : "Weather",
      value: isRussian ? "Недоступно" : "Unavailable",
      detail: isRussian ? `OpenWeather вернул ${response.status}.` : `OpenWeather returned ${response.status}.`,
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
  const alertIDs = current?.alerts ?? [];
  const alerts = await Promise.all(alertIDs.slice(0, 5).map(async (id) => {
    try {
      return await weatherAlertDetails(id);
    } catch (error) {
      console.error(`OpenWeather alert ${id} lookup failed`, error);
      return undefined;
    }
  }));
  const alertSummaries = alerts.flatMap((alert) => {
    if (!alert) return [];

    const description = alert.description
      .replace(/\s+/g, " ")
      .trim();
    const distinctDescription = description.toLowerCase() === alert.event.toLowerCase()
      ? ""
      : description;
    const compactDescription = distinctDescription.length > 180
      ? `${distinctDescription.slice(0, 177)}...`
      : distinctDescription;
    const basis = isRussian
      ? `Источник: ${alert.source}. Предупреждение относится к району или периоду, а не обязательно к погоде прямо сейчас.`
      : `Source: ${alert.source}. The advisory applies to an area or time window, not necessarily to conditions at this exact moment.`;
    return [[alert.event, compactDescription, basis].filter(Boolean).join(" · ")];
  });
  const alertCount = alertIDs.length;

  return {
    title: isRussian ? "Погода" : "Weather",
    value: temp == null ? (isRussian ? "Прогноз готов" : "Forecast ready") : `${Math.round(temp)} C`,
    detail: [
      description,
      alertCount > 0
        ? (alertSummaries.join("; ") || (isRussian
          ? `${alertCount} погодных предупреждений от OpenWeather. Они могут относиться к более широкой территории или другому времени.`
          : `${alertCount} OpenWeather alert${alertCount === 1 ? "" : "s"}. They may apply to a wider area or a different time window.`))
        : undefined
    ].filter(Boolean).join(" · "),
    kind: alertCount > 0 ? "warning" : "weather"
  };
}

async function eventsContext(location: string | LocationLookup | undefined, kind: string, startsAt?: string | number | null, endsAt?: string | number | null, isRussian = false): Promise<{ card: EnrichmentCard; events: NearbyEvent[] }> {
  const apiKey = ticketmasterApiKey();
  if (!apiKey) {
    return { card: {
        title: isRussian ? "События рядом" : "Nearby events",
        value: isRussian ? "Не подключено" : "Not connected",
        detail: isRussian ? "Добавьте TICKETMASTER_API_KEY или TICKETMASTER_CONSUMER_KEY в Vercel для контекста местных событий." : "Set TICKETMASTER_API_KEY or TICKETMASTER_CONSUMER_KEY on Vercel for local event context.",
        kind: "events"
      }, events: [] };
  }

  const url = new URL("https://app.ticketmaster.com/discovery/v2/events.json");
  const window = eventSearchWindow(kind, startsAt, endsAt);
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
      url.searchParams.set("city", cityFromLocation(typeof location === "string" ? location : location.query));
    }
  }

  const response = await fetch(url);
  if (!response.ok) {
    return { card: {
        title: isRussian ? "События рядом" : "Nearby events",
        value: isRussian ? "Недоступно" : "Unavailable",
        detail: isRussian ? `Ticketmaster вернул ${response.status}.` : `Ticketmaster returned ${response.status}.`,
        kind: "events"
      }, events: [] };
  }

  const data = await response.json() as { page?: { totalElements?: number }; _embedded?: { events?: TicketmasterEvent[] } };
  const events = data._embedded?.events ?? [];
  const firstEvent = events[0];
  const eventNames = events.map((event) => event.name).filter(Boolean).slice(0, 2);
  const nearbyEvents = events.flatMap((event): NearbyEvent[] => {
    const name = clean(event.name);
    if (!name) return [];
    const venue = event._embedded?.venues?.[0];
    return [{
      id: clean(event.id) || clean(event.url) || `${name}-${event.dates?.start?.localDate ?? ""}-${event.dates?.start?.localTime ?? ""}`,
      name,
      url: clean(event.url) || undefined,
      localDate: clean(event.dates?.start?.localDate) || undefined,
      localTime: clean(event.dates?.start?.localTime) || undefined,
      venue: clean(venue?.name) || undefined,
      city: clean(venue?.city?.name) || undefined
    }];
  });

  return { card: {
      title: isRussian ? "События рядом" : "Nearby events",
      value: isRussian ? `Найдено: ${data.page?.totalElements ?? 0}` : `${data.page?.totalElements ?? 0} found`,
      detail: firstEvent ? eventDetail(firstEvent) : eventNames?.length ? eventNames.join(" · ") : (isRussian ? "Крупных публичных событий рядом не найдено." : "No major public events found nearby."),
      actionURL: firstEvent?.url,
      kind: "events"
    }, events: nearbyEvents };
}

function compactDate(value?: string | number | null) {
  const date = parseRequestDate(value);
  return date ? date.toISOString().slice(0, 10) : undefined;
}

function compactTime(value?: string) {
  if (!value) {
    return undefined;
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  }).format(date);
}

function minutesBetweenIso(later?: string, earlier?: string) {
  if (!later || !earlier) {
    return undefined;
  }

  const laterDate = new Date(later);
  const earlierDate = new Date(earlier);
  if (Number.isNaN(laterDate.getTime()) || Number.isNaN(earlierDate.getTime())) {
    return undefined;
  }

  return Math.round((laterDate.getTime() - earlierDate.getTime()) / 60000);
}

function compactDuration(minutes?: number) {
  if (minutes == null) {
    return undefined;
  }

  const abs = Math.abs(minutes);
  const hours = Math.floor(abs / 60);
  const mins = abs % 60;
  const value = [
    hours ? `${hours}h` : undefined,
    mins ? `${mins}m` : undefined
  ].filter(Boolean).join(" ") || "0m";

  return minutes < 0 ? `-${value}` : value;
}

function compactRoute(origin?: string, destination?: string) {
  return [origin, destination].filter(Boolean).join(" -> ");
}

function compactPercent(value?: number) {
  return value == null ? undefined : `${Math.round(value * 100)}%`;
}

function cleanMarkdownLine(value: string) {
  return value.replace(/\s+/g, " ").trim();
}

function cleanBriefText(value: string) {
  return value
    .replace(/\s+/g, " ")
    .replace(/([a-z0-9)])([A-Z][A-Za-z /-]{1,24}:)/g, "$1\n$2")
    .replace(/([.!?])([A-Z])/g, "$1\n$2")
    .trim();
}

function mapsSearchURL(query: string) {
  if (!query) {
    return undefined;
  }

  const url = new URL("https://www.google.com/maps/search/");
  url.searchParams.set("api", "1");
  url.searchParams.set("query", query);
  return url.href;
}

function cardLine(card: EnrichmentCard) {
  return cleanMarkdownLine([card.value, card.detail].filter(Boolean).join(" - "));
}

function bestCard(cards: EnrichmentCard[], kind: EnrichmentCard["kind"]) {
  return cards.find((card) => card.kind === kind);
}

function routeTitleForKind(kind: string, isRussian = false) {
  switch (kind) {
  case "flight":
    return isRussian ? "Маршрут в аэропорт" : "Route to airport";
  case "hotel":
    return isRussian ? "Маршрут прибытия" : "Arrival route";
  case "event":
    return isRussian ? "Маршрут к месту события" : "Route to venue";
  case "transit":
    return isRussian ? "Участок поездки" : "Travel leg";
  default:
    return isRussian ? "Как добраться" : "Getting there";
  }
}

function deterministicRouteLeg(kind: string, title: string, location: string, isRussian = false): TravelRouteLeg[] {
  if (!location) {
    return [];
  }

  const destination = placeForExternalLookup(kind, location) || location;
  const guidance = isRussian
    ? (kind === "flight"
      ? "Запланируйте путь до аэропорта с запасом на багаж, контроль безопасности и смену выхода."
      : kind === "event"
        ? "Проверьте маршрут до выхода и оставьте небольшой запас на вход, билеты и поиск нужной двери."
        : kind === "hotel"
          ? "Сделайте прибытие предсказуемым: маршрут, окно заселения и ближайшие полезные места."
          : "Держите маршрут, запас времени и запасной вариант под рукой до начала этого участка.")
    : (kind === "flight"
      ? "Plan the door-to-airport journey with enough buffer for bags, security, and gate changes."
      : kind === "event"
        ? "Plan the route before you leave, then keep a small buffer for entry, tickets, and finding the right door."
        : kind === "hotel"
          ? "Use this leg to make arrival feel automatic: route, check-in window, and nearby essentials."
          : "Keep the route, buffer, and fallback option ready before this leg starts.");

  return [{
    title: routeTitleForKind(kind, isRussian),
    destination,
    guidance,
    bufferMinutes: kind === "flight" ? 120 : kind === "event" ? 20 : 15,
    mapURL: mapsSearchURL(destination || title)
  }];
}

function deterministicActions(kind: string, title: string, location: string, cards: EnrichmentCard[], isRussian = false): TravelAction[] {
  const actions: TravelAction[] = [];
  const warning = cards.find((card) => card.kind === "warning");
  const maps = bestCard(cards, "maps");
  const weather = cards.find((card) => card.kind === "weather" || card.title.toLowerCase().includes("weather"));
  const flight = cards.find((card) => card.kind === "flight");
  const event = cards.find((card) => card.kind === "events" && card.actionURL);

  if (warning) {
    actions.push({
      title: isRussian ? "Проверьте риск" : "Review the risk",
      detail: cardLine(warning),
      priority: "now",
      kind: warning.title.toLowerCase().includes("flight") ? "flight" : "safety",
      actionURL: warning.actionURL
    });
  }

  if (location) {
    actions.push({
      title: kind === "flight"
        ? (isRussian ? "Проверьте маршрут в аэропорт" : "Check the airport route")
        : (isRussian ? "Посмотрите маршрут" : "Preview the route"),
      detail: maps?.detail || (isRussian ? `Откройте маршрутный контекст для ${location}.` : `Open the route context for ${location}.`),
      priority: kind === "flight" ? "soon" : "later",
      kind: "route",
      actionURL: mapsSearchURL(location)
    });
  }

  if (flight && kind === "flight") {
    actions.push({
      title: isRussian ? "Держите статус рейса под рукой" : "Keep flight status visible",
      detail: cardLine(flight),
      priority: "soon",
      kind: "flight",
      actionURL: flight.actionURL
    });
  }

  if (weather) {
    actions.push({
      title: isRussian ? "Подготовьтесь к погоде" : "Prepare for the weather",
      detail: cardLine(weather) || (isRussian ? "Проверьте прогноз перед выходом." : "Check the forecast before leaving."),
      priority: warning ? "now" : "soon",
      kind: "weather",
      actionURL: weather.actionURL
    });
  }

  if (event) {
    actions.push({
      title: isRussian ? "Посмотрите, что есть рядом" : "Look at what is nearby",
      detail: cardLine(event),
      priority: "later",
      kind: "event",
      actionURL: event.actionURL
    });
  }

  actions.push({
    title: isRussian ? "Держите детали бронирования под рукой" : "Keep booking details handy",
    detail: title
      ? (isRussian ? `Используйте "${title}" как источник истины, если данные провайдера изменятся.` : `Use "${title}" as the source of truth if provider data changes.`)
      : (isRussian ? "Добавьте более понятный заголовок, чтобы Voya могла оценить этот момент." : "Add a clearer title so Voya can reason about this moment."),
    priority: "later",
    kind: "booking"
  });

  return actions.slice(0, 5);
}

function deterministicSections(kind: string, title: string, location: string, cards: EnrichmentCard[], warnings: string[], isRussian = false): TravelBriefSection[] {
  const weather = cards.find((card) => card.kind === "weather" || card.title.toLowerCase().includes("weather"));
  const flight = cards.find((card) => card.kind === "flight");
  const events = cards.find((card) => card.kind === "events");
  const maps = bestCard(cards, "maps");

  const sections: TravelBriefSection[] = [{
    title: isRussian ? "Что значит этот момент" : "What this moment means",
    body: title
      ? (isRussian ? `${title} - это не просто пункт маршрута: здесь сходятся время, место, маршрут, погода и детали бронирования.` : `${title} is not just an itinerary item; it combines timing, place, route, weather, and booking context.`)
      : (isRussian ? "Добавьте понятный заголовок, и Voya превратит это в практичный момент поездки." : "Add a clear title and Voya can turn this into a practical travel moment."),
    kind: "overview"
  }];

  if (maps || location) {
    sections.push({
      title: isRussian ? "Как добраться" : "Getting there",
      body: maps?.detail || location || (isRussian ? "Добавьте место, аэропорт, отель, станцию или ссылку на карту, чтобы включить подсказки по маршруту." : "Add a venue, airport, hotel, station, or map link to unlock route guidance."),
      kind: "route"
    });
  }

  if (flight && kind === "flight") {
    sections.push({
      title: isRussian ? "Сигналы по рейсу" : "Flight intelligence",
      body: cardLine(flight),
      kind: flight.kind === "warning" ? "risk" : "flight"
    });
  }

  if (weather) {
    sections.push({
      title: isRussian ? "Погода как решение" : "Weather as a decision",
      body: cardLine(weather) || (isRussian ? "Прогноз должен превращаться в практичный совет: что надеть, что взять и когда выходить." : "Forecast data should become practical advice: what to wear, what to pack, and when to leave."),
      kind: weather.kind === "warning" ? "risk" : "weather"
    });
  }

  if (events) {
    sections.push({
      title: kind === "event"
        ? (isRussian ? "Контекст события" : "Event context")
        : (isRussian ? "Возможности рядом" : "Nearby opportunities"),
      body: cardLine(events),
      kind: "event"
    });
  }

  if (warnings.length > 0) {
    sections.push({
      title: isRussian ? "Риски, которые нужно видеть" : "Risks to keep visible",
      body: warnings.join(" "),
      kind: "risk"
    });
  }

  sections.push({
    title: isRussian ? "Позиция ассистента" : "Assistant stance",
    body: isRussian
      ? "Voya должна переводить данные провайдеров в решения: время выхода, запас, запасной маршрут, подготовку к погоде и то, что требует внимания сейчас."
      : "Voya should keep translating provider data into decisions: leave time, buffer, fallback route, weather prep, and what deserves attention now.",
    kind: "action"
  });

  return sections.slice(0, 7);
}

function markdownFromSections(summary: string, sections: TravelBriefSection[], actions: TravelAction[], routeLegs: TravelRouteLeg[], isRussian = false) {
  const sectionLines = sections.map((section) => [
    `### ${section.title}`,
    cleanBriefText(section.body)
  ].join("\n")).join("\n\n");
  const routeLines = routeLegs.length
    ? [
      isRussian ? "### Участки пути" : "### Journey legs",
      ...routeLegs.map((leg) => `- **${leg.title}**: ${leg.guidance}${leg.bufferMinutes ? (isRussian ? ` Держите запас около ${leg.bufferMinutes} мин.` : ` Keep ~${leg.bufferMinutes} min buffer.`) : ""}`)
    ].join("\n")
    : "";
  const actionLines = actions.length
    ? [
      isRussian ? "### Следующие действия" : "### Next actions",
      ...actions.map((action) => `- **${action.title}**: ${action.detail}`)
    ].join("\n")
    : "";

  return [isRussian ? "## Краткая сводка поездки" : "## Travel brief", summary, sectionLines, routeLines, actionLines].filter(Boolean).join("\n\n");
}

async function aiBrief(kind: string, title: string, location: string, status: string, cards: EnrichmentCard[], warnings: string[], languageInstruction: string, locale: string): Promise<TravelBriefGenerated | undefined> {
  if (!process.env.OPENAI_API_KEY) {
    return undefined;
  }

  try {
    const { object }: { object: TravelBriefGenerated } = await generateObject({
      model: openai(briefModelName()),
      schema: travelBriefSchema,
      schemaName: "TravelAssistantBrief",
      schemaDescription: "Human travel assistant brief generated from trusted provider facts.",
      system: [
        "You are Voya, a practical travel assistant.",
        "Use only the provided facts. Do not invent performers, seating, gates, routes, prices, opening hours, or precise transit times.",
        "Be human and decision-oriented: translate facts into what the traveler should know or do.",
        "Prefer short sections, concrete next actions, route guidance, weather decisions, and visible risks.",
        "Do not pack labeled fields into one run-on paragraph. Use natural sentences with spaces between every idea.",
        "Keep each section body to 1-3 readable sentences. Put dense labels into separate sections instead of inline.",
        "If a fact is missing, say what would unlock it instead of pretending.",
        languageInstruction,
        "Return structured JSON only."
      ].join(" "),
      prompt: [
        `App locale: ${locale}`,
        languageInstruction,
        "",
        `Kind: ${kind || "unknown"}`,
        `Title: ${title || "unknown"}`,
        `Location: ${location || "unknown"}`,
        `Status: ${status || "unknown"}`,
        `Warnings: ${warnings.length ? warnings.join(" | ") : "none"}`,
        "",
        "Trusted provider facts:",
        JSON.stringify(cards, null, 2),
        "",
        "Create a formatted travel brief for the detail screen."
      ].join("\n")
    });

    return object;
  } catch (error) {
    console.error("Travel brief generation failed", error);
    return undefined;
  }
}

async function buildTravelBrief(kind: string, title: string, location: string, status: string, cards: EnrichmentCard[], warnings: string[], locale: string, languageCode: string, languageName: string): Promise<Pick<EnrichmentResponse, "summary" | "briefMarkdown" | "sections" | "actions" | "routeLegs" | "imageURLs">> {
  const isRussian = languageCode.toLowerCase().startsWith("ru");
  const routeLegs = deterministicRouteLeg(kind, title, location, isRussian);
  const actions = deterministicActions(kind, title, location, cards, isRussian);
  const sections = deterministicSections(kind, title, location, cards, warnings, isRussian);
  const languageInstruction = responseLanguageInstruction(languageCode, languageName, locale);
  const summary = isRussian
    ? (title
      ? `Voya следит за ${title} как за моментом поездки, а не просто бронированием.`
      : "Добавьте больше деталей, и Voya превратит это в практичный момент поездки.")
    : (title
      ? `Voya is watching ${title} as a travel moment, not just a booking.`
      : "Add more details and Voya will turn this into a practical travel moment.");
  const fallback = {
    summary,
    briefMarkdown: markdownFromSections(summary, sections, actions, routeLegs, isRussian),
    sections,
    actions,
    routeLegs,
    // Action URLs often point to maps or ticket pages, not image assets. Keep this
    // empty until a trusted image provider supplies verifiable image URLs.
    imageURLs: []
  };

  const generated = await aiBrief(kind, title, location, status, cards, warnings, languageInstruction, locale);
  if (!generated) {
    return fallback;
  }

  const generatedActions = generated.actions.map((action) => ({ ...action, actionURL: action.actionURL ?? undefined }));
  const generatedRouteLegs = generated.routeLegs.map((leg) => ({
    ...leg,
    origin: leg.origin ?? undefined,
    destination: leg.destination ?? undefined,
    guidance: cleanBriefText(leg.guidance),
    bufferMinutes: leg.bufferMinutes ?? undefined,
    mapURL: leg.mapURL ?? undefined
  }));

  return {
    summary: generated.summary ? cleanBriefText(generated.summary) : fallback.summary,
    briefMarkdown: generated.briefMarkdown ? cleanBriefText(generated.briefMarkdown) : fallback.briefMarkdown,
    sections: generated.sections.length
      ? generated.sections.map((section) => ({ ...section, body: cleanBriefText(section.body) }))
      : fallback.sections,
    actions: generatedActions.length
      ? generatedActions.map((action) => ({ ...action, detail: cleanBriefText(action.detail) }))
      : fallback.actions,
    routeLegs: generatedRouteLegs.length ? generatedRouteLegs : fallback.routeLegs,
    imageURLs: []
  };
}

function flightLegLookup(
  flightNumber: string,
  index: number,
  total: number,
  date: string | undefined,
  originAirport: string | undefined,
  destinationAirport: string | undefined
) {
  if (total <= 1) {
    return {
      flightNumber,
      date,
      originAirport,
      destinationAirport
    };
  }

  return {
    flightNumber,
    date,
    originAirport: index === 0 ? originAirport : undefined,
    destinationAirport: index === total - 1 ? destinationAirport : undefined
  };
}

type FlightAttempt = Awaited<ReturnType<typeof getFlightStatus>> extends infer Response
  ? { flightNumber: string; response: Response }
  : never;

function departureTime(attempt: FlightAttempt) {
  return attempt.response.snapshot?.estimatedDepartureAt
    ?? attempt.response.snapshot?.scheduledDepartureAt
    ?? attempt.response.schedule.estimatedDepartureAt
    ?? attempt.response.schedule.scheduledDepartureAt;
}

function arrivalTime(attempt: FlightAttempt) {
  return attempt.response.snapshot?.estimatedArrivalAt
    ?? attempt.response.snapshot?.scheduledArrivalAt
    ?? attempt.response.schedule.estimatedArrivalAt
    ?? attempt.response.schedule.scheduledArrivalAt;
}

function flightDuration(attempt: FlightAttempt) {
  return compactDuration(minutesBetweenIso(arrivalTime(attempt), departureTime(attempt)));
}

function flightLegCards(attempts: FlightAttempt[], isRussian = false) {
  const cards: EnrichmentCard[] = [];

  attempts.forEach((attempt, index) => {
    const snapshot = attempt.response.snapshot;
    if (!snapshot) {
      cards.push({
        title: isRussian ? `Рейс ${attempt.flightNumber}` : `Flight ${attempt.flightNumber}`,
        value: isRussian ? "Не подтверждено" : "Not validated",
        detail: attempt.response.validation.reasons[0] ?? (isRussian ? "FlightAware не вернул надежное совпадение для этого сегмента." : "FlightAware did not return a trustworthy match for this segment."),
        kind: "warning"
      });
      return;
    }

    const depart = departureTime(attempt);
    const arrive = arrivalTime(attempt);
    cards.push({
      title: attempts.length > 1 ? (isRussian ? `Рейс ${index + 1}` : `Flight ${index + 1}`) : (isRussian ? "Рейс" : "Flight"),
      value: `${attempt.flightNumber} · ${compactRoute(snapshot.originAirport, snapshot.destinationAirport) || (isRussian ? "Маршрут ожидается" : "Route pending")}`,
      detail: [
        [compactTime(depart), compactTime(arrive)].filter(Boolean).join(" -> "),
        flightDuration(attempt),
        snapshot.dataMode === "published_schedule" ? "Schedule" : snapshot.providerStatus ?? snapshot.status
      ].filter(Boolean).join(" · "),
      kind: "flight"
    });
  });

  return cards;
}

function connectionCards(attempts: FlightAttempt[], isRussian = false) {
  if (attempts.length < 2) {
    return [];
  }

  const validated = attempts.filter((attempt) => attempt.response.snapshot);
  const ordered = [...validated].sort((a, b) => {
    const left = departureTime(a);
    const right = departureTime(b);
    return (left ? new Date(left).getTime() : 0) - (right ? new Date(right).getTime() : 0);
  });
  const connectionDetails: string[] = [];

  for (let index = 0; index < ordered.length - 1; index += 1) {
    const current = ordered[index];
    const next = ordered[index + 1];
    const layover = compactDuration(minutesBetweenIso(departureTime(next), arrivalTime(current)));
    const airport = current.response.snapshot?.destinationAirport ?? next.response.snapshot?.originAirport;
    if (layover) {
      connectionDetails.push([airport, layover].filter(Boolean).join(" · "));
    }
  }

  return [{
    title: isRussian ? "Стыковка" : "Connection",
    value: isRussian ? `${validated.length}/${attempts.length} сегментов` : `${validated.length}/${attempts.length} legs`,
    detail: connectionDetails.length ? connectionDetails.join(" · ") : (isRussian ? `Проверены: ${attempts.map((attempt) => attempt.flightNumber).join(", ")}.` : `Tried ${attempts.map((attempt) => attempt.flightNumber).join(", ")}.`),
    kind: validated.length === attempts.length ? "flight" : "warning"
  } satisfies EnrichmentCard];
}

function planeContextCard(response: FlightAttempt["response"], isRussian = false): EnrichmentCard {
  const plane = response.plane;
  const position = plane.position;
  const positionText = position
    ? `${position.lat.toFixed(2)}, ${position.lon.toFixed(2)}`
    : undefined;
  const sourceTime = compactTime(plane.sourceUpdatedAt);
  const detailParts = [
    plane.detail,
    positionText ? (isRussian ? `Позиция ${positionText}` : `Position ${positionText}`) : undefined,
    sourceTime ? (isRussian ? `Обновлено ${sourceTime}` : `Updated ${sourceTime}`) : undefined
  ].filter(Boolean);

  return {
    title: isRussian ? "Где самолет" : "Aircraft location",
    value: plane.headline,
    detail: detailParts.join(" · ") || undefined,
    kind: "flight"
  };
}

async function flightCards(title: string, location: string, startsAt?: string | number | null, isRussian = false): Promise<EnrichmentCard[]> {
  const flightNumbers = allFlightNumbers(`${title} ${location}`);
  if (flightNumbers.length === 0) {
    return [{
      title: isRussian ? "Рейс" : "Flight",
      value: isRussian ? "Нет номера рейса" : "No flight number",
      detail: isRussian ? "Добавьте номер рейса, например BA2490, чтобы включить живой статус." : "Add a flight number such as BA2490 to enable live status.",
      kind: "flight"
    }];
  }

  const airportCodes = airportCodesFromText(location);
  const originAirport = airportCodes[0];
  const destinationAirport = airportCodes.length > 1 ? airportCodes.at(-1) : undefined;
  const date = compactDate(startsAt);
  const attempts = await Promise.all(flightNumbers.map(async (flightNumber, index) => ({
    flightNumber,
    response: await getFlightStatus(flightLegLookup(
      flightNumber,
      index,
      flightNumbers.length,
      date,
      originAirport,
      destinationAirport
    ))
  })));
  const selected = attempts.find((attempt) => attempt.response.snapshot) ?? attempts[0];
  const { flightNumber, response } = selected;

  if (!response.snapshot) {
    return [{
      title: isRussian ? "Рейс" : "Flight",
      value: flightNumber,
      detail: [
        response.validation.reasons[0] ?? (isRussian ? "Живой статус рейса недоступен." : "Live flight status is unavailable."),
        flightNumbers.length > 1 ? (isRussian ? `Проверены: ${flightNumbers.join(", ")}.` : `Tried ${flightNumbers.join(", ")}.`) : undefined
      ].filter(Boolean).join(" "),
      kind: "flight"
    }];
  }

  const snapshot = response.snapshot;
  const gateParts = [
    snapshot.departureTerminal ? `T${snapshot.departureTerminal}` : undefined,
    snapshot.departureGate ? `Gate ${snapshot.departureGate}` : undefined
  ].filter(Boolean);
  const aircraftParts = [
    snapshot.aircraftRegistration,
    snapshot.aircraftType,
    snapshot.position ? `${snapshot.position.lat.toFixed(2)}, ${snapshot.position.lon.toFixed(2)}` : undefined
  ].filter(Boolean);
  const disruption = response.intelligence.disruptions[0];
  const history = response.intelligence.history;
  const originWeather = response.intelligence.weather.origin;
  const destinationWeather = response.intelligence.weather.destination;
  const route = response.intelligence.route;
  const delayCard: EnrichmentCard = {
    title: isRussian ? "Задержка" : "Delay",
    value: response.delayStats.headline,
    detail: response.delayStats.onTimeProbability == null
      ? undefined
      : (isRussian ? `${Math.round(response.delayStats.onTimeProbability * 100)}% оценка Voya для вылета вовремя` : `${Math.round(response.delayStats.onTimeProbability * 100)}% Voya on-time estimate`),
    kind: (snapshot.delayMinutes ?? 0) >= 15 ? "warning" : "flight"
  };

  return [...flightLegCards(attempts, isRussian), ...connectionCards(attempts, isRussian), delayCard, {
    title: isRussian ? "Выход" : "Gate",
    value: gateParts.length ? gateParts.join(" · ") : (isRussian ? "Не опубликовано" : "Not posted"),
    detail: response.gate.baggageClaim ? `Baggage ${response.gate.baggageClaim}` : response.gate.guidance[1],
    kind: "flight"
  }, {
    title: isRussian ? "Время" : "Times",
    value: [
      compactTime(response.schedule.estimatedDepartureAt ?? response.schedule.scheduledDepartureAt),
      compactTime(response.schedule.estimatedArrivalAt ?? response.schedule.scheduledArrivalAt)
    ].filter(Boolean).join(" -> ") || (isRussian ? "Недоступно" : "Not available"),
    detail: response.schedule.actualDepartureAt
      ? `Departed ${compactTime(response.schedule.actualDepartureAt)}`
      : snapshot.dataMode === "published_schedule"
        ? (isRussian ? "Опубликованное расписание авиакомпании. Живое время у выхода появится ближе к вылету." : "Published airline schedule. Live gate times open closer to departure.")
        : (isRussian ? "Используются плановые, расчетные и фактические времена у выхода от FlightAware." : "Uses FlightAware scheduled, estimated, and actual gate times."),
    kind: "flight"
  }, {
    title: isRussian ? "Надежность" : "Reliability",
    value: history?.sampleSize
      ? `${compactPercent(history.delayed15Rate) ?? "0%"} delayed`
      : (isRussian ? "Собираем" : "Collecting"),
    detail: history?.averageArrivalDelayMinutes == null
      ? (isRussian ? "История может требовать подключенный тариф FlightAware." : "History may require the enabled FlightAware tier.")
      : (isRussian ? `${history.sampleSize} недавних рейсов · средняя задержка прибытия ${Math.round(history.averageArrivalDelayMinutes)} мин` : `${history.sampleSize} recent flights · avg arrival delay ${Math.round(history.averageArrivalDelayMinutes)} min`),
    kind: (history?.delayed15Rate ?? 0) >= 0.3 ? "warning" : "flight"
  }, {
    title: isRussian ? "Сбои" : "Disruptions",
    value: disruption?.total
      ? `${compactPercent(disruption.delayRate) ?? "0%"} delayed`
      : (isRussian ? "Нет сигнала" : "No signal"),
    detail: disruption
      ? `${disruption.entityName ?? disruption.entityId ?? disruption.entityType} · ${disruption.delays ?? 0} delayed · ${disruption.cancellations ?? 0} cancelled`
      : (isRussian ? "FlightAware не вернул счетчик сбоев." : "No FlightAware disruption count returned."),
    kind: (disruption?.delayRate ?? 0) >= 0.25 ? "warning" : "flight"
  }, {
    title: isRussian ? "Маршрут" : "Route",
    value: route?.routeDistance ?? (isRussian ? "Не подан" : "Not filed"),
    detail: route?.route
      ? `${route.route.slice(0, 80)}${route.route.length > 80 ? "..." : ""}`
      : response.intelligence.mode === "published_schedule"
        ? (isRussian ? "Типовые поданные маршруты появляются ближе к операции или когда доступна история маршрутов." : "Typical filed routes appear closer to operations or when route history is available.")
        : undefined,
    kind: "flight"
  }, {
    title: isRussian ? "Погода в аэропорту" : "Airport weather",
    value: originWeather?.temperatureC == null ? (isRussian ? "Прогноз" : "Forecast") : `${originWeather.temperatureC} C`,
    detail: [
      originWeather?.airport,
      originWeather?.summary ?? originWeather?.forecastSummary,
      destinationWeather?.airport ? (isRussian ? `Прибытие ${destinationWeather.airport}` : `Arrive ${destinationWeather.airport}`) : undefined
    ].filter(Boolean).join(" · "),
    kind: "weather"
  }, {
    title: isRussian ? "Оповещения" : "Alerts",
    value: response.alerting.supported ? (isRussian ? "Готово" : "Ready") : (isRussian ? "Недоступно" : "Unavailable"),
    detail: response.alerting.supported ? (isRussian ? "Оповещения FlightAware могут передавать обновления по выходу, задержке, отмене, диверсии, вылету и прибытию." : "FlightAware alerts can feed gate, delay, cancellation, diversion, departure, and arrival updates.") : undefined,
    kind: "flight"
  }, planeContextCard(response, isRussian), {
    title: isRussian ? "Самолет" : "Aircraft",
    value: aircraftParts.length ? aircraftParts.join(" · ") : (isRussian ? "Недоступно" : "Not available"),
    detail: snapshot.position?.updatedAt ? (isRussian ? `Живая позиция обновлена ${compactTime(snapshot.position.updatedAt)}` : `Live position updated ${compactTime(snapshot.position.updatedAt)}`) : snapshot.airlineCode,
    kind: "flight"
  }];
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!await protectPublicEndpoint(req, res, { name: "enrich", hourlyIPLimit: 240, hourlyInstallLimit: 80, maxBodyBytes: 32_000 })) return;

  const body = req.body as EnrichmentRequest;
  const kind = clean(body.kind).toLowerCase();
  const title = clean(body.title);
  const location = clean(body.location);
  const lookupPlace = await normalizeLocationForProviders(kind, title, location);
  const status = clean(body.status);
  const locale = clean(body.locale) || "en";
  const languageCode = clean(body.languageCode) || locale.split(/[-_]/)[0] || "en";
  const languageName = clean(body.languageName) || languageCode;
  const isRussian = languageCode.toLowerCase().startsWith("ru");

  const [weather, eventContext] = await Promise.all([
    weatherCard(lookupPlace, isRussian),
    eventsContext(lookupPlace, kind, body.startsAt, body.endsAt, isRussian)
  ]);
  const cards: EnrichmentCard[] = [
    {
      title: isRussian ? "Статус" : "Status",
      value: status || (isRussian ? "Нужно проверить" : "Needs review"),
      detail: title || (isRussian ? "Добавьте заголовок для лучшего контекста." : "Add a title for better context."),
      kind: "ai"
    },
    {
      title: isRussian ? "Карты" : "Maps",
      value: location ? (isRussian ? "Готово" : "Ready") : (isRussian ? "Нужно место" : "Location needed"),
      detail: location || (isRussian ? "Добавьте адрес, аэропорт, отель, место или город." : "Add an address, airport, hotel, venue, or city."),
      kind: "maps"
    },
    weather,
    eventContext.card
  ];

  if (kind === "flight") {
    cards.splice(2, 0, ...await flightCards(title, location, body.startsAt, isRussian));
  }

  const warnings = cards.filter((card) => card.kind === "warning").map((card) => `${card.title}: ${card.detail ?? card.value}`);
  const brief = await buildTravelBrief(kind, title, location, status, cards, warnings, locale, languageCode, languageName);

  const response: EnrichmentResponse = {
    summary: brief.summary,
    cards,
    warnings,
    briefMarkdown: brief.briefMarkdown,
    sections: brief.sections,
    actions: brief.actions,
    routeLegs: brief.routeLegs,
    imageURLs: brief.imageURLs,
    nearbyEvents: eventContext.events
  };

  return res.status(200).json(response);
}
