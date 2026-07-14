import type { VercelRequest, VercelResponse } from "@vercel/node";
import { timingSafeEqual } from "node:crypto";

function configuredManagementSecret() {
  return process.env.VOYA_ADMIN_SECRET?.trim()
    ?? process.env.FLIGHTAWARE_ALERT_WEBHOOK_SECRET?.trim();
}

function firstHeader(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function requestManagementSecret(req: VercelRequest) {
  const querySecret = typeof req.query.secret === "string" ? req.query.secret.trim() : undefined;
  const headerSecret = firstHeader(req.headers["x-voya-admin-secret"])?.trim();
  const authorization = firstHeader(req.headers.authorization)?.trim();
  const bearerSecret = authorization?.toLowerCase().startsWith("bearer ")
    ? authorization.slice("bearer ".length).trim()
    : undefined;

  return querySecret || headerSecret || bearerSecret;
}

function secretsMatch(actual: string | undefined, expected: string) {
  if (!actual) {
    return false;
  }

  const encoder = new TextEncoder();
  const actualBuffer = encoder.encode(actual);
  const expectedBuffer = encoder.encode(expected);
  return actualBuffer.length === expectedBuffer.length && timingSafeEqual(actualBuffer, expectedBuffer);
}

function authorizeManagement(req: VercelRequest) {
  const expected = configuredManagementSecret();
  return !expected || secretsMatch(requestManagementSecret(req), expected);
}

function flightAwareApiKey() {
  return process.env.FLIGHTAWARE_AEROAPI_KEY?.trim();
}

async function flightAwareRequest(path: string, init: RequestInit = {}) {
  const apiKey = flightAwareApiKey();
  if (!apiKey) {
    return {
      connected: false as const,
      status: 503,
      data: { error: "Set FLIGHTAWARE_AEROAPI_KEY to manage FlightAware alert subscriptions." }
    };
  }

  const response = await fetch(`https://aeroapi.flightaware.com/aeroapi${path}`, {
    ...init,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      "x-apikey": apiKey,
      ...(init.headers ?? {})
    }
  });
  const data = await response.json().catch(() => undefined);

  return {
    connected: true as const,
    status: response.status,
    data
  };
}

function alertPath(req: VercelRequest) {
  const endpoint = req.query.endpoint === "true" || req.query.endpoint === "1";
  if (endpoint) {
    return "/alerts/endpoint";
  }

  const alertId = typeof req.query.alertId === "string" ? req.query.alertId.trim() : "";
  return alertId ? `/alerts/${encodeURIComponent(alertId)}` : "/alerts";
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET" && req.method !== "POST" && req.method !== "PUT" && req.method !== "DELETE") {
    res.setHeader("Allow", "GET, POST, PUT, DELETE");
    return res.status(405).json({ error: "Method not allowed" });
  }

  if (!authorizeManagement(req)) {
    return res.status(401).json({ error: "Unauthorized FlightAware alert management request." });
  }

  const result = await flightAwareRequest(alertPath(req), {
    method: req.method,
    body: req.method === "POST" || req.method === "PUT" ? JSON.stringify(req.body ?? {}) : undefined
  });

  return res.status(result.status).json(result.data ?? {});
}
