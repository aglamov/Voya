import type { VercelRequest, VercelResponse } from "@vercel/node";
import {
  flightWatchKey,
  normalizeDeviceToken,
  normalizeFlightDate,
  normalizeFlightNumber,
  redisCommand,
  storageConfigured
} from "./_storage.js";
import { protectPublicEndpoint } from "./_security.js";

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

function validInstallID(value: unknown) {
  const normalized = clean(value)?.toLowerCase();
  return normalized && /^[0-9a-f-]{36}$/.test(normalized) ? normalized : undefined;
}

function watchTTL(date: string | undefined) {
  if (!date) return 14 * 24 * 60 * 60;
  const expiresAt = Date.parse(`${date}T23:59:59Z`) + 3 * 24 * 60 * 60 * 1000;
  return Math.max(24 * 60 * 60, Math.min(120 * 24 * 60 * 60, Math.floor((expiresAt - Date.now()) / 1000)));
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

async function ensureFlightAwareEndpoint(apiKey: string) {
  const targetURL = flightAwareAlertTargetURL();
  if (!targetURL) {
    return { ok: false as const, error: "Set VOYA_API_PUBLIC_BASE_URL and FLIGHTAWARE_ALERT_WEBHOOK_SECRET before enabling flight alerts." };
  }

  const configuredTarget = await redisCommand<string>(["GET", "voya:flightaware:alert-endpoint"]);
  if (configuredTarget === targetURL) {
    return { ok: true as const };
  }

  const response = await fetch("https://aeroapi.flightaware.com/aeroapi/alerts/endpoint", {
    method: "PUT",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      "x-apikey": apiKey
    },
    body: JSON.stringify({ url: targetURL })
  });
  if (!response.ok) {
    const data = await response.json().catch(() => undefined) as { detail?: string } | undefined;
    return {
      ok: false as const,
      status: response.status,
      error: data?.detail ?? `FlightAware alert endpoint setup failed with HTTP ${response.status}.`
    };
  }

  await redisCommand(["SET", "voya:flightaware:alert-endpoint", targetURL]);
  return { ok: true as const };
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

  const endpoint = await ensureFlightAwareEndpoint(apiKey);
  if (!endpoint.ok) {
    return {
      requested: true,
      configured: true,
      subscribed: false,
      existing: false,
      status: endpoint.status,
      error: endpoint.error
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
  if (!await protectPublicEndpoint(req, res, { name: "flight-watch", hourlyIPLimit: 120, hourlyInstallLimit: 40, maxBodyBytes: 24_000 })) return;

  const payload = req.body as FlightWatchPayload;
  const flightNumber = normalizeFlightNumber(payload.flightNumber);
  const date = normalizeFlightDate(payload.date);
  const deviceToken = normalizeDeviceToken(payload.deviceToken);
  const appInstallId = validInstallID(payload.appInstallId);

  if (!flightNumber) {
    return res.status(400).json({ error: "Invalid flight number." });
  }
  if (!appInstallId || !deviceToken) {
    return res.status(400).json({ error: "A valid app installation ID and APNs device token are required." });
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
  const ttl = watchTTL(date);
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
  await redisCommand(["EXPIRE", `voya:flight-watch:${key}:meta`, ttl]);
  await redisCommand(["EXPIRE", `voya:flight-watch-index:${flightNumber}`, ttl]);

  await redisCommand(["SADD", `voya:flight-watch:${key}:devices`, deviceToken]);
  await redisCommand(["EXPIRE", `voya:flight-watch:${key}:devices`, ttl]);
  if (date) {
    const genericDevicesKey = `voya:flight-watch:${flightWatchKey(flightNumber)}:devices`;
    await redisCommand(["SADD", genericDevicesKey, deviceToken]);
    await redisCommand(["EXPIRE", genericDevicesKey, ttl]);
  }
  await redisCommand([
    "HSET",
    `voya:push:device:${deviceToken}`,
    "appInstallId",
    appInstallId,
    "lastFlightWatch",
    key,
    "updatedAt",
    now
  ]);

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
    deviceLinked: true,
    alertWatch,
    updatedAt: now
  });
}
