import { processFlightSignal } from "./_flight-events.js";
import { flightWatchKey, redisCommand, storageConfigured } from "./_storage.js";

const DUE_KEY = "voya:flight-watches:due";
const LOCK_SECONDS = 8 * 60;

type FlightWatchMeta = {
  flightNumber: string;
  date?: string;
  departureAt?: string;
  originAirport?: string;
  destinationAirport?: string;
  flightAwareAlertSubscribed?: string;
  lastProviderEventAt?: string;
  lastCheckedAt?: string;
  lastMonitorError?: string;
};

type FlightAwareOperationalFlight = {
  fa_flight_id?: string;
  ident?: string;
  ident_iata?: string;
  scheduled_out?: string;
  scheduled_in?: string;
  estimated_out?: string;
  estimated_in?: string;
  actual_out?: string;
  actual_in?: string;
  gate_origin?: string;
  gate_destination?: string;
  terminal_origin?: string;
  terminal_destination?: string;
  cancelled?: boolean;
  diverted?: boolean;
  status?: string;
  origin?: { code_iata?: string; code_icao?: string; code_lid?: string };
  destination?: { code_iata?: string; code_icao?: string; code_lid?: string };
};

function metaKey(key: string) {
  return `voya:flight-watch:${key}:meta`;
}

function hashRecord(value: unknown) {
  const record: Record<string, string> = {};
  if (Array.isArray(value)) {
    for (let index = 0; index + 1 < value.length; index += 2) {
      if (typeof value[index] === "string" && typeof value[index + 1] === "string") {
        record[value[index]] = value[index + 1];
      }
    }
  } else if (value && typeof value === "object") {
    for (const [key, item] of Object.entries(value)) {
      if (typeof item === "string") record[key] = item;
    }
  }
  return record;
}

function referenceDeparture(meta: Pick<FlightWatchMeta, "departureAt" | "date">) {
  const direct = meta.departureAt ? Date.parse(meta.departureAt) : Number.NaN;
  if (Number.isFinite(direct)) return direct;
  const fallback = meta.date ? Date.parse(`${meta.date}T12:00:00Z`) : Number.NaN;
  return Number.isFinite(fallback) ? fallback : Date.now() + 12 * 60 * 60 * 1000;
}

export function nextFlightCheckAt(
  meta: Pick<FlightWatchMeta, "departureAt" | "date">,
  subscribed: boolean,
  now = Date.now()
) {
  const hours = (referenceDeparture(meta) - now) / (60 * 60 * 1000);
  let minutes: number;
  if (hours > 48) minutes = subscribed ? 12 * 60 : 6 * 60;
  else if (hours > 24) minutes = subscribed ? 6 * 60 : 3 * 60;
  else if (hours > 4) minutes = subscribed ? 60 : 30;
  else if (hours > -2) minutes = subscribed ? 15 : 10;
  else if (hours > -12) minutes = 30;
  else return undefined;
  return new Date(now + minutes * 60 * 1000).toISOString();
}

export async function scheduleFlightWatch(input: {
  key: string;
  departureAt?: string;
  date?: string;
  subscribed: boolean;
  error?: string;
}) {
  if (!storageConfigured()) return undefined;
  const nextCheckAt = nextFlightCheckAt(input, input.subscribed);
  const state = input.subscribed ? "active" : "degraded";
  await redisCommand([
    "HSET",
    metaKey(input.key),
    "monitorState",
    state,
    "nextCheckAt",
    nextCheckAt ?? "",
    "lastMonitorError",
    input.error ?? ""
  ]);
  if (nextCheckAt) {
    await redisCommand(["ZADD", DUE_KEY, Date.parse(nextCheckAt), input.key]);
  } else {
    await redisCommand(["ZREM", DUE_KEY, input.key]);
  }
  return { state, nextCheckAt, fallbackPolling: true };
}

async function readMeta(key: string): Promise<FlightWatchMeta | undefined> {
  const raw = await redisCommand<unknown>(["HGETALL", metaKey(key)]);
  const record = hashRecord(raw);
  if (!record.flightNumber) return undefined;
  return record as FlightWatchMeta;
}

function dateWindow(date: string) {
  const start = new Date(`${date}T00:00:00Z`);
  const end = new Date(start.getTime() + 48 * 60 * 60 * 1000);
  start.setUTCDate(start.getUTCDate() - 1);
  return { start: start.toISOString(), end: end.toISOString() };
}

function serviceDate(flight: FlightAwareOperationalFlight) {
  return (flight.scheduled_out ?? flight.estimated_out ?? flight.actual_out)?.slice(0, 10);
}

function operationalDeparture(flight: FlightAwareOperationalFlight) {
  const value = flight.scheduled_out ?? flight.estimated_out ?? flight.actual_out;
  const parsed = value ? Date.parse(value) : Number.NaN;
  return Number.isFinite(parsed) ? parsed : undefined;
}

function selectOperationalFlight(candidates: FlightAwareOperationalFlight[], meta: FlightWatchMeta) {
  const airportMatches = (
    airport: FlightAwareOperationalFlight["origin"],
    expected: string | undefined
  ) => !expected || [airport?.code_iata, airport?.code_icao, airport?.code_lid]
    .some((value) => value?.trim().toUpperCase() === expected.trim().toUpperCase());
  const routed = candidates.filter((flight) =>
    airportMatches(flight.origin, meta.originAirport)
      && airportMatches(flight.destination, meta.destinationAirport)
  );
  const exact = meta.date ? routed.find((flight) => serviceDate(flight) === meta.date) : routed[0];
  if (exact) return exact;
  const target = meta.departureAt ? Date.parse(meta.departureAt) : Number.NaN;
  if (!Number.isFinite(target)) return undefined;
  return routed
    .flatMap((flight) => {
      const departure = operationalDeparture(flight);
      return departure === undefined ? [] : [{ flight, distance: Math.abs(departure - target) }];
    })
    .filter((candidate) => candidate.distance <= 18 * 60 * 60 * 1000)
    .sort((lhs, rhs) => lhs.distance - rhs.distance)[0]?.flight;
}

async function fetchOperationalFlight(meta: FlightWatchMeta) {
  const apiKey = process.env.FLIGHTAWARE_AEROAPI_KEY?.trim();
  if (!apiKey) throw new Error("FlightAware AeroAPI is not configured.");
  const params = new URLSearchParams();
  if (meta.date) {
    const window = dateWindow(meta.date);
    params.set("start", window.start);
    params.set("end", window.end);
  }
  const response = await fetch(
    `https://aeroapi.flightaware.com/aeroapi/flights/${encodeURIComponent(meta.flightNumber)}?${params.toString()}`,
    { headers: { Accept: "application/json", "x-apikey": apiKey } }
  );
  const body = await response.json().catch(() => undefined) as { flights?: FlightAwareOperationalFlight[]; title?: string; detail?: string } | undefined;
  if (!response.ok) throw new Error(body?.detail ?? body?.title ?? `FlightAware returned HTTP ${response.status}.`);
  const candidates = body?.flights ?? [];
  return selectOperationalFlight(candidates, meta);
}

function monitorEventType(flight: FlightAwareOperationalFlight) {
  if (flight.cancelled) return "cancelled";
  if (flight.diverted) return "diverted";
  return "operational_poll";
}

export async function fetchCanonicalFlightSignal(input: {
  flightNumber: string;
  date?: string;
  departureAt?: string;
  originAirport?: string;
  destinationAirport?: string;
  source: "webhook" | "poll";
  providerEventType?: string;
  now?: Date;
}) {
  const flight = await fetchOperationalFlight({
    flightNumber: input.flightNumber,
    date: input.date,
    departureAt: input.departureAt,
    originAirport: input.originAirport,
    destinationAirport: input.destinationAirport
  });
  if (!flight) return undefined;
  const receivedAt = (input.now ?? new Date()).toISOString();
  return {
    provider: "flightaware" as const,
    source: input.source,
    eventType: input.providerEventType ?? monitorEventType(flight),
    providerFlightId: flight.fa_flight_id,
    flightNumber: input.flightNumber,
    flightDate: input.date,
    headline: `${input.flightNumber}: verified operational update`,
    detail: flight.status,
    gate: {
      departureTerminal: flight.terminal_origin,
      departureGate: flight.gate_origin,
      arrivalTerminal: flight.terminal_destination,
      arrivalGate: flight.gate_destination
    },
    timing: {
      scheduledDepartureAt: flight.scheduled_out,
      scheduledArrivalAt: flight.scheduled_in,
      estimatedDepartureAt: flight.estimated_out,
      estimatedArrivalAt: flight.estimated_in,
      actualDepartureAt: flight.actual_out,
      actualArrivalAt: flight.actual_in
    },
    receivedAt
  };
}

async function monitorOne(key: string, now = new Date()) {
  const lock = await redisCommand<string | null>([
    "SET",
    `voya:flight-watch-monitor-lock:${key}`,
    now.toISOString(),
    "EX",
    LOCK_SECONDS,
    "NX"
  ]);
  if (lock !== "OK") return { key, skipped: true, reason: "already_running" };

  const meta = await readMeta(key);
  if (!meta) {
    await redisCommand(["ZREM", DUE_KEY, key]);
    return { key, skipped: true, reason: "missing_watch" };
  }
  const subscribed = meta.flightAwareAlertSubscribed === "1";
  try {
    const signal = await fetchCanonicalFlightSignal({
      flightNumber: meta.flightNumber,
      date: meta.date,
      departureAt: meta.departureAt,
      originAirport: meta.originAirport,
      destinationAirport: meta.destinationAirport,
      source: "poll",
      now
    });
    if (!signal) throw new Error("No date-matched operational flight was returned.");
    const processing = await processFlightSignal(signal);
    const departureAt = signal.timing.scheduledDepartureAt ?? signal.timing.estimatedDepartureAt ?? meta.departureAt;
    const nextCheckAt = nextFlightCheckAt({ departureAt, date: meta.date }, subscribed, now.getTime());
    await redisCommand([
      "HSET",
      metaKey(key),
      "monitorState",
      "active",
      "lastCheckedAt",
      signal.receivedAt,
      "lastMonitorError",
      "",
      "nextCheckAt",
      nextCheckAt ?? ""
    ]);
    if (nextCheckAt) await redisCommand(["ZADD", DUE_KEY, Date.parse(nextCheckAt), key]);
    else await redisCommand(["ZREM", DUE_KEY, key]);
    return { key, checked: true, event: processing.event?.type, nextCheckAt };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Flight monitor failed.";
    const nextCheckAt = new Date(now.getTime() + 30 * 60 * 1000).toISOString();
    await redisCommand([
      "HSET",
      metaKey(key),
      "monitorState",
      "degraded",
      "lastCheckedAt",
      now.toISOString(),
      "lastMonitorError",
      message,
      "nextCheckAt",
      nextCheckAt
    ]);
    await redisCommand(["ZADD", DUE_KEY, Date.parse(nextCheckAt), key]);
    return { key, checked: false, error: message, nextCheckAt };
  } finally {
    await redisCommand(["DEL", `voya:flight-watch-monitor-lock:${key}`]);
  }
}

export async function processDueFlightWatches(limit = 12) {
  if (!storageConfigured()) return { due: 0, checked: 0, events: 0, errors: ["Redis is not configured."] };
  const keys = await redisCommand<string[]>([
    "ZRANGEBYSCORE",
    DUE_KEY,
    0,
    Date.now(),
    "LIMIT",
    0,
    Math.max(1, Math.min(limit, 30))
  ]);
  const results = [];
  for (const key of keys ?? []) results.push(await monitorOne(key));
  return {
    due: keys?.length ?? 0,
    checked: results.filter((result) => "checked" in result && result.checked).length,
    events: results.filter((result) => "event" in result && Boolean(result.event)).length,
    errors: results.flatMap((result) => "error" in result && result.error ? [result.error] : []),
    results
  };
}

export async function flightWatchMonitoringStatus(flightNumber: string, date?: string) {
  if (!storageConfigured()) return undefined;
  const key = flightWatchKey(flightNumber, date);
  const meta = await readMeta(key);
  if (!meta) return undefined;
  const record = meta as FlightWatchMeta & Record<string, string | undefined>;
  return {
    state: record.monitorState || (record.flightAwareAlertSubscribed === "1" ? "active" : "degraded"),
    fallbackPolling: true,
    nextCheckAt: record.nextCheckAt || undefined,
    lastCheckedAt: record.lastCheckedAt || undefined,
    lastProviderEventAt: record.lastProviderEventAt || undefined,
    lastEventType: record.lastTravelEventType || undefined,
    lastError: record.lastMonitorError || undefined
  };
}
