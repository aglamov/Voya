import type { VercelRequest, VercelResponse } from "@vercel/node";

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

  const result = await flightAwareRequest(alertPath(req), {
    method: req.method,
    body: req.method === "POST" || req.method === "PUT" ? JSON.stringify(req.body ?? {}) : undefined
  });

  return res.status(result.status).json(result.data ?? {});
}
