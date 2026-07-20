import type { VercelRequest, VercelResponse } from "@vercel/node";
import {
  flightWatchKey,
  flightWatchTargetsKey,
  normalizeDeviceToken,
  normalizeFlightDate,
  normalizeFlightNumber,
  redisCommand,
  storageConfigured
} from "./_storage.js";
import { protectPublicEndpoint } from "./_security.js";
import { flightWatchMonitoringStatus, scheduleFlightWatch } from "./_flight-monitor.js";

export type FlightWatchPayload = {
  appInstallId?: string;
  deviceToken?: string;
  itemId?: string;
  tripId?: string;
  flightNumber?: string;
  date?: string;
  departureAt?: string;
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
    ident: flightNumber,
    ident_iata: flightNumber,
    origin_iata: iataAirport(originAirport),
    destination_iata: iataAirport(destinationAirport),
    start: date,
    end: date,
    target_url: flightAwareAlertTargetURL(),
    impending_departure: [30, 15, 5],
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
  const existingTargetURL = await redisCommand<string>(["HGET", metaKey, "flightAwareAlertTargetURL"]);
  const targetURL = flightAwareAlertTargetURL();

  if (existingSubscribed === "1" && existingTargetURL === targetURL) {
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
  const canRepairExisting = existingSubscribed === "1" && Boolean(existingAlertId);
  const alertURL = canRepairExisting
    ? `https://aeroapi.flightaware.com/aeroapi/alerts/${encodeURIComponent(existingAlertId!)}`
    : "https://aeroapi.flightaware.com/aeroapi/alerts";
  const response = await fetch(alertURL, {
    method: canRepairExisting ? "PUT" : "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      "x-apikey": apiKey
    },
    body: JSON.stringify(body)
  });
  const data = await response.json().catch(() => undefined) as unknown;
  const location = response.headers.get("location") ?? existingLocation ?? undefined;
  const alertId = alertIdFromLocation(location ?? null) ?? existingAlertId ?? undefined;

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
    "flightAwareAlertTargetURL",
    targetURL ?? "",
    "flightAwareAlertCreatedAt",
    new Date().toISOString()
  ]);

  return {
    requested: true,
    configured: true,
    subscribed: true,
    existing: canRepairExisting,
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
  const storedTargetURL = await redisCommand<string>(["HGET", metaKey, "flightAwareAlertTargetURL"]);
  const isCurrent = subscribed === "1" && storedTargetURL === flightAwareAlertTargetURL();

  return {
    requested: false,
    configured: Boolean(flightAwareApiKey()),
    subscribed: isCurrent,
    existing: isCurrent,
    alertId: alertId || undefined,
    location: location || undefined
  };
}

export async function registerFlightWatch(payload: FlightWatchPayload) {
  const flightNumber = normalizeFlightNumber(payload.flightNumber);
  const date = normalizeFlightDate(payload.date);
  const deviceToken = normalizeDeviceToken(payload.deviceToken);
  const appInstallId = validInstallID(payload.appInstallId);
  const tripId = validInstallID(payload.tripId);
  const itemId = validInstallID(payload.itemId);
  const departureAt = clean(payload.departureAt);

  if (!flightNumber) {
    return { status: 400, body: { error: "Invalid flight number." } };
  }
  if (!appInstallId || !deviceToken) {
    return { status: 400, body: { error: "A valid app installation ID and APNs device token are required." } };
  }

  if (!storageConfigured()) {
    return { status: 202, body: {
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
      },
      monitoring: {
        state: "unavailable",
        fallbackPolling: false,
        lastError: "Redis is required for durable flight monitoring."
      }
    } };
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
    "departureAt",
    departureAt ?? "",
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
  const target = JSON.stringify({ appInstallId, tripId, itemId });
  await redisCommand(["HSET", flightWatchTargetsKey(flightNumber, date), deviceToken, target]);
  await redisCommand(["EXPIRE", flightWatchTargetsKey(flightNumber, date), ttl]);
  if (date) {
    const genericDevicesKey = `voya:flight-watch:${flightWatchKey(flightNumber)}:devices`;
    await redisCommand(["SADD", genericDevicesKey, deviceToken]);
    await redisCommand(["EXPIRE", genericDevicesKey, ttl]);
    await redisCommand(["HSET", flightWatchTargetsKey(flightNumber), deviceToken, target]);
    await redisCommand(["EXPIRE", flightWatchTargetsKey(flightNumber), ttl]);
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
  await scheduleFlightWatch({
    key,
    departureAt,
    date,
    subscribed: alertWatch.subscribed,
    error: "error" in alertWatch ? alertWatch.error : undefined
  });
  const monitoring = await flightWatchMonitoringStatus(flightNumber, date);

  return { status: 202, body: {
    accepted: true,
    stored: true,
    flightKey: key,
    deviceLinked: true,
    alertWatch,
    monitoring,
    updatedAt: now
  } };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!await protectPublicEndpoint(req, res, { name: "flight-watch", hourlyIPLimit: 120, hourlyInstallLimit: 40, maxBodyBytes: 24_000 })) return;
  const result = await registerFlightWatch(req.body as FlightWatchPayload);
  return res.status(result.status).json(result.body);
}
