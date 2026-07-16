type RedisValue = string | number;

function redisURL() {
  return (
    process.env.UPSTASH_REDIS_REST_URL
      ?? process.env.UPSTASH_KV_REST_API_URL
      ?? process.env.UPSTASH_REDIS_REST_API_URL
  )?.trim().replace(/\/$/, "");
}

function redisToken() {
  return (
    process.env.UPSTASH_REDIS_REST_TOKEN
      ?? process.env.UPSTASH_KV_REST_API_TOKEN
      ?? process.env.UPSTASH_REDIS_REST_API_TOKEN
  )?.trim();
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

export function flightWatchTargetsKey(flightNumber: string, date?: string) {
  return `voya:flight-watch:${flightWatchKey(flightNumber, date)}:targets`;
}

export type RegisteredFlightTarget = {
  deviceToken: string;
  appInstallId?: string;
  tripId?: string;
  itemId?: string;
};

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

function hashEntries(value: unknown): Array<[string, string]> {
  if (Array.isArray(value)) {
    const entries: Array<[string, string]> = [];
    for (let index = 0; index + 1 < value.length; index += 2) {
      if (typeof value[index] === "string" && typeof value[index + 1] === "string") {
        entries.push([value[index], value[index + 1]]);
      }
    }
    return entries;
  }

  if (value && typeof value === "object") {
    return Object.entries(value).flatMap(([key, item]) => typeof item === "string" ? [[key, item]] : []);
  }

  return [];
}

export async function registeredTargetsForFlight(flightNumber: string, date?: string) {
  const keys = [
    flightWatchTargetsKey(flightNumber, date),
    date ? flightWatchTargetsKey(flightNumber) : undefined
  ].filter(Boolean) as string[];
  const targets = new Map<string, RegisteredFlightTarget>();

  for (const key of keys) {
    const raw = await redisCommand<unknown>(["HGETALL", key]);
    for (const [field, value] of hashEntries(raw)) {
      const token = normalizeDeviceToken(field);
      if (!token || targets.has(token)) continue;
      try {
        const parsed = JSON.parse(value) as Omit<RegisteredFlightTarget, "deviceToken">;
        targets.set(token, { ...parsed, deviceToken: token });
      } catch {
        targets.set(token, { deviceToken: token });
      }
    }
  }

  for (const token of await registeredTokensForFlight(flightNumber, date)) {
    if (!targets.has(token)) {
      targets.set(token, { deviceToken: token });
    }
  }

  return [...targets.values()];
}

export function fallbackPushTokens() {
  return (process.env.VOYA_PUSH_TEST_DEVICE_TOKENS ?? "")
    .split(",")
    .flatMap((token) => {
      const normalized = normalizeDeviceToken(token);
      return normalized ? [normalized] : [];
    });
}
