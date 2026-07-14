import type { VercelRequest, VercelResponse } from "@vercel/node";
import { timingSafeEqual } from "node:crypto";
import { sendAPNsAlert } from "./_apns.js";
import { redisCommand, storageConfigured } from "./_storage.js";
import {
  currentWeatherAt,
  type NormalizedWeatherAlert,
  weatherAlertDetails,
  weatherConfigured
} from "./_weather.js";
import { weatherWatchKey, type StoredWeatherWatch } from "./weather-watch.js";

function firstHeader(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function suppliedSecret(req: VercelRequest) {
  const authorization = firstHeader(req.headers.authorization)?.trim();
  const bearer = authorization?.toLowerCase().startsWith("bearer ")
    ? authorization.slice("bearer ".length).trim()
    : undefined;
  return firstHeader(req.headers["x-voya-monitor-secret"])?.trim()
    || (typeof req.query.secret === "string" ? req.query.secret.trim() : undefined)
    || bearer;
}

function authorized(req: VercelRequest) {
  const actual = suppliedSecret(req);
  const expectedSecrets = [process.env.CRON_SECRET, process.env.WEATHER_MONITOR_SECRET]
    .map((value) => value?.trim())
    .filter(Boolean) as string[];
  if (!expectedSecrets.length || !actual) {
    return false;
  }
  const encoder = new TextEncoder();
  const lhs = encoder.encode(actual);
  return expectedSecrets.some((expected) => {
    const rhs = encoder.encode(expected);
    return lhs.length === rhs.length && timingSafeEqual(lhs, rhs);
  });
}

function parsedWatch(raw: string | undefined) {
  if (!raw) {
    return undefined;
  }
  try {
    return JSON.parse(raw) as StoredWeatherWatch;
  } catch {
    return undefined;
  }
}

function isRelevant(watch: StoredWeatherWatch, now = new Date()) {
  const startsAt = watch.startsAt ? new Date(watch.startsAt) : undefined;
  const endsAt = watch.endsAt ? new Date(watch.endsAt) : undefined;
  if (startsAt && startsAt.getTime() > now.getTime() + 48 * 60 * 60 * 1000) {
    return false;
  }
  return !endsAt || endsAt.getTime() >= now.getTime() - 12 * 60 * 60 * 1000;
}

function coordinateKey(watch: StoredWeatherWatch) {
  return `${watch.latitude.toFixed(2)}:${watch.longitude.toFixed(2)}`;
}

function compactDescription(value: string) {
  return value.replace(/\s+/g, " ").trim().slice(0, 240);
}

function pushCopy(alert: NormalizedWeatherAlert, watch: StoredWeatherWatch) {
  return {
    title: alert.severity === "action" ? alert.event : `Weather watch: ${alert.event}`,
    body: `${watch.label}: ${compactDescription(alert.description)}`
  };
}

async function claimDelivery(watch: StoredWeatherWatch, alert: NormalizedWeatherAlert) {
  const key = `voya:weather-alert-delivery:${watch.appInstallId}:${alert.id}`;
  const end = alert.endsAt ? new Date(alert.endsAt).getTime() : Date.now() + 24 * 60 * 60 * 1000;
  const ttl = Math.max(6 * 60 * 60, Math.floor((end - Date.now()) / 1000) + 24 * 60 * 60);
  const result = await redisCommand<string | null>(["SET", key, "1", "EX", ttl, "NX"]);
  return result === "OK" ? key : undefined;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST" && req.method !== "GET") {
    res.setHeader("Allow", "GET, POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!authorized(req)) {
    return res.status(401).json({ error: "Unauthorized weather monitor invocation." });
  }
  if (!weatherConfigured() || !storageConfigured()) {
    return res.status(503).json({ error: "OpenWeather and Upstash Redis must be configured." });
  }

  const acquiredLock = await redisCommand<string | null>([
    "SET",
    "voya:weather-monitor:lock",
    new Date().toISOString(),
    "EX",
    9 * 60,
    "NX"
  ]);
  if (acquiredLock !== "OK") {
    return res.status(202).json({ ok: true, skipped: true, reason: "Weather monitor is already running or recently completed." });
  }

  const watchIds = await redisCommand<string[]>(["SMEMBERS", "voya:weather-watch:index"]);
  const watches: StoredWeatherWatch[] = [];
  let staleWatches = 0;
  for (const id of watchIds ?? []) {
    const watch = parsedWatch(await redisCommand<string>(["GET", weatherWatchKey(id)]));
    if (!watch) {
      staleWatches += 1;
      await redisCommand(["SREM", "voya:weather-watch:index", id]);
    } else if (isRelevant(watch)) {
      watches.push(watch);
    }
  }

  const groups = new Map<string, StoredWeatherWatch[]>();
  for (const watch of watches) {
    const key = coordinateKey(watch);
    groups.set(key, [...(groups.get(key) ?? []), watch]);
  }

  const groupEntries = [...groups.entries()];
  const configuredLimit = Number(process.env.WEATHER_MAX_GROUPS_PER_RUN ?? "12");
  const groupLimit = Math.max(1, Math.min(100, Number.isFinite(configuredLimit) ? Math.floor(configuredLimit) : 12));
  const storedCursor = Number(await redisCommand<string>(["GET", "voya:weather-monitor:cursor"]) ?? "0");
  const cursor = groupEntries.length ? Math.max(0, storedCursor) % groupEntries.length : 0;
  const selectedGroups = Array.from(
    { length: Math.min(groupLimit, groupEntries.length) },
    (_, offset) => groupEntries[(cursor + offset) % groupEntries.length]
  );
  if (groupEntries.length) {
    await redisCommand(["SET", "voya:weather-monitor:cursor", (cursor + selectedGroups.length) % groupEntries.length]);
  }

  let providerQueries = 0;
  let matchedAlerts = 0;
  let pushesSent = 0;
  const errors: string[] = [];
  const alertDetails = new Map<string, Promise<NormalizedWeatherAlert>>();
  for (const [, groupedWatches] of selectedGroups) {
    const representative = groupedWatches[0];
    try {
      providerQueries += 1;
      const current = await currentWeatherAt({
        lat: representative.latitude,
        lon: representative.longitude
      });
      matchedAlerts += current.alertIds.length;
      const alerts = await Promise.all(current.alertIds.map((id) => {
        const cached = alertDetails.get(id);
        if (cached) {
          return cached;
        }
        const detail = weatherAlertDetails(id);
        alertDetails.set(id, detail);
        return detail;
      }));
      for (const alert of alerts) {
        for (const watch of groupedWatches) {
          const deliveryKey = await claimDelivery(watch, alert);
          if (!deliveryKey) {
            continue;
          }
          const copy = pushCopy(alert, watch);
          const push = await sendAPNsAlert([watch.deviceToken], {
            title: copy.title,
            body: copy.body,
            threadId: `weather-${alert.id}`,
            data: {
              provider: alert.provider,
              eventType: "weather_alert",
              alertId: alert.id,
              severity: alert.severity,
              source: alert.source,
              startsAt: alert.startsAt,
              endsAt: alert.endsAt,
              tripId: watch.tripId,
              itemId: watch.itemId
            }
          });
          pushesSent += push.sent;
          errors.push(...push.errors);
          if (push.invalidDeviceTokens.includes(watch.deviceToken)) {
            await redisCommand(["SREM", "voya:weather-watch:index", watch.id]);
            await redisCommand(["DEL", weatherWatchKey(watch.id)]);
          }
          if (push.sent === 0) {
            await redisCommand(["DEL", deliveryKey]);
          }
        }
      }
    } catch (error) {
      errors.push(error instanceof Error ? error.message : "Weather monitoring failed.");
    }
  }

  return res.status(200).json({
    ok: errors.length === 0,
    indexedWatches: watchIds?.length ?? 0,
    activeWatches: watches.length,
    staleWatchesRemoved: staleWatches,
    coordinateGroups: groups.size,
    coordinateGroupsChecked: selectedGroups.length,
    providerQueries,
    matchedAlerts,
    pushesSent,
    errors: errors.slice(0, 20),
    checkedAt: new Date().toISOString()
  });
}
