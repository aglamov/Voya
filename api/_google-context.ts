type GoogleProviderError = "not_configured" | "not_found" | "unavailable";

export type GoogleProviderResult<T> =
  | { data: T }
  | { error: GoogleProviderError; status?: number };

export type GooglePlaceContext = {
  id: string;
  name: string;
  address?: string;
  latitude: number;
  longitude: number;
  primaryType?: string;
  rating?: number;
  userRatingCount?: number;
  priceLevel?: string;
  openNow?: boolean;
  weekdayDescriptions?: string[];
  mapsURL?: string;
};

export type GoogleAirQualityContext = {
  observedAt?: string;
  aqi?: number;
  category?: string;
  dominantPollutant?: string;
  recommendation?: string;
};

export type GooglePollenType = {
  code: string;
  name: string;
  inSeason: boolean;
  value?: number;
  category?: string;
  recommendation?: string;
};

export type GooglePollenContext = {
  date?: string;
  peakDate?: string;
  maximumIndex?: number;
  dominantTypes: GooglePollenType[];
};

type CacheEntry<T> = { expiresAt: number; value: GoogleProviderResult<T> };

const placeCache = new Map<string, CacheEntry<GooglePlaceContext>>();
const airQualityCache = new Map<string, CacheEntry<GoogleAirQualityContext>>();
const pollenCache = new Map<string, CacheEntry<GooglePollenContext>>();

const PLACE_TTL_MS = 24 * 60 * 60 * 1_000;
const AIR_QUALITY_TTL_MS = 15 * 60 * 1_000;
const POLLEN_TTL_MS = 6 * 60 * 60 * 1_000;

function providerKey(service: "places" | "air" | "pollen") {
  const specific = service === "places"
    ? process.env.GOOGLE_PLACES_API_KEY
    : service === "air"
      ? process.env.GOOGLE_AIR_QUALITY_API_KEY
      : process.env.GOOGLE_POLLEN_API_KEY;
  return (specific ?? process.env.GOOGLE_MAPS_API_KEY)?.trim();
}

export function googleContextConfigured(service?: "places" | "air" | "pollen") {
  if (service) return Boolean(providerKey(service));
  return Boolean(providerKey("places") || providerKey("air") || providerKey("pollen"));
}

function cached<T>(cache: Map<string, CacheEntry<T>>, key: string) {
  const entry = cache.get(key);
  if (!entry || entry.expiresAt <= Date.now()) {
    if (entry) cache.delete(key);
    return undefined;
  }
  return entry.value;
}

function store<T>(cache: Map<string, CacheEntry<T>>, key: string, value: GoogleProviderResult<T>, ttl: number) {
  if (cache.size > 400) {
    for (const [candidate, entry] of cache) {
      if (entry.expiresAt <= Date.now()) cache.delete(candidate);
      if (cache.size <= 320) break;
    }
  }
  cache.set(key, { expiresAt: Date.now() + ttl, value });
  return value;
}

function normalizedLanguage(languageCode?: string) {
  const value = languageCode?.trim().replace("_", "-");
  return value && /^[a-z]{2,3}(?:-[a-zA-Z]{2,4})?$/.test(value) ? value : "en";
}

function coordinateKey(latitude: number, longitude: number, languageCode?: string) {
  return `${latitude.toFixed(3)},${longitude.toFixed(3)}:${normalizedLanguage(languageCode)}`;
}

function validCoordinate(latitude: number, longitude: number) {
  return Number.isFinite(latitude) && latitude >= -90 && latitude <= 90
    && Number.isFinite(longitude) && longitude >= -180 && longitude <= 180;
}

async function googleFetch(url: URL | string, init?: RequestInit) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timeout);
  }
}

export async function findGooglePlace(query: string, languageCode?: string): Promise<GoogleProviderResult<GooglePlaceContext>> {
  const apiKey = providerKey("places");
  if (!apiKey) return { error: "not_configured" };
  const textQuery = query.replace(/\s+/g, " ").trim().slice(0, 500);
  if (!textQuery) return { error: "not_found" };
  const language = normalizedLanguage(languageCode);
  const cacheKey = `${language}:${textQuery.toLowerCase()}`;
  const existing = cached(placeCache, cacheKey);
  if (existing) return existing;

  try {
    const response = await googleFetch("https://places.googleapis.com/v1/places:searchText", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": [
          "places.id",
          "places.displayName",
          "places.formattedAddress",
          "places.location",
          "places.primaryType",
          "places.rating",
          "places.userRatingCount",
          "places.priceLevel",
          "places.regularOpeningHours.openNow",
          "places.regularOpeningHours.weekdayDescriptions",
          "places.googleMapsUri"
        ].join(",")
      },
      body: JSON.stringify({ textQuery, languageCode: language, pageSize: 1 })
    });
    if (!response.ok) {
      return store(placeCache, cacheKey, { error: "unavailable", status: response.status }, 60_000);
    }
    const payload = await response.json() as {
      places?: Array<{
        id?: string;
        displayName?: { text?: string };
        formattedAddress?: string;
        location?: { latitude?: number; longitude?: number };
        primaryType?: string;
        rating?: number;
        userRatingCount?: number;
        priceLevel?: string;
        regularOpeningHours?: { openNow?: boolean; weekdayDescriptions?: string[] };
        googleMapsUri?: string;
      }>;
    };
    const place = payload.places?.[0];
    const latitude = place?.location?.latitude;
    const longitude = place?.location?.longitude;
    const name = place?.displayName?.text?.trim();
    if (!place?.id || !name || latitude == null || longitude == null || !validCoordinate(latitude, longitude)) {
      return store(placeCache, cacheKey, { error: "not_found" }, 10 * 60_000);
    }
    return store(placeCache, cacheKey, { data: {
      id: place.id,
      name,
      address: place.formattedAddress?.trim(),
      latitude,
      longitude,
      primaryType: place.primaryType,
      rating: place.rating,
      userRatingCount: place.userRatingCount,
      priceLevel: place.priceLevel,
      openNow: place.regularOpeningHours?.openNow,
      weekdayDescriptions: place.regularOpeningHours?.weekdayDescriptions,
      mapsURL: place.googleMapsUri
    } }, PLACE_TTL_MS);
  } catch {
    return store(placeCache, cacheKey, { error: "unavailable" }, 60_000);
  }
}

export async function lookupGoogleAirQuality(
  latitude: number,
  longitude: number,
  languageCode?: string
): Promise<GoogleProviderResult<GoogleAirQualityContext>> {
  const apiKey = providerKey("air");
  if (!apiKey) return { error: "not_configured" };
  if (!validCoordinate(latitude, longitude)) return { error: "not_found" };
  const language = normalizedLanguage(languageCode);
  const cacheKey = coordinateKey(latitude, longitude, language);
  const existing = cached(airQualityCache, cacheKey);
  if (existing) return existing;

  const url = new URL("https://airquality.googleapis.com/v1/currentConditions:lookup");
  url.searchParams.set("key", apiKey);
  try {
    const response = await googleFetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        universalAqi: true,
        location: { latitude, longitude },
        languageCode: language,
        extraComputations: ["HEALTH_RECOMMENDATIONS", "DOMINANT_POLLUTANT_CONCENTRATION"]
      })
    });
    if (!response.ok) {
      return store(airQualityCache, cacheKey, { error: "unavailable", status: response.status }, 60_000);
    }
    const payload = await response.json() as {
      dateTime?: string;
      indexes?: Array<{ code?: string; aqi?: number; category?: string; dominantPollutant?: string }>;
      healthRecommendations?: { generalPopulation?: string };
    };
    const index = payload.indexes?.find((item) => item.code === "uaqi") ?? payload.indexes?.[0];
    if (!index) return store(airQualityCache, cacheKey, { error: "not_found" }, 5 * 60_000);
    return store(airQualityCache, cacheKey, { data: {
      observedAt: payload.dateTime,
      aqi: index.aqi,
      category: index.category,
      dominantPollutant: index.dominantPollutant,
      recommendation: payload.healthRecommendations?.generalPopulation?.trim()
    } }, AIR_QUALITY_TTL_MS);
  } catch {
    return store(airQualityCache, cacheKey, { error: "unavailable" }, 60_000);
  }
}

function pollenDate(value?: { year?: number; month?: number; day?: number }) {
  if (!value?.year || !value.month || !value.day) return undefined;
  return `${String(value.year).padStart(4, "0")}-${String(value.month).padStart(2, "0")}-${String(value.day).padStart(2, "0")}`;
}

export async function lookupGooglePollen(
  latitude: number,
  longitude: number,
  languageCode?: string,
  days = 3
): Promise<GoogleProviderResult<GooglePollenContext>> {
  const apiKey = providerKey("pollen");
  if (!apiKey) return { error: "not_configured" };
  if (!validCoordinate(latitude, longitude)) return { error: "not_found" };
  const language = normalizedLanguage(languageCode);
  const requestedDays = Math.max(1, Math.min(5, Math.floor(days)));
  const cacheKey = `${coordinateKey(latitude, longitude, language)}:${requestedDays}`;
  const existing = cached(pollenCache, cacheKey);
  if (existing) return existing;

  const url = new URL("https://pollen.googleapis.com/v1/forecast:lookup");
  url.searchParams.set("key", apiKey);
  url.searchParams.set("location.latitude", String(latitude));
  url.searchParams.set("location.longitude", String(longitude));
  url.searchParams.set("days", String(requestedDays));
  url.searchParams.set("pageSize", String(requestedDays));
  url.searchParams.set("languageCode", language);
  url.searchParams.set("plantsDescription", "false");
  try {
    const response = await googleFetch(url);
    if (!response.ok) {
      return store(pollenCache, cacheKey, { error: "unavailable", status: response.status }, 60_000);
    }
    const payload = await response.json() as {
      dailyInfo?: Array<{
        date?: { year?: number; month?: number; day?: number };
        pollenTypeInfo?: Array<{
          code?: string;
          displayName?: string;
          inSeason?: boolean;
          indexInfo?: { value?: number; category?: string };
          healthRecommendations?: string[];
        }>;
      }>;
    };
    const daysWithPollen = (payload.dailyInfo ?? []).map((day) => ({
      date: pollenDate(day.date),
      types: (day.pollenTypeInfo ?? []).flatMap((type): GooglePollenType[] => {
        if (!type.code || !type.displayName) return [];
        return [{
          code: type.code,
          name: type.displayName,
          inSeason: type.inSeason === true,
          value: type.indexInfo?.value,
          category: type.indexInfo?.category,
          recommendation: type.healthRecommendations?.find(Boolean)?.trim()
        }];
      })
    }));
    const allTypes = daysWithPollen.flatMap((day) => day.types.map((type) => ({ ...type, date: day.date })));
    if (!daysWithPollen.length) return store(pollenCache, cacheKey, { error: "not_found" }, 60 * 60_000);
    const maximumIndex = allTypes.reduce<number | undefined>((maximum, type) => {
      if (type.value == null) return maximum;
      return maximum == null ? type.value : Math.max(maximum, type.value);
    }, undefined);
    const dominantTypes = allTypes
      .filter((type) => type.value != null && type.value === maximumIndex)
      .filter((type, index, values) => values.findIndex((candidate) => candidate.code === type.code) === index)
      .slice(0, 3)
      .map(({ date: _date, ...type }) => type);
    const peakDate = allTypes.find((type) => type.value != null && type.value === maximumIndex)?.date;
    return store(pollenCache, cacheKey, { data: {
      date: daysWithPollen[0]?.date,
      peakDate,
      maximumIndex,
      dominantTypes
    } }, POLLEN_TTL_MS);
  } catch {
    return store(pollenCache, cacheKey, { error: "unavailable" }, 60_000);
  }
}

export async function googleTravelContext(query: string, languageCode?: string) {
  const place = await findGooglePlace(query, languageCode);
  if (!("data" in place)) return { place };
  const [airQuality, pollen] = await Promise.all([
    lookupGoogleAirQuality(place.data.latitude, place.data.longitude, languageCode),
    lookupGooglePollen(place.data.latitude, place.data.longitude, languageCode)
  ]);
  return { place, airQuality, pollen };
}
