import type { VercelRequest, VercelResponse } from "@vercel/node";

const uberOAuthEndpoint = "https://login.uber.com/oauth/v2/token";
const uberProductsEndpoint = "https://api.uber.com/v1.2/products";
const uberPriceEstimatesEndpoint = "https://api.uber.com/v1.2/estimates/price";
const uberTimeEstimatesEndpoint = "https://api.uber.com/v1.2/estimates/time";

type UberCheck = {
  ok: boolean;
  status?: number;
  error?: string;
  detail?: unknown;
};

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function clientID() {
  return clean(process.env.UBER_CLIENT_ID);
}

function clientSecret() {
  return clean(process.env.UBER_CLIENT_SECRET);
}

function diagnosticsToken() {
  return clean(process.env.UBER_DIAGNOSTICS_TOKEN);
}

function errorSummary(payload: unknown) {
  if (!payload || typeof payload !== "object") {
    return undefined;
  }

  const record = payload as Record<string, unknown>;
  return record.error_description ?? record.message ?? record.error ?? record.code;
}

async function parsePayload(response: Response) {
  const text = await response.text();
  if (!text) {
    return undefined;
  }

  try {
    return JSON.parse(text) as unknown;
  } catch {
    return text.slice(0, 240);
  }
}

async function getAccessToken(): Promise<UberCheck & { accessToken?: string }> {
  const body = new URLSearchParams({
    client_id: clientID(),
    client_secret: clientSecret(),
    grant_type: "client_credentials",
    scope: "request"
  });

  const response = await fetch(uberOAuthEndpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body
  });
  const payload = await parsePayload(response);

  if (!response.ok || !payload || typeof payload !== "object" || typeof (payload as Record<string, unknown>).access_token !== "string") {
    return {
      ok: false,
      status: response.status,
      error: String(errorSummary(payload) ?? "Uber OAuth token request failed")
    };
  }

  return {
    ok: true,
    status: response.status,
    accessToken: (payload as Record<string, string>).access_token
  };
}

async function uberGet(endpoint: string, accessToken: string, params: Record<string, string>): Promise<UberCheck> {
  const url = new URL(endpoint);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }

  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/json"
    }
  });
  const payload = await parsePayload(response);

  return {
    ok: response.ok,
    status: response.status,
    error: response.ok ? undefined : String(errorSummary(payload) ?? "Uber API request failed"),
    detail: response.ok ? availabilitySummary(payload) : undefined
  };
}

function availabilitySummary(payload: unknown) {
  if (!payload || typeof payload !== "object") {
    return undefined;
  }

  const record = payload as Record<string, unknown>;
  if (Array.isArray(record.products)) {
    return { count: record.products.length };
  }
  if (Array.isArray(record.prices)) {
    return { count: record.prices.length };
  }
  if (Array.isArray(record.times)) {
    return { count: record.times.length };
  }

  return undefined;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const requiredToken = diagnosticsToken();
  if (requiredToken && req.query.token !== requiredToken) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const configured = Boolean(clientID() && clientSecret());
  if (!configured) {
    return res.status(200).json({
      configured: false,
      approved: false,
      checks: {
        oauth: { ok: false, error: "Set UBER_CLIENT_ID and UBER_CLIENT_SECRET in Vercel." }
      }
    });
  }

  try {
    const oauth = await getAccessToken();
    if (!oauth.ok || !oauth.accessToken) {
      return res.status(200).json({
        configured: true,
        approved: false,
        checks: {
          oauth: { ok: oauth.ok, status: oauth.status, error: oauth.error }
        }
      });
    }

    const sharedLocation = {
      latitude: "37.7752315",
      longitude: "-122.418075"
    };
    const route = {
      start_latitude: "37.7752315",
      start_longitude: "-122.418075",
      end_latitude: "37.6213129",
      end_longitude: "-122.3789554"
    };

    const [products, priceEstimates, timeEstimates] = await Promise.all([
      uberGet(uberProductsEndpoint, oauth.accessToken, sharedLocation),
      uberGet(uberPriceEstimatesEndpoint, oauth.accessToken, route),
      uberGet(uberTimeEstimatesEndpoint, oauth.accessToken, sharedLocation)
    ]);

    return res.status(200).json({
      configured: true,
      approved: products.ok || priceEstimates.ok || timeEstimates.ok,
      checks: {
        oauth: { ok: true, status: oauth.status },
        products,
        priceEstimates,
        timeEstimates
      }
    });
  } catch (error) {
    return res.status(200).json({
      configured: true,
      approved: false,
      checks: {
        oauth: {
          ok: false,
          error: error instanceof Error ? error.message : "Uber diagnostics failed"
        }
      }
    });
  }
}
