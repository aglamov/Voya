import crypto from "node:crypto";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { normalizeDeviceToken, redisCommand, storageConfigured } from "./_storage.js";
import { geocodeWeatherLocation, normalizeCoordinates, weatherConfigured } from "./_weather.js";

export type StoredWeatherWatch = {
  id: string;
  appInstallId: string;
  deviceToken: string;
  tripId: string;
  itemId?: string;
  label: string;
  location: string;
  latitude: number;
  longitude: number;
  startsAt?: string;
  endsAt?: string;
  locale?: string;
  updatedAt: string;
};

type WeatherWatchPayload = {
  appInstallId?: string;
  deviceToken?: string;
  tripId?: string;
  itemId?: string;
  label?: string;
  location?: string;
  latitude?: number;
  longitude?: number;
  startsAt?: string;
  endsAt?: string;
  locale?: string;
};

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function optionalISODate(value: unknown) {
  const raw = clean(value);
  if (!raw) {
    return undefined;
  }
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
}

function uuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function firstHeader(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

async function withinRegistrationLimit(req: VercelRequest, appInstallId: string) {
  const forwarded = firstHeader(req.headers["x-forwarded-for"])?.split(",")[0]?.trim();
  const address = forwarded || firstHeader(req.headers["x-real-ip"])?.trim() || "unknown";
  const bucket = Math.floor(Date.now() / (60 * 60 * 1000));
  const keys = [
    { key: `voya:rate:weather-watch:ip:${address}:${bucket}`, limit: 60 },
    { key: `voya:rate:weather-watch:install:${appInstallId}:${bucket}`, limit: 40 }
  ];
  for (const entry of keys) {
    const count = await redisCommand<number>(["INCR", entry.key]);
    if (count === 1) {
      await redisCommand(["EXPIRE", entry.key, 2 * 60 * 60]);
    }
    if ((count ?? 0) > entry.limit) {
      return false;
    }
  }
  return true;
}

function watchId(payload: WeatherWatchPayload) {
  return crypto.createHash("sha256")
    .update([clean(payload.appInstallId), clean(payload.tripId), clean(payload.itemId) || "destination"].join(":"))
    .digest("hex")
    .slice(0, 32);
}

export function weatherWatchKey(id: string) {
  return `voya:weather-watch:${id}`;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const payload = req.body as WeatherWatchPayload;
  const appInstallId = clean(payload.appInstallId);
  const tripId = clean(payload.tripId);
  const deviceToken = normalizeDeviceToken(payload.deviceToken);
  const location = clean(payload.location);
  const label = clean(payload.label) || location;
  if (!appInstallId || !tripId || !deviceToken || !location) {
    return res.status(400).json({ error: "appInstallId, tripId, deviceToken, and location are required." });
  }

  if (!weatherConfigured()) {
    return res.status(503).json({ error: "OPENWEATHER_API_KEY is not configured." });
  }
  if (!storageConfigured()) {
    return res.status(503).json({ error: "Upstash Redis is not configured." });
  }
  if (!uuid(appInstallId) || !uuid(tripId) || (clean(payload.itemId) && !uuid(clean(payload.itemId)))) {
    return res.status(400).json({ error: "Invalid installation, trip, or item identifier." });
  }
  if (location.length > 500 || label.length > 160) {
    return res.status(400).json({ error: "Weather watch location or label is too long." });
  }
  if (!await withinRegistrationLimit(req, appInstallId)) {
    res.setHeader("Retry-After", "3600");
    return res.status(429).json({ error: "Weather watch registration limit exceeded." });
  }

  const providedCoordinates = normalizeCoordinates(payload.latitude, payload.longitude);
  const place = providedCoordinates
    ? { ...providedCoordinates, name: label }
    : await geocodeWeatherLocation(location);
  if (!place) {
    return res.status(422).json({ error: `OpenWeather could not locate ${location}.` });
  }

  const id = watchId(payload);
  const now = new Date().toISOString();
  const record: StoredWeatherWatch = {
    id,
    appInstallId,
    deviceToken,
    tripId,
    itemId: clean(payload.itemId) || undefined,
    label: label || place.name,
    location,
    latitude: place.lat,
    longitude: place.lon,
    startsAt: optionalISODate(payload.startsAt),
    endsAt: optionalISODate(payload.endsAt),
    locale: clean(payload.locale) || undefined,
    updatedAt: now
  };

  const expiryDate = record.endsAt ? new Date(record.endsAt) : new Date(Date.now() + 60 * 24 * 60 * 60 * 1000);
  const ttlSeconds = Math.max(24 * 60 * 60, Math.floor((expiryDate.getTime() - Date.now()) / 1000) + 2 * 24 * 60 * 60);
  await redisCommand(["SET", weatherWatchKey(id), JSON.stringify(record), "EX", ttlSeconds]);
  await redisCommand(["SADD", "voya:weather-watch:index", id]);
  await redisCommand([
    "HSET", `voya:push:device:${deviceToken}`,
    "appInstallId", appInstallId,
    "lastWeatherWatch", id,
    "updatedAt", now
  ]);

  return res.status(202).json({
    accepted: true,
    stored: true,
    watch: record,
    monitoring: "scheduled"
  });
}
