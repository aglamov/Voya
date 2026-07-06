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
};

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : undefined;
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
      warning: "Set UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN to persist flight watches."
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

  return res.status(202).json({
    accepted: true,
    stored: true,
    flightKey: key,
    deviceLinked: Boolean(deviceToken),
    updatedAt: now
  });
}
