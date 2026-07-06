import type { VercelRequest, VercelResponse } from "@vercel/node";
import {
  flightWatchKey,
  normalizeDeviceToken,
  normalizeFlightDate,
  normalizeFlightNumber,
  redisCommand,
  storageConfigured
} from "./_storage.js";

type FlightWatchPayload = {
  appInstallId?: string;
  deviceToken?: string;
  itemId?: string;
  flightNumber?: string;
  date?: string;
  originAirport?: string;
  destinationAirport?: string;
  subscribeToAlerts?: boolean;
};

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : undefined;
}

function flightAwareApiKey() {
  return process.env.FLIGHTAWARE_AEROAPI_KEY?.trim();
}

function normalizedPublicBaseURL() {
  const value = process.env.VOYA_API_PUBLIC_BASE_URL?.trim().replace(/\/$/, "");
  if (!value) {
    return undefined;
  }
  return value.startsWith("http://") || value.startsWith("https://") ? value : `https://${value}`;
}

function flightAwareAlertTargetURL() {
  const baseURL = normalizedPublicBaseURL();
  const secret = process.env.FLIGHTAWARE_ALERT_WEBHOOK_SECRET?.trim();
  if (!baseURL || !secret) {
    return undefined;
  }

  return `${baseURL}/api/flightaware-alerts?secret=${encodeURIComponent(secret)}`;
}

function iataAirport(value: string | undefined) {
  const normalized = clean(value)?.toUpperCase();
  return normalized && /^[A-Z]{3}$/.test(normalized) ? normalized : undefined;
}

function flightAwareAlertPayload(
  flightNumber: string,
  date: string | undefined,
  originAirport: string | undefined,
  destinationAirport: string | undefined
) {
  return {
    description: `Voya ${flightNumber}${date ? ` ${date}` : ""}`,
    ident: flightNumber,
    ident_iata: flightNumber,
    origin_iata: iataAirport(originAirport),
    destination_iata: iataAirport(destinationAirport),
    start: date,
    end: date,
    enabled: true,
    target_url: flightAwareAlertTargetURL(),
    events: {
      arrival: true,
      cancelled: true,
      departure: true,
      diverted: true,
      filed: true,
      out: true,
      off: true,
      on: true,
      in: true,
      hold_start: true,
      hold_end: true
    }
  };
}

function compactRecord<T extends Record<string, unknown>>(value: T) {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined && item !== "")) as T;
}

function alertIdFromLocation(location: string | null) {
  return location?.match(/\/alerts\/(\d+)/)?.[1];
}

async function ensureFlightAwareAlert(
  key: string,
  flightNumber: string,
  date: string | undefined,
  originAirport: string | undefined,
  destinationAirport: string | undefined
) {
  const metaKey = `voya:flight-watch:${key}:meta`;
  const existingSubscribed = await redisCommand<string>(["HGET", metaKey, "flightAwareAlertSubscribed"]);
  const existingAlertId = await redisCommand<string>(["HGET", metaKey, "flightAwareAlertId"]);
  const existingLocation = await redisCommand<string>(["HGET", metaKey, "flightAwareAlertLocation"]);

  if (existingSubscribed === "1") {
    return {
      requested: false,
      configured: Boolean(flightAwareApiKey()),
      subscribed: true,
      existing: true,
      alertId: existingAlertId || undefined,
      location: existingLocation || undefined
    };
  }

  const apiKey = flightAwareApiKey();
  if (!apiKey) {
    return {
      requested: true,
      configured: false,
      subscribed: false,
      existing: false,
      error: "Set FLIGHTAWARE_AEROAPI_KEY to create FlightAware alert subscriptions."
    };
  }

  const body = compactRecord(flightAwareAlertPayload(flightNumber, date, originAirport, destinationAirport));
  const response = await fetch("https://aeroapi.flightaware.com/aeroapi/alerts", {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      "x-apikey": apiKey
    },
    body: JSON.stringify(body)
  });
  const data = await response.json().catch(() => undefined) as unknown;
  const location = response.headers.get("location") ?? undefined;
  const alertId = alertIdFromLocation(location ?? null);

  if (!response.ok) {
    return {
      requested: true,
      configured: true,
      subscribed: false,
      existing: false,
      status: response.status,
      error: typeof data === "object" && data && "detail" in data ? String(data.detail) : `FlightAware alert creation failed with HTTP ${response.status}.`
    };
  }

  await redisCommand([
    "HSET",
    metaKey,
    "flightAwareAlertSubscribed",
    "1",
    "flightAwareAlertId",
    alertId ?? "",
    "flightAwareAlertLocation",
    location ?? "",
    "flightAwareAlertCreatedAt",
    new Date().toISOString()
  ]);

  return {
    requested: true,
    configured: true,
    subscribed: true,
    existing: false,
    status: response.status,
    alertId,
    location
  };
}

async function flightAwareAlertStatus(key: string) {
  const metaKey = `voya:flight-watch:${key}:meta`;
  const subscribed = await redisCommand<string>(["HGET", metaKey, "flightAwareAlertSubscribed"]);
  const alertId = await redisCommand<string>(["HGET", metaKey, "flightAwareAlertId"]);
  const location = await redisCommand<string>(["HGET", metaKey, "flightAwareAlertLocation"]);

  return {
    requested: false,
    configured: Boolean(flightAwareApiKey()),
    subscribed: subscribed === "1",
    existing: subscribed === "1",
    alertId: alertId || undefined,
    location: location || undefined
  };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const payload = req.body as FlightWatchPayload;
  const flightNumber = normalizeFlightNumber(payload.flightNumber);
  const date = normalizeFlightDate(payload.date);
  const deviceToken = normalizeDeviceToken(payload.deviceToken);

  if (!flightNumber) {
    return res.status(400).json({ error: "Invalid flight number." });
  }

  if (!storageConfigured()) {
    return res.status(202).json({
      accepted: true,
      stored: false,
      flightKey: flightWatchKey(flightNumber, date),
      warning: "Set UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN to persist flight watches.",
      alertWatch: {
        requested: Boolean(payload.subscribeToAlerts),
        configured: Boolean(flightAwareApiKey()),
        subscribed: false,
        existing: false,
        error: "Flight watches must be persisted before creating FlightAware alerts."
      }
    });
  }

  const key = flightWatchKey(flightNumber, date);
  const now = new Date().toISOString();
  await redisCommand([
    "HSET",
    `voya:flight-watch:${key}:meta`,
    "flightNumber",
    flightNumber,
    "date",
    date ?? "",
    "originAirport",
    clean(payload.originAirport)?.toUpperCase() ?? "",
    "destinationAirport",
    clean(payload.destinationAirport)?.toUpperCase() ?? "",
    "updatedAt",
    now
  ]);
  await redisCommand(["SADD", `voya:flight-watch-index:${flightNumber}`, key]);

  if (deviceToken) {
    await redisCommand(["SADD", `voya:flight-watch:${key}:devices`, deviceToken]);
    if (date) {
      await redisCommand(["SADD", `voya:flight-watch:${flightWatchKey(flightNumber)}:devices`, deviceToken]);
    }
    await redisCommand([
      "HSET",
      `voya:push:device:${deviceToken}`,
      "appInstallId",
      clean(payload.appInstallId) ?? "",
      "lastFlightWatch",
      key,
      "updatedAt",
      now
    ]);
  }

  const alertWatch = payload.subscribeToAlerts
    ? await ensureFlightAwareAlert(
        key,
        flightNumber,
        date,
        clean(payload.originAirport)?.toUpperCase(),
        clean(payload.destinationAirport)?.toUpperCase()
      )
    : await flightAwareAlertStatus(key);

  return res.status(202).json({
    accepted: true,
    stored: true,
    flightKey: key,
    deviceLinked: Boolean(deviceToken),
    alertWatch,
    updatedAt: now
  });
}
