import type { VercelRequest, VercelResponse } from "@vercel/node";
import { protectPublicEndpoint } from "./_security.js";
import { normalizeFlightNumber } from "./_storage.js";

type FlightAwareAirport = {
  code?: string;
  code_iata?: string;
  code_icao?: string;
  code_lid?: string;
};

type FlightAwareDeparture = {
  ident?: string;
  ident_iata?: string;
  ident_icao?: string;
  fa_flight_id?: string;
  origin?: FlightAwareAirport;
  destination?: FlightAwareAirport;
  scheduled_out?: string;
  estimated_out?: string;
  actual_out?: string;
  gate_origin?: string;
  terminal_origin?: string;
  cancelled?: boolean;
  diverted?: boolean;
};

type ScheduledDeparturesResponse = {
  scheduled_departures?: FlightAwareDeparture[];
  flights?: FlightAwareDeparture[];
  detail?: string;
  title?: string;
};

const airportSearchOrder = ["KATL", "KDFW", "KJFK", "KLAX", "EGLL", "EHAM"];

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() || undefined : undefined;
}

function airportCode(value: FlightAwareAirport | undefined) {
  return clean(value?.code_iata) ?? clean(value?.code_icao) ?? clean(value?.code_lid) ?? clean(value?.code);
}

function aeroAPITimestamp(value: Date) {
  return value.toISOString().replace(/\.\d{3}Z$/, "Z");
}

async function scheduledDepartures(airport: string, now: Date) {
  const apiKey = process.env.FLIGHTAWARE_AEROAPI_KEY?.trim();
  if (!apiKey) throw new Error("FlightAware AeroAPI is not configured.");

  const url = new URL(`/aeroapi/airports/${airport}/flights/scheduled_departures`, "https://aeroapi.flightaware.com");
  url.searchParams.set("start", aeroAPITimestamp(new Date(now.getTime() - 30 * 60_000)));
  url.searchParams.set("end", aeroAPITimestamp(new Date(now.getTime() + 4 * 60 * 60_000)));
  const response = await fetch(url, {
    headers: { Accept: "application/json", "x-apikey": apiKey }
  });
  const body = await response.json().catch(() => undefined) as ScheduledDeparturesResponse | undefined;
  if (!response.ok) {
    throw new Error(body?.detail ?? body?.title ?? `FlightAware returned HTTP ${response.status}.`);
  }
  return body?.scheduled_departures ?? body?.flights ?? [];
}

function assignedGate(flight: FlightAwareDeparture, now: Date) {
  const flightNumber = normalizeFlightNumber(flight.ident_iata ?? flight.ident ?? flight.ident_icao);
  const gate = clean(flight.gate_origin);
  const departureAt = flight.estimated_out ?? flight.scheduled_out ?? flight.actual_out;
  const departureTime = departureAt ? Date.parse(departureAt) : Number.NaN;
  if (!flightNumber || !gate || !departureAt || !Number.isFinite(departureTime)) return undefined;
  if (flight.cancelled || flight.diverted || departureTime < now.getTime() - 45 * 60_000) return undefined;

  return {
    flightNumber,
    providerFlightId: flight.fa_flight_id,
    originAirport: airportCode(flight.origin),
    destinationAirport: airportCode(flight.destination),
    departureAt,
    terminal: clean(flight.terminal_origin),
    gate
  };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!await protectPublicEndpoint(req, res, {
    name: "flight-gate-diagnostic",
    hourlyIPLimit: 20,
    hourlyInstallLimit: 12
  })) return;

  const now = new Date();
  const errors: string[] = [];
  for (const airport of airportSearchOrder) {
    try {
      const result = (await scheduledDepartures(airport, now))
        .flatMap((flight) => assignedGate(flight, now) ?? [])
        .sort((lhs, rhs) => Date.parse(lhs.departureAt) - Date.parse(rhs.departureAt))[0];
      if (result) {
        return res.status(200).json({
          ok: true,
          provider: "FlightAware AeroAPI",
          receivedBy: "Vercel",
          checkedAt: now.toISOString(),
          assignment: result
        });
      }
    } catch (error) {
      errors.push(error instanceof Error ? error.message : `Could not check ${airport}.`);
    }
  }

  return res.status(404).json({
    ok: false,
    provider: "FlightAware AeroAPI",
    receivedBy: "Vercel",
    checkedAt: now.toISOString(),
    error: "No imminent departure with an assigned gate was found at the searched hubs.",
    providerErrors: [...new Set(errors)]
  });
}
