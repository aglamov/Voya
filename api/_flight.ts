import { z } from "zod";

export const flightLookupSchema = z.object({
  flightNumber: z.string().min(2).max(16),
  date: z.string().min(8).max(32).optional(),
  originAirport: z.string().min(3).max(4).optional(),
  destinationAirport: z.string().min(3).max(4).optional()
});

export type FlightLookup = z.infer<typeof flightLookupSchema>;

export type FlightSnapshotStatus =
  | "scheduled"
  | "boarding"
  | "delayed"
  | "departed"
  | "arrived"
  | "cancelled"
  | "diverted"
  | "unknown";

export type FlightSnapshot = {
  provider: "aviationstack" | "flightaware";
  providerFlightId?: string;
  providerStatus?: string;
  airlineName?: string;
  airlineCode?: string;
  flightNumber: string;
  flightIata?: string;
  flightIcao?: string;
  operatingAirlineCode?: string;
  codeshare?: {
    airlineName?: string;
    airlineCode?: string;
    flightNumber?: string;
    flightIata?: string;
    flightIcao?: string;
  };
  flightDate?: string;
  originAirport?: string;
  originAirportIcao?: string;
  originAirportName?: string;
  originTimezone?: string;
  destinationAirport?: string;
  destinationAirportIcao?: string;
  destinationAirportName?: string;
  destinationTimezone?: string;
  scheduledDepartureAt?: string;
  scheduledArrivalAt?: string;
  estimatedDepartureAt?: string;
  estimatedArrivalAt?: string;
  actualDepartureAt?: string;
  actualArrivalAt?: string;
  estimatedDepartureRunwayAt?: string;
  actualDepartureRunwayAt?: string;
  estimatedArrivalRunwayAt?: string;
  actualArrivalRunwayAt?: string;
  departureTerminal?: string;
  departureGate?: string;
  departureDelayMinutes?: number;
  arrivalTerminal?: string;
  arrivalGate?: string;
  arrivalDelayMinutes?: number;
  baggageClaim?: string;
  aircraftType?: string;
  aircraftRegistration?: string;
  aircraftIata?: string;
  aircraftIcao?: string;
  aircraftIcao24?: string;
  status: FlightSnapshotStatus;
  delayMinutes?: number;
  cancellationReason?: string;
  diversionAirport?: string;
  position?: {
    lat: number;
    lon: number;
    altitudeFeet?: number;
    groundspeedKnots?: number;
    groundspeedKmh?: number;
    verticalSpeed?: number;
    headingDegrees?: number;
    isGround?: boolean;
    updatedAt?: string;
  };
  onTimeProbability?: number;
  confidence: number;
  sourceUpdatedAt?: string;
  fetchedAt: string;
};

export type FlightStatusResponse = {
  query: FlightLookup;
  validation: {
    state: "validated" | "not_found" | "provider_not_connected" | "provider_error";
    confidence: number;
    reasons: string[];
  };
  snapshot?: FlightSnapshot;
  delayStats: {
    headline: string;
    delayMinutes?: number;
    onTimeProbability?: number;
    reasons: string[];
  };
  gate: {
    departureTerminal?: string;
    departureGate?: string;
    arrivalTerminal?: string;
    arrivalGate?: string;
    baggageClaim?: string;
    changed: boolean;
    guidance: string[];
  };
  aircraft: {
    type?: string;
    registration?: string;
    position?: FlightSnapshot["position"];
  };
  nextActions: string[];
  provider: {
    name: "aviationstack" | "FlightAware AeroAPI";
    connected: boolean;
    attribution: string;
  };
  warnings: string[];
};

type FlightAwareAirport = {
  code?: string;
  code_iata?: string;
  code_icao?: string;
  terminal?: string;
  gate?: string;
  baggage_claim?: string;
  delay?: number;
};

type FlightAwareFlight = {
  fa_flight_id?: string;
  ident?: string;
  ident_iata?: string;
  operator?: string;
  operator_iata?: string;
  flight_number?: string;
  registration?: string;
  aircraft_type?: string;
  status?: string;
  cancelled?: boolean;
  diverted?: boolean;
  origin?: FlightAwareAirport;
  destination?: FlightAwareAirport;
  scheduled_out?: string;
  scheduled_off?: string;
  scheduled_on?: string;
  scheduled_in?: string;
  estimated_out?: string;
  estimated_off?: string;
  estimated_on?: string;
  estimated_in?: string;
  actual_out?: string;
  actual_off?: string;
  actual_on?: string;
  actual_in?: string;
  predicted_out?: string;
  predicted_off?: string;
  predicted_on?: string;
  predicted_in?: string;
};

type FlightAwareFlightsResponse = {
  flights?: FlightAwareFlight[];
};

type FlightAwareTrackPoint = {
  timestamp?: string;
  latitude?: number;
  longitude?: number;
  altitude?: number;
  groundspeed?: number;
  heading?: number;
};

type FlightAwareTrackResponse = {
  positions?: FlightAwareTrackPoint[];
};

type AviationstackFlight = {
  flight_date?: string;
  flight_status?: string;
  departure?: {
    airport?: string;
    timezone?: string;
    iata?: string;
    icao?: string;
    terminal?: string;
    gate?: string;
    delay?: number;
    scheduled?: string;
    estimated?: string;
    actual?: string;
    estimated_runway?: string;
    actual_runway?: string;
  };
  arrival?: {
    airport?: string;
    timezone?: string;
    iata?: string;
    icao?: string;
    terminal?: string;
    gate?: string;
    baggage?: string;
    delay?: number;
    scheduled?: string;
    estimated?: string;
    actual?: string;
    estimated_runway?: string;
    actual_runway?: string;
  };
  airline?: {
    name?: string;
    iata?: string;
    icao?: string;
  };
  flight?: {
    number?: string;
    iata?: string;
    icao?: string;
    codeshared?: {
      airline_name?: string;
      airline_iata?: string;
      airline_icao?: string;
      flight_number?: string;
      flight_iata?: string;
      flight_icao?: string;
    };
  };
  aircraft?: {
    registration?: string;
    iata?: string;
    icao?: string;
    icao24?: string;
  };
  live?: {
    updated?: string;
    latitude?: number;
    longitude?: number;
    altitude?: number;
    direction?: number;
    speed_horizontal?: number;
    speed_vertical?: number;
    is_ground?: boolean;
  };
};

type AviationstackResponse = {
  data?: AviationstackFlight[];
  error?: {
    code?: string;
    message?: string;
  };
};

function cleanFlightNumber(value: string) {
  return value.replace(/\s+/g, "").toUpperCase();
}

function airportCode(value?: FlightAwareAirport) {
  return value?.code_iata ?? value?.code ?? value?.code_icao;
}

function minutesBetween(later?: string, earlier?: string) {
  if (!later || !earlier) {
    return undefined;
  }

  const laterDate = new Date(later);
  const earlierDate = new Date(earlier);
  if (Number.isNaN(laterDate.getTime()) || Number.isNaN(earlierDate.getTime())) {
    return undefined;
  }

  return Math.round((laterDate.getTime() - earlierDate.getTime()) / 60000);
}

function statusFromFlightAware(flight: FlightAwareFlight): FlightSnapshotStatus {
  const status = flight.status?.toLowerCase() ?? "";
  if (flight.cancelled || status.includes("cancel")) {
    return "cancelled";
  }
  if (flight.diverted || status.includes("divert")) {
    return "diverted";
  }
  if (flight.actual_in || flight.actual_on || status.includes("arriv")) {
    return "arrived";
  }
  if (flight.actual_off || flight.actual_out || status.includes("depart")) {
    return "departed";
  }
  if (status.includes("delay")) {
    return "delayed";
  }
  if (status.includes("board")) {
    return "boarding";
  }
  if (flight.scheduled_out || flight.scheduled_off) {
    return "scheduled";
  }

  return "unknown";
}

function statusFromAviationstack(status?: string): FlightSnapshotStatus {
  switch (status?.toLowerCase()) {
    case "scheduled":
      return "scheduled";
    case "active":
      return "departed";
    case "landed":
      return "arrived";
    case "cancelled":
      return "cancelled";
    case "incident":
      return "unknown";
    case "diverted":
      return "diverted";
    default:
      return "unknown";
  }
}

function onTimeProbability(status: FlightSnapshotStatus, delayMinutes?: number) {
  if (status === "cancelled" || status === "diverted") {
    return 0;
  }
  if (delayMinutes == null) {
    return status === "scheduled" ? 0.72 : undefined;
  }
  if (delayMinutes <= 5) {
    return 0.86;
  }
  if (delayMinutes <= 15) {
    return 0.68;
  }
  if (delayMinutes <= 45) {
    return 0.42;
  }
  return 0.2;
}

function normalizeAviationstackFlight(flight: AviationstackFlight, fallbackFlightNumber: string): FlightSnapshot {
  const status = statusFromAviationstack(flight.flight_status);
  const delayMinutes = flight.departure?.delay ?? flight.arrival?.delay;

  return {
    provider: "aviationstack",
    providerFlightId: flight.flight?.iata ?? flight.flight?.icao ?? fallbackFlightNumber,
    providerStatus: flight.flight_status,
    airlineName: flight.airline?.name,
    airlineCode: flight.airline?.iata ?? flight.airline?.icao,
    flightNumber: flight.flight?.iata ?? flight.flight?.icao ?? flight.flight?.number ?? fallbackFlightNumber,
    flightIata: flight.flight?.iata,
    flightIcao: flight.flight?.icao,
    operatingAirlineCode: flight.airline?.iata ?? flight.airline?.icao,
    codeshare: flight.flight?.codeshared
      ? {
          airlineName: flight.flight.codeshared.airline_name,
          airlineCode: flight.flight.codeshared.airline_iata ?? flight.flight.codeshared.airline_icao,
          flightNumber: flight.flight.codeshared.flight_number,
          flightIata: flight.flight.codeshared.flight_iata,
          flightIcao: flight.flight.codeshared.flight_icao
        }
      : undefined,
    flightDate: flight.flight_date,
    originAirport: flight.departure?.iata,
    originAirportIcao: flight.departure?.icao,
    originAirportName: flight.departure?.airport,
    originTimezone: flight.departure?.timezone,
    destinationAirport: flight.arrival?.iata,
    destinationAirportIcao: flight.arrival?.icao,
    destinationAirportName: flight.arrival?.airport,
    destinationTimezone: flight.arrival?.timezone,
    scheduledDepartureAt: flight.departure?.scheduled,
    scheduledArrivalAt: flight.arrival?.scheduled,
    estimatedDepartureAt: flight.departure?.estimated,
    estimatedArrivalAt: flight.arrival?.estimated,
    actualDepartureAt: flight.departure?.actual,
    actualArrivalAt: flight.arrival?.actual,
    estimatedDepartureRunwayAt: flight.departure?.estimated_runway,
    actualDepartureRunwayAt: flight.departure?.actual_runway,
    estimatedArrivalRunwayAt: flight.arrival?.estimated_runway,
    actualArrivalRunwayAt: flight.arrival?.actual_runway,
    departureTerminal: flight.departure?.terminal,
    departureGate: flight.departure?.gate,
    departureDelayMinutes: flight.departure?.delay,
    arrivalTerminal: flight.arrival?.terminal,
    arrivalGate: flight.arrival?.gate,
    arrivalDelayMinutes: flight.arrival?.delay,
    baggageClaim: flight.arrival?.baggage,
    aircraftType: flight.aircraft?.iata ?? flight.aircraft?.icao,
    aircraftRegistration: flight.aircraft?.registration,
    aircraftIata: flight.aircraft?.iata,
    aircraftIcao: flight.aircraft?.icao,
    aircraftIcao24: flight.aircraft?.icao24,
    status,
    delayMinutes,
    position: flight.live?.latitude != null && flight.live.longitude != null
      ? {
          lat: flight.live.latitude,
          lon: flight.live.longitude,
          altitudeFeet: flight.live.altitude,
          groundspeedKmh: flight.live.speed_horizontal,
          verticalSpeed: flight.live.speed_vertical,
          headingDegrees: flight.live.direction,
          isGround: flight.live.is_ground,
          updatedAt: flight.live.updated
        }
      : undefined,
    onTimeProbability: onTimeProbability(status, delayMinutes),
    confidence: 0.84,
    sourceUpdatedAt: flight.live?.updated ?? flight.departure?.actual ?? flight.departure?.estimated ?? flight.departure?.scheduled,
    fetchedAt: new Date().toISOString()
  };
}

function normalizeFlightAwareFlight(flight: FlightAwareFlight, fallbackFlightNumber: string): FlightSnapshot {
  const status = statusFromFlightAware(flight);
  const scheduledDepartureAt = flight.scheduled_out ?? flight.scheduled_off;
  const estimatedDepartureAt = flight.estimated_out ?? flight.predicted_out ?? flight.estimated_off ?? flight.predicted_off;
  const delayMinutes = minutesBetween(estimatedDepartureAt, scheduledDepartureAt) ?? flight.origin?.delay;

  return {
    provider: "flightaware",
    providerFlightId: flight.fa_flight_id,
    airlineCode: flight.operator_iata ?? flight.operator,
    flightNumber: flight.ident_iata ?? flight.ident ?? fallbackFlightNumber,
    operatingAirlineCode: flight.operator_iata ?? flight.operator,
    originAirport: airportCode(flight.origin),
    destinationAirport: airportCode(flight.destination),
    scheduledDepartureAt,
    scheduledArrivalAt: flight.scheduled_in ?? flight.scheduled_on,
    estimatedDepartureAt,
    estimatedArrivalAt: flight.estimated_in ?? flight.predicted_in ?? flight.estimated_on ?? flight.predicted_on,
    actualDepartureAt: flight.actual_out ?? flight.actual_off,
    actualArrivalAt: flight.actual_in ?? flight.actual_on,
    departureTerminal: flight.origin?.terminal,
    departureGate: flight.origin?.gate,
    arrivalTerminal: flight.destination?.terminal,
    arrivalGate: flight.destination?.gate,
    baggageClaim: flight.destination?.baggage_claim,
    aircraftType: flight.aircraft_type,
    aircraftRegistration: flight.registration,
    status,
    delayMinutes,
    onTimeProbability: onTimeProbability(status, delayMinutes),
    confidence: 0.9,
    sourceUpdatedAt: flight.actual_out ?? flight.estimated_out ?? flight.scheduled_out,
    fetchedAt: new Date().toISOString()
  };
}

function routeMatches(snapshot: FlightSnapshot, lookup: FlightLookup) {
  const originMatches = !lookup.originAirport || snapshot.originAirport === lookup.originAirport.toUpperCase();
  const destinationMatches = !lookup.destinationAirport || snapshot.destinationAirport === lookup.destinationAirport.toUpperCase();

  return originMatches && destinationMatches;
}

function lookupWindow(date?: string) {
  const center = date ? new Date(date) : new Date();
  if (Number.isNaN(center.getTime())) {
    return undefined;
  }

  const start = new Date(center);
  start.setUTCHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 2);

  return { start: start.toISOString(), end: end.toISOString() };
}

async function flightAwareFetch(path: string) {
  const apiKey = process.env.FLIGHTAWARE_AEROAPI_KEY;
  if (!apiKey) {
    return { connected: false as const };
  }

  const response = await fetch(`https://aeroapi.flightaware.com/aeroapi${path}`, {
    headers: {
      Accept: "application/json",
      "x-apikey": apiKey
    }
  });

  if (!response.ok) {
    return { connected: true as const, ok: false as const, status: response.status };
  }

  return { connected: true as const, ok: true as const, data: await response.json() };
}

async function aviationstackFetch(lookup: FlightLookup) {
  const apiKey = process.env.AVIATIONSTACK_API_KEY;
  if (!apiKey) {
    return { connected: false as const };
  }

  const url = new URL("http://api.aviationstack.com/v1/flights");
  url.searchParams.set("access_key", apiKey);
  url.searchParams.set("limit", "10");
  url.searchParams.set("flight_iata", cleanFlightNumber(lookup.flightNumber));
  if (lookup.date) {
    url.searchParams.set("flight_date", lookup.date.slice(0, 10));
  }
  if (lookup.originAirport) {
    url.searchParams.set("dep_iata", lookup.originAirport.toUpperCase());
  }
  if (lookup.destinationAirport) {
    url.searchParams.set("arr_iata", lookup.destinationAirport.toUpperCase());
  }

  const response = await fetch(url);
  if (!response.ok) {
    return { connected: true as const, ok: false as const, status: response.status };
  }

  const data = await response.json() as AviationstackResponse;
  if (data.error) {
    return { connected: true as const, ok: false as const, status: 200, error: data.error.message ?? data.error.code };
  }

  return { connected: true as const, ok: true as const, data };
}

async function fetchTrack(snapshot: FlightSnapshot) {
  if (!snapshot.providerFlightId) {
    return undefined;
  }

  const result = await flightAwareFetch(`/flights/${encodeURIComponent(snapshot.providerFlightId)}/track`);
  if (!result.connected || !result.ok) {
    return undefined;
  }

  const data = result.data as FlightAwareTrackResponse;
  const point = data.positions?.at(-1);
  if (point?.latitude == null || point.longitude == null) {
    return undefined;
  }

  return {
    lat: point.latitude,
    lon: point.longitude,
    altitudeFeet: point.altitude,
    groundspeedKnots: point.groundspeed,
    headingDegrees: point.heading,
    updatedAt: point.timestamp
  };
}

function gateGuidance(snapshot?: FlightSnapshot) {
  if (!snapshot) {
    return ["Validate the flight first, then refresh gate and terminal guidance closer to departure."];
  }

  const guidance = [
    snapshot.departureTerminal
      ? `Go to terminal ${snapshot.departureTerminal} and follow airport signs after security.`
      : "Terminal is not available yet; check the airport displays and refresh closer to departure.",
    snapshot.departureGate
      ? `Departure gate is ${snapshot.departureGate}.`
      : "Gate is often posted 1-3 hours before departure and can change.",
    "Indoor turn-by-turn airport navigation needs an airport map or indoor maps provider, not a flight-status feed alone."
  ];

  return guidance;
}

function nextActions(snapshot?: FlightSnapshot) {
  if (!snapshot) {
    return ["Connect a live flight-status provider or retry when the provider is available."];
  }

  if (snapshot.status === "cancelled") {
    return ["Contact the airline or booking source for rebooking options.", "Keep the imported confirmation visible for support."];
  }

  if (snapshot.status === "delayed" || (snapshot.delayMinutes ?? 0) >= 15) {
    return ["Keep monitoring for a revised departure time or gate change.", "If you have a connection, re-check the connection buffer."];
  }

  if (!snapshot.departureGate) {
    return ["Refresh closer to departure for gate assignment.", "Use terminal signs and airport displays as the final source at the airport."];
  }

  return ["Proceed using the current terminal and gate, and keep alerts enabled for changes."];
}

function delayHeadline(snapshot?: FlightSnapshot) {
  if (!snapshot) {
    return "Flight status provider is not connected.";
  }

  if (snapshot.status === "cancelled") {
    return "Flight is cancelled.";
  }

  const delay = snapshot.delayMinutes;
  if (delay == null) {
    return "No delay estimate available yet.";
  }

  if (delay <= 5) {
    return "Looks close to schedule.";
  }

  return `Estimated delay is about ${delay} minutes.`;
}

export async function getFlightStatus(lookup: FlightLookup): Promise<FlightStatusResponse> {
  const normalizedLookup = {
    ...lookup,
    flightNumber: cleanFlightNumber(lookup.flightNumber),
    originAirport: lookup.originAirport?.toUpperCase(),
    destinationAirport: lookup.destinationAirport?.toUpperCase()
  };
  const window = lookupWindow(normalizedLookup.date);

  if (!window) {
    return flightStatusError(normalizedLookup, "provider_error", ["Date is not a valid ISO date."]);
  }

  const aviationstackResult = await aviationstackFetch(normalizedLookup);
  if (aviationstackResult.connected && aviationstackResult.ok) {
    const data = aviationstackResult.data as AviationstackResponse;
    const snapshots = (data.data ?? []).map((flight) => normalizeAviationstackFlight(flight, normalizedLookup.flightNumber));
    const snapshot = snapshots.find((candidate) => routeMatches(candidate, normalizedLookup)) ?? snapshots[0];

    if (!snapshot) {
      return flightStatusError(
        normalizedLookup,
        "not_found",
        ["aviationstack did not return a matching flight for this number, date, and route."],
        "aviationstack"
      );
    }

    return flightStatusSuccess(normalizedLookup, snapshot, "aviationstack");
  }

  if (aviationstackResult.connected && !aviationstackResult.ok && !process.env.FLIGHTAWARE_AEROAPI_KEY) {
    return flightStatusError(
      normalizedLookup,
      "provider_error",
      [`aviationstack returned ${aviationstackResult.error ?? `HTTP ${aviationstackResult.status}`}.`],
      "aviationstack"
    );
  }

  const url = new URL(`/aeroapi/flights/${encodeURIComponent(normalizedLookup.flightNumber)}`, "https://aeroapi.flightaware.com");
  url.searchParams.set("start", window.start);
  url.searchParams.set("end", window.end);

  const result = await flightAwareFetch(`${url.pathname.replace("/aeroapi", "")}${url.search}`);
  if (!result.connected) {
    return flightStatusError(normalizedLookup, "provider_not_connected", ["Set AVIATIONSTACK_API_KEY to enable free live flight validation, or FLIGHTAWARE_AEROAPI_KEY for the paid FlightAware fallback."]);
  }

  if (!result.ok) {
    return flightStatusError(normalizedLookup, "provider_error", [`FlightAware AeroAPI returned HTTP ${result.status}.`]);
  }

  const data = result.data as FlightAwareFlightsResponse;
  const snapshots = (data.flights ?? []).map((flight) => normalizeFlightAwareFlight(flight, normalizedLookup.flightNumber));
  const snapshot = snapshots.find((candidate) => routeMatches(candidate, normalizedLookup)) ?? snapshots[0];

  if (!snapshot) {
    return flightStatusError(normalizedLookup, "not_found", ["Provider did not return a matching flight for this number and date."]);
  }

  snapshot.position = await fetchTrack(snapshot);

  return flightStatusSuccess(normalizedLookup, snapshot, "FlightAware AeroAPI");
}

function flightStatusSuccess(
  normalizedLookup: FlightLookup,
  snapshot: FlightSnapshot,
  providerName: FlightStatusResponse["provider"]["name"]
): FlightStatusResponse {
  return {
    query: normalizedLookup,
    validation: {
      state: "validated",
      confidence: routeMatches(snapshot, normalizedLookup) ? 0.92 : 0.78,
      reasons: [
        "Flight number and service date were found by the live provider.",
        routeMatches(snapshot, normalizedLookup)
          ? "Route matches the requested airports."
          : "Provider returned the flight, but route matching could not be fully confirmed from the request."
      ]
    },
    snapshot,
    delayStats: {
      headline: delayHeadline(snapshot),
      delayMinutes: snapshot.delayMinutes,
      onTimeProbability: snapshot.onTimeProbability,
      reasons: [
        "Score is a cautious Voya estimate from provider status and current delay.",
        "Use a paid predictive feed such as FlightAware Foresight, Cirium, or OAG for stronger historical OTP statistics."
      ]
    },
    gate: {
      departureTerminal: snapshot.departureTerminal,
      departureGate: snapshot.departureGate,
      arrivalTerminal: snapshot.arrivalTerminal,
      arrivalGate: snapshot.arrivalGate,
      baggageClaim: snapshot.baggageClaim,
      changed: false,
      guidance: gateGuidance(snapshot)
    },
    aircraft: {
      type: snapshot.aircraftType,
      registration: snapshot.aircraftRegistration,
      position: snapshot.position
    },
    nextActions: nextActions(snapshot),
    provider: {
      name: providerName,
      connected: true,
      attribution: providerName === "aviationstack"
        ? "Flight status data from aviationstack when configured."
        : "Flight status and tracking data from FlightAware AeroAPI when configured."
    },
    warnings: []
  };
}

function flightStatusError(
  lookup: FlightLookup,
  state: FlightStatusResponse["validation"]["state"],
  reasons: string[],
  providerName: FlightStatusResponse["provider"]["name"] = process.env.AVIATIONSTACK_API_KEY ? "aviationstack" : "FlightAware AeroAPI"
): FlightStatusResponse {
  return {
    query: lookup,
    validation: {
      state,
      confidence: 0,
      reasons
    },
    delayStats: {
      headline: reasons[0] ?? "Flight status unavailable.",
      reasons: []
    },
    gate: {
      changed: false,
      guidance: gateGuidance()
    },
    aircraft: {},
    nextActions: nextActions(),
    provider: {
      name: providerName,
      connected: state !== "provider_not_connected",
      attribution: providerName === "aviationstack"
        ? "Flight status data from aviationstack when configured."
        : "Flight status and tracking data from FlightAware AeroAPI when configured."
    },
    warnings: reasons
  };
}
