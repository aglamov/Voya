export type WeatherCoordinates = {
  lat: number;
  lon: number;
  name: string;
  country?: string;
};

export type NormalizedWeatherAlert = {
  id: string;
  provider: "openweather";
  source: string;
  event: string;
  description: string;
  startsAt?: string;
  endsAt?: string;
  severity: "watch" | "action";
};

type OpenWeatherCurrentResponse = {
  data?: Array<{
    temp?: number;
    weather?: Array<{ description?: string }>;
    alerts?: string[];
  }>;
};

type OpenWeatherAlertResponse = {
  id?: string;
  sender_name?: string;
  event?: string;
  start?: number;
  end?: number;
  description?: string;
};

export class WeatherProviderError extends Error {
  constructor(message: string, readonly status?: number) {
    super(message);
    this.name = "WeatherProviderError";
  }
}

export function weatherConfigured() {
  return Boolean(process.env.OPENWEATHER_API_KEY?.trim());
}

function apiKey() {
  const value = process.env.OPENWEATHER_API_KEY?.trim();
  if (!value) {
    throw new WeatherProviderError("OPENWEATHER_API_KEY is not configured.");
  }
  return value;
}

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function validCoordinate(value: number, minimum: number, maximum: number) {
  return Number.isFinite(value) && value >= minimum && value <= maximum;
}

export function normalizeCoordinates(lat: unknown, lon: unknown): { lat: number; lon: number } | undefined {
  const latitude = typeof lat === "number" ? lat : Number(lat);
  const longitude = typeof lon === "number" ? lon : Number(lon);
  if (!validCoordinate(latitude, -90, 90) || !validCoordinate(longitude, -180, 180)) {
    return undefined;
  }
  return { lat: latitude, lon: longitude };
}

export async function geocodeWeatherLocation(location: string): Promise<WeatherCoordinates | undefined> {
  const query = clean(location);
  if (!query) {
    return undefined;
  }

  const candidates = [query];
  const parts = query.split(",").map((part) => part.trim()).filter(Boolean);
  if (parts.length > 2) {
    candidates.push(parts.slice(-2).join(", "));
  }

  for (const candidate of [...new Set(candidates)]) {
    const url = new URL("https://api.openweathermap.org/geo/1.0/direct");
    url.searchParams.set("q", candidate);
    url.searchParams.set("limit", "1");
    url.searchParams.set("appid", apiKey());
    const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
    if (!response.ok) {
      throw new WeatherProviderError(`OpenWeather geocoding returned HTTP ${response.status}.`, response.status);
    }

    const places = await response.json() as Array<{ lat?: number; lon?: number; name?: string; country?: string }>;
    const place = places[0];
    const coordinates = normalizeCoordinates(place?.lat, place?.lon);
    if (place && coordinates) {
      return {
        ...coordinates,
        name: clean(place.name) || candidate,
        country: clean(place.country) || undefined
      };
    }
  }

  return undefined;
}

export async function currentWeatherAt(
  coordinates: { lat: number; lon: number },
  language = "en"
) {
  const url = new URL("https://api.openweathermap.org/data/4.0/onecall/current");
  url.searchParams.set("lat", String(coordinates.lat));
  url.searchParams.set("lon", String(coordinates.lon));
  url.searchParams.set("units", "metric");
  url.searchParams.set("lang", language);
  url.searchParams.set("appid", apiKey());
  const response = await fetch(url, { signal: AbortSignal.timeout(12_000) });
  if (!response.ok) {
    throw new WeatherProviderError(`OpenWeather current conditions returned HTTP ${response.status}.`, response.status);
  }

  const data = await response.json() as OpenWeatherCurrentResponse;
  const current = data.data?.[0];
  return {
    temperatureCelsius: current?.temp,
    description: clean(current?.weather?.[0]?.description) || undefined,
    alertIds: [...new Set((current?.alerts ?? []).map(clean).filter(Boolean))]
  };
}

function isoDate(value: number | undefined) {
  if (!Number.isFinite(value)) {
    return undefined;
  }
  return new Date((value as number) * 1000).toISOString();
}

function severityFor(event: string, description: string): "watch" | "action" {
  const value = `${event} ${description}`.toLowerCase();
  return /emergency|extreme|warning|hurricane|tornado|typhoon|cyclone|tsunami|flash flood|severe thunderstorm|red alert|heat wave|heatwave|blizzard|ice storm/.test(value)
    ? "action"
    : "watch";
}

export async function weatherAlertDetails(alertId: string): Promise<NormalizedWeatherAlert> {
  const normalizedId = clean(alertId);
  if (!normalizedId) {
    throw new WeatherProviderError("Weather alert ID is missing.");
  }

  const url = new URL(`https://api.openweathermap.org/data/4.0/onecall/alert/${encodeURIComponent(normalizedId)}`);
  url.searchParams.set("appid", apiKey());
  const response = await fetch(url, { signal: AbortSignal.timeout(12_000) });
  if (!response.ok) {
    throw new WeatherProviderError(`OpenWeather alert ${normalizedId} returned HTTP ${response.status}.`, response.status);
  }

  const data = await response.json() as OpenWeatherAlertResponse;
  const event = clean(data.event) || "Weather alert";
  const description = clean(data.description) || event;
  return {
    id: clean(data.id) || normalizedId,
    provider: "openweather",
    source: clean(data.sender_name) || "OpenWeather",
    event,
    description,
    startsAt: isoDate(data.start),
    endsAt: isoDate(data.end),
    severity: severityFor(event, description)
  };
}

export async function activeWeatherAlertsAt(coordinates: { lat: number; lon: number }) {
  const current = await currentWeatherAt(coordinates);
  const alerts = await Promise.all(current.alertIds.map((id) => weatherAlertDetails(id)));
  return { current, alerts };
}
