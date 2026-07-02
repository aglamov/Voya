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

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function firstFlightNumber(value: string) {
  return value.match(/\b[A-Z]{2}\s?\d{2,4}\b/i)?.[0]?.replace(/\s+/g, "").toUpperCase();
}

async function geocode(location: string) {
  const apiKey = process.env.OPENWEATHER_API_KEY;
  if (!apiKey || !location) {
    return null;
  }

  const url = new URL("https://api.openweathermap.org/geo/1.0/direct");
  url.searchParams.set("q", location);
  url.searchParams.set("limit", "1");
  url.searchParams.set("appid", apiKey);

  const response = await fetch(url);
  if (!response.ok) {
    return null;
  }

  const places = (await response.json()) as Array<{ lat: number; lon: number; name?: string; country?: string }>;
  return places[0] ?? null;
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

  const place = await geocode(location);
  if (!place) {
    return {
      title: "Weather",
      value: "Location needed",
      detail: "Add a clearer city, airport, hotel, or venue address.",
      kind: "weather"
    };
  }

  const url = new URL("https://api.openweathermap.org/data/3.0/onecall");
  url.searchParams.set("lat", String(place.lat));
  url.searchParams.set("lon", String(place.lon));
  url.searchParams.set("exclude", "minutely");
  url.searchParams.set("units", "metric");
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
    current?: { temp?: number; weather?: Array<{ description?: string }> };
    alerts?: Array<{ event?: string }>;
  };
  const temp = data.current?.temp;
  const description = data.current?.weather?.[0]?.description;
  const alert = data.alerts?.[0]?.event;

  return {
    title: "Weather",
    value: temp == null ? "Forecast ready" : `${Math.round(temp)} C`,
    detail: [description, alert ? `Alert: ${alert}` : undefined].filter(Boolean).join(" · "),
    kind: alert ? "warning" : "weather"
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
    await weatherCard(location),
    await eventsCard(location)
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
