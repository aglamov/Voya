type RedisValue = string | number;

function redisURL() {
  return process.env.UPSTASH_REDIS_REST_URL?.trim().replace(/\/$/, "");
}

function redisToken() {
  return process.env.UPSTASH_REDIS_REST_TOKEN?.trim();
}

export function storageConfigured() {
  return Boolean(redisURL() && redisToken());
}

export async function redisCommand<T = unknown>(command: RedisValue[]) {
  const url = redisURL();
  const token = redisToken();
  if (!url || !token) {
    return undefined;
  }

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(command)
  });
  const data = await response.json().catch(() => undefined) as { result?: T; error?: string } | undefined;
  if (!response.ok || data?.error) {
    throw new Error(data?.error ?? `Redis command failed with HTTP ${response.status}`);
  }

  return data?.result;
}

export function normalizeDeviceToken(value: unknown) {
  if (typeof value !== "string") {
    return undefined;
  }

  const token = value.replace(/[<>\s]/g, "").toLowerCase();
  return /^[a-f0-9]{64,}$/.test(token) ? token : undefined;
}

export function normalizeFlightNumber(value: unknown) {
  if (typeof value !== "string") {
    return undefined;
  }

  const flightNumber = value.replace(/\s+/g, "").toUpperCase();
  return /^[A-Z0-9]{2,4}\d{1,5}[A-Z]?$/.test(flightNumber) ? flightNumber : undefined;
}

export function normalizeFlightDate(value: unknown) {
  if (typeof value !== "string") {
    return undefined;
  }

  const date = value.slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(date) ? date : undefined;
}

export function flightWatchKey(flightNumber: string, date?: string) {
  return `${flightNumber}:${date ?? "any"}`;
}

export async function registeredTokensForFlight(flightNumber: string, date?: string) {
  const keys = [
    `voya:flight-watch:${flightWatchKey(flightNumber, date)}:devices`,
    date ? `voya:flight-watch:${flightWatchKey(flightNumber)}:devices` : undefined
  ].filter(Boolean) as string[];
  const tokens = new Set<string>();

  for (const key of keys) {
    const members = await redisCommand<string[]>(["SMEMBERS", key]);
    for (const member of members ?? []) {
      const token = normalizeDeviceToken(member);
      if (token) {
        tokens.add(token);
      }
    }
  }

  return [...tokens];
}

export function fallbackPushTokens() {
  return (process.env.VOYA_PUSH_TEST_DEVICE_TOKENS ?? "")
    .split(",")
    .flatMap((token) => {
      const normalized = normalizeDeviceToken(token);
      return normalized ? [normalized] : [];
    });
}
