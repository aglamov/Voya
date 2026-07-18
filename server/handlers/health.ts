import { timingSafeEqual } from "node:crypto";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { redisCommand, storageConfigured } from "../../api/_storage.js";

function firstHeader(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function suppliedSecret(req: VercelRequest) {
  const authorization = firstHeader(req.headers.authorization)?.trim();
  return authorization?.toLowerCase().startsWith("bearer ")
    ? authorization.slice("bearer ".length).trim()
    : firstHeader(req.headers["x-voya-admin-secret"])?.trim();
}

function authorized(req: VercelRequest) {
  const expected = process.env.VOYA_ADMIN_SECRET?.trim();
  const actual = suppliedSecret(req);
  if (!expected || !actual) return false;
  const encoder = new TextEncoder();
  const lhs = encoder.encode(actual);
  const rhs = encoder.encode(expected);
  return lhs.length === rhs.length && timingSafeEqual(lhs, rhs);
}

function configured(...names: string[]) {
  return names.some((name) => Boolean(process.env[name]?.trim()));
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader("Cache-Control", "no-store");
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!process.env.VOYA_ADMIN_SECRET?.trim()) {
    return res.status(503).json({ error: "Admin diagnostics are not configured." });
  }
  if (!authorized(req)) {
    return res.status(401).json({ error: "Unauthorized diagnostics request." });
  }

  const checks = {
    openAI: configured("OPENAI_API_KEY"),
    openWeather: configured("OPENWEATHER_API_KEY"),
    flightAware: configured("FLIGHTAWARE_AEROAPI_KEY"),
    googleRoutes: configured("GOOGLE_ROUTES_API_KEY", "GOOGLE_MAPS_API_KEY"),
    ticketmaster: configured("TICKETMASTER_API_KEY", "TICKETMASTER_CONSUMER_KEY"),
    redis: storageConfigured(),
    apns: configured("APNS_KEY_ID") && configured("APNS_TEAM_ID") && configured("APNS_PRIVATE_KEY") && configured("APNS_BUNDLE_ID"),
    apnsProduction: process.env.APNS_ENV?.trim() === "production",
    cron: configured("CRON_SECRET", "WEATHER_MONITOR_SECRET"),
    clientProtection: configured("VOYA_CLIENT_API_KEY"),
    flightAwareWebhook: configured("FLIGHTAWARE_ALERT_WEBHOOK_SECRET"),
    publicBaseURL: configured("VOYA_API_PUBLIC_BASE_URL"),
    agentQueue: configured("QSTASH_TOKEN"),
    agentWorker: configured("AGENT_WORKER_SECRET"),
    agentMonitor: configured("AGENT_MONITOR_SECRET", "CRON_SECRET")
  };
  let redisReachable = false;
  if (checks.redis) {
    try {
      redisReachable = await redisCommand<string>(["PING"]) === "PONG";
    } catch {
      redisReachable = false;
    }
  }

  const requiredChecks = Object.entries(checks)
    .filter(([name]) => name !== "clientProtection")
    .map(([, value]) => value);
  const ready = requiredChecks.every(Boolean) && redisReachable;
  return res.status(ready ? 200 : 503).json({
    ready,
    environment: process.env.VERCEL_ENV ?? "local",
    checks: { ...checks, redisReachable },
    checkedAt: new Date().toISOString()
  });
}
