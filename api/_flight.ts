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
  provider: "flightaware";
  providerFlightId?: string;
  providerStatus?: string;
  airlineCode?: string;
  flightNumber: string;
  flightIata?: string;
  flightIcao?: string;
  operatingAirlineCode?: string;
  codeshares?: string[];
  originAirport?: string;
  originAirportIcao?: string;
  destinationAirport?: string;
  destinationAirportIcao?: string;
  scheduledDepartureAt?: string;
  scheduledTakeoffAt?: string;
  scheduledLandingAt?: string;
  scheduledArrivalAt?: string;
  estimatedDepartureAt?: string;
  estimatedTakeoffAt?: string;
  estimatedLandingAt?: string;
  estimatedArrivalAt?: string;
  actualDepartureAt?: string;
  actualTakeoffAt?: string;
  actualLandingAt?: string;
  actualArrivalAt?: string;
  departureTerminal?: string;
  departureGate?: string;
  departureDelayMinutes?: number;
  arrivalTerminal?: string;
  arrivalGate?: string;
  arrivalDelayMinutes?: number;
  baggageClaim?: string;
  aircraftType?: string;
  aircraftRegistration?: string;
  status: FlightSnapshotStatus;
  delayMinutes?: number;
  cancellationReason?: string;
  diversionAirport?: string;
  inboundProviderFlightId?: string;
  progressPercent?: number;
  routeDistanceNm?: number;
  filedAirspeedKnots?: number;
  filedAltitudeFeet?: number;
  filedRoute?: string;
  filedEte?: number;
  position?: {
    lat: number;
    lon: number;
    altitudeFeet?: number;
    groundspeedKnots?: number;
    headingDegrees?: number;
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
  schedule: {
    scheduledDepartureAt?: string;
    scheduledTakeoffAt?: string;
    scheduledLandingAt?: string;
    scheduledArrivalAt?: string;
    estimatedDepartureAt?: string;
    estimatedTakeoffAt?: string;
    estimatedLandingAt?: string;
    estimatedArrivalAt?: string;
    actualDepartureAt?: string;
    actualTakeoffAt?: string;
    actualLandingAt?: string;
    actualArrivalAt?: string;
  };
  alerting: {
    supported: boolean;
    source: "flightaware-alerts";
    events: string[];
    webhookEndpoint: string;
    managementEndpoint: string;
  };
  nextActions: string[];
  provider: {
    name: "FlightAware AeroAPI";
    connected: boolean;
    attribution: string;
  };
  warnings: string[];
};

type FlightAwareAirport = {
  code?: string;
  code_iata?: string;
  code_icao?: string;
  code_lid?: string;
};

type FlightAwareFlight = {
  fa_flight_id?: string;
  ident?: string;
  ident_iata?: string;
  ident_icao?: string;
  operator?: string;
  operator_iata?: string;
  operator_icao?: string;
  flight_number?: string;
  registration?: string;
  aircraft_type?: string;
  status?: string;
  progress_percent?: number;
  cancelled?: boolean;
  diverted?: boolean;
  blocked?: boolean;
  inbound_fa_flight_id?: string;
  codeshares?: string[];
  codeshares_iata?: string[];
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
  departure_delay?: number;
  arrival_delay?: number;
  terminal_origin?: string;
  gate_origin?: string;
  terminal_destination?: string;
  gate_destination?: string;
  baggage_claim?: string;
  route_distance?: number;
  filed_airspeed?: number;
  filed_altitude?: number;
  filed_route?: string;
  route?: string;
  filed_ete?: number;
};

type FlightAwareFlightsResponse = {
  flights?: FlightAwareFlight[];
};

type FlightAwareScheduledDeparturesResponse = {
  scheduled_departures?: FlightAwareFlight[];
  flights?: FlightAwareFlight[];
};

type FlightAwareCanonicalResponse = {
  ident?: string;
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

type FlightAwareErrorBody = {
  message?: string;
  error?: string;
  title?: string;
  detail?: string;
  reason?: string;
};

function cleanFlightNumber(value: string) {
  return value.replace(/\s+/g, "").toUpperCase();
}

function identCandidates(value: string) {
  const clean = cleanFlightNumber(value);
  const airlineIataToIcao: Record<string, string> = {
    BA: "BAW",
    LH: "DLH",
    LX: "SWR",
    OS: "AUA",
    SN: "BEL",
    AF: "AFR",
    KL: "KLM",
    IB: "IBE",
    VY: "VLG",
    U2: "EZY",
    FR: "RYR",
    W6: "WZZ",
    AA: "AAL",
    DL: "DAL",
    UA: "UAL",
    AC: "ACA"
  };
  const match = clean.match(/^([A-Z0-9]{2})(\d{1,4}[A-Z]?)$/);
  const icaoIdent = match ? `${airlineIataToIcao[match[1]] ?? ""}${match[2]}` : "";

  return [...new Set([clean, icaoIdent].filter(Boolean))];
}

function airportCode(value?: FlightAwareAirport) {
  return value?.code_iata ?? value?.code ?? value?.code_icao ?? value?.code_lid;
}

function secondsToMinutes(value?: number) {
  return value == null ? undefined : Math.round(value / 60);
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
  if (flight.actual_in || flight.actual_on || status.includes("arriv") || status.includes("landed")) {
    return "arrived";
  }
  if (flight.actual_off || flight.actual_out || status.includes("depart") || status.includes("en route")) {
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

function normalizeFlightAwareFlight(flight: FlightAwareFlight, fallbackFlightNumber: string): FlightSnapshot {
  const status = statusFromFlightAware(flight);
  const departureDelayMinutes = secondsToMinutes(flight.departure_delay)
    ?? minutesBetween(flight.estimated_out, flight.scheduled_out);
  const arrivalDelayMinutes = secondsToMinutes(flight.arrival_delay)
    ?? minutesBetween(flight.estimated_in, flight.scheduled_in);
  const delayMinutes = departureDelayMinutes ?? arrivalDelayMinutes;

  return {
    provider: "flightaware",
    providerFlightId: flight.fa_flight_id,
    providerStatus: flight.status,
    airlineCode: flight.operator_iata ?? flight.operator_icao ?? flight.operator,
    flightNumber: flight.ident_iata ?? flight.ident_icao ?? flight.ident ?? fallbackFlightNumber,
    flightIata: flight.ident_iata,
    flightIcao: flight.ident_icao,
    operatingAirlineCode: flight.operator_iata ?? flight.operator_icao ?? flight.operator,
    codeshares: flight.codeshares_iata ?? flight.codeshares,
    originAirport: airportCode(flight.origin),
    originAirportIcao: flight.origin?.code_icao,
    destinationAirport: airportCode(flight.destination),
    destinationAirportIcao: flight.destination?.code_icao,
    scheduledDepartureAt: flight.scheduled_out,
    scheduledTakeoffAt: flight.scheduled_off,
    scheduledLandingAt: flight.scheduled_on,
    scheduledArrivalAt: flight.scheduled_in,
    estimatedDepartureAt: flight.estimated_out,
    estimatedTakeoffAt: flight.estimated_off,
    estimatedLandingAt: flight.estimated_on,
    estimatedArrivalAt: flight.estimated_in,
    actualDepartureAt: flight.actual_out,
    actualTakeoffAt: flight.actual_off,
    actualLandingAt: flight.actual_on,
    actualArrivalAt: flight.actual_in,
    departureTerminal: flight.terminal_origin,
    departureGate: flight.gate_origin,
    departureDelayMinutes,
    arrivalTerminal: flight.terminal_destination,
    arrivalGate: flight.gate_destination,
    arrivalDelayMinutes,
    baggageClaim: flight.baggage_claim,
    aircraftType: flight.aircraft_type,
    aircraftRegistration: flight.registration,
    status,
    delayMinutes,
    diversionAirport: flight.diverted ? airportCode(flight.destination) : undefined,
    inboundProviderFlightId: flight.inbound_fa_flight_id,
    progressPercent: flight.progress_percent,
    routeDistanceNm: flight.route_distance,
    filedAirspeedKnots: flight.filed_airspeed,
    filedAltitudeFeet: flight.filed_altitude,
    filedRoute: flight.filed_route ?? flight.route,
    filedEte: flight.filed_ete,
    onTimeProbability: onTimeProbability(status, delayMinutes),
    confidence: 0.94,
    sourceUpdatedAt: flight.actual_out ?? flight.estimated_out ?? flight.scheduled_out,
    fetchedAt: new Date().toISOString()
  };
}

function routeMatches(snapshot: FlightSnapshot, lookup: FlightLookup) {
  const originMatches = !lookup.originAirport || snapshot.originAirport === lookup.originAirport.toUpperCase();
  const destinationMatches = !lookup.destinationAirport || snapshot.destinationAirport === lookup.destinationAirport.toUpperCase();

  return originMatches && destinationMatches;
}

function dateMatches(snapshot: FlightSnapshot, lookup: FlightLookup) {
  if (!lookup.date) {
    return true;
  }

  const lookupDate = lookup.date.slice(0, 10);
  const snapshotDates = [
    snapshot.scheduledDepartureAt,
    snapshot.estimatedDepartureAt,
    snapshot.actualDepartureAt
  ]
    .filter(Boolean)
    .map((value) => value?.slice(0, 10));

  return snapshotDates.length === 0 ? false : snapshotDates.includes(lookupDate);
}

function verifiedSnapshot(snapshots: FlightSnapshot[], lookup: FlightLookup) {
  return snapshots.find((candidate) => routeMatches(candidate, lookup) && dateMatches(candidate, lookup));
}

function flightNumberMatches(snapshot: FlightSnapshot, lookup: FlightLookup) {
  const candidates = identCandidates(lookup.flightNumber);
  const snapshotValues = [
    snapshot.flightNumber,
    snapshot.flightIata,
    snapshot.flightIcao,
    ...(snapshot.codeshares ?? [])
  ].filter((value): value is string => typeof value === "string" && value.length > 0)
    .map((value) => cleanFlightNumber(value));

  return snapshotValues.some((value) => candidates.includes(value));
}

function verifiedScheduleSnapshot(snapshots: FlightSnapshot[], lookup: FlightLookup) {
  return snapshots.find((candidate) => flightNumberMatches(candidate, lookup) && routeMatches(candidate, lookup) && dateMatches(candidate, lookup));
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
  const apiKey = process.env.FLIGHTAWARE_AEROAPI_KEY?.trim();
  if (!apiKey) {
    return { connected: false as const };
  }

  const response = await fetch(`https://aeroapi.flightaware.com/aeroapi${path}`, {
    headers: {
      Accept: "application/json",
      "x-apikey": apiKey
    }
  });
  const data = await response.json().catch(() => undefined);

  if (!response.ok) {
    const errorBody = data as FlightAwareErrorBody | undefined;
    const error = [
      errorBody?.message,
      errorBody?.error,
      errorBody?.title,
      errorBody?.detail,
      errorBody?.reason
    ].filter(Boolean).join(" ");

    return {
      connected: true as const,
      ok: false as const,
      status: response.status,
      error: error || undefined
    };
  }

  return { connected: true as const, ok: true as const, data };
}

async function flightAwareCanonicalIdent(ident: string) {
  const result = await flightAwareFetch(`/flights/${encodeURIComponent(ident)}/canonical`);
  if (!result.connected || !result.ok) {
    return undefined;
  }

  const data = result.data as FlightAwareCanonicalResponse;
  return typeof data.ident === "string" && data.ident.trim() ? data.ident.trim().toUpperCase() : undefined;
}

async function flightAwareFlights(ident: string, window: { start: string; end: string }) {
  const url = new URL(`/aeroapi/flights/${encodeURIComponent(ident)}`, "https://aeroapi.flightaware.com");
  url.searchParams.set("start", window.start);
  url.searchParams.set("end", window.end);

  return flightAwareFetch(`${url.pathname.replace("/aeroapi", "")}${url.search}`);
}

async function flightAwareScheduledDepartures(lookup: FlightLookup, window: { start: string; end: string }) {
  if (!lookup.originAirport) {
    return undefined;
  }

  const url = new URL(`/aeroapi/airports/${encodeURIComponent(lookup.originAirport)}/flights/scheduled_departures`, "https://aeroapi.flightaware.com");
  url.searchParams.set("start", window.start);
  url.searchParams.set("end", window.end);

  return flightAwareFetch(`${url.pathname.replace("/aeroapi", "")}${url.search}`);
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

  return [
    snapshot.departureTerminal
      ? `Go to terminal ${snapshot.departureTerminal} and follow airport signs after security.`
      : "Terminal is not available yet; check the airport displays and refresh closer to departure.",
    snapshot.departureGate
      ? `Departure gate is ${snapshot.departureGate}.`
      : "Gate is often posted 1-3 hours before departure and can change.",
    "Airport displays and airline notifications remain the final authority at the airport."
  ];
}

function nextActions(snapshot?: FlightSnapshot) {
  if (!snapshot) {
    return ["Refresh after FlightAware has flight data for this service date."];
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

function alerting(webhookBaseURL?: string): FlightStatusResponse["alerting"] {
  const baseURL = webhookBaseURL?.replace(/\/$/, "") || "https://your-voya-backend.example";

  return {
    supported: true,
    source: "flightaware-alerts",
    events: [
      "departure",
      "arrival",
      "cancellation",
      "diversion",
      "schedule_change",
      "gate_change",
      "holding"
    ],
    webhookEndpoint: `${baseURL}/api/flightaware-alerts`,
    managementEndpoint: `${baseURL}/api/flightaware-alert-subscriptions`
  };
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

  let result = await flightAwareFlights(normalizedLookup.flightNumber, window);
  if (!result.connected) {
    return flightStatusError(normalizedLookup, "provider_not_connected", ["Set FLIGHTAWARE_AEROAPI_KEY to enable FlightAware AeroAPI status, schedule, gate, and alert data."]);
  }

  if (!result.ok && (result.status === 400 || result.status === 404)) {
    for (const ident of identCandidates(normalizedLookup.flightNumber)) {
      if (ident === normalizedLookup.flightNumber) {
        continue;
      }
      const candidateResult = await flightAwareFlights(ident, window);
      if (candidateResult.ok) {
        result = candidateResult;
        break;
      }
    }

    if (!result.ok) {
      const canonicalIdent = await flightAwareCanonicalIdent(normalizedLookup.flightNumber);
      if (canonicalIdent && canonicalIdent !== normalizedLookup.flightNumber) {
        result = await flightAwareFlights(canonicalIdent, window);
      }
    }
  }

  if (!result.ok && result.status === 400 && normalizedLookup.date && normalizedLookup.originAirport) {
    const scheduleResult = await flightAwareScheduledDepartures(normalizedLookup, window);
    if (scheduleResult?.connected && scheduleResult.ok) {
      const scheduleData = scheduleResult.data as FlightAwareScheduledDeparturesResponse;
      const scheduleFlights = scheduleData.scheduled_departures ?? scheduleData.flights ?? [];
      const scheduleSnapshots = scheduleFlights.map((flight) => normalizeFlightAwareFlight(flight, normalizedLookup.flightNumber));
      const scheduleSnapshot = verifiedScheduleSnapshot(scheduleSnapshots, normalizedLookup);

      if (scheduleSnapshot) {
        return flightStatusSuccess(normalizedLookup, scheduleSnapshot);
      }
    }
  }

  if (!result.ok) {
    return flightStatusError(normalizedLookup, "provider_error", [`FlightAware AeroAPI returned HTTP ${result.status}${result.error ? `: ${result.error}` : ""}.`]);
  }

  const data = result.data as FlightAwareFlightsResponse;
  const snapshots = (data.flights ?? []).map((flight) => normalizeFlightAwareFlight(flight, normalizedLookup.flightNumber));
  const snapshot = verifiedSnapshot(snapshots, normalizedLookup);

  if (!snapshot) {
    return flightStatusError(normalizedLookup, "not_found", ["FlightAware returned data, but none matched the imported flight date and route closely enough to trust."]);
  }

  snapshot.position = await fetchTrack(snapshot);

  return flightStatusSuccess(normalizedLookup, snapshot);
}

function flightStatusSuccess(
  normalizedLookup: FlightLookup,
  snapshot: FlightSnapshot
): FlightStatusResponse {
  return {
    query: normalizedLookup,
    validation: {
      state: "validated",
      confidence: routeMatches(snapshot, normalizedLookup) && dateMatches(snapshot, normalizedLookup) ? 0.96 : 0,
      reasons: [
        "FlightAware found this flight number for the imported service date.",
        "Route and date match the imported itinerary item."
      ]
    },
    snapshot,
    delayStats: {
      headline: delayHeadline(snapshot),
      delayMinutes: snapshot.delayMinutes,
      onTimeProbability: snapshot.onTimeProbability,
      reasons: [
        "Score is a cautious Voya estimate from FlightAware status and current delay.",
        "FlightAware Foresight can be added later for stronger predictive ETAs."
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
    schedule: {
      scheduledDepartureAt: snapshot.scheduledDepartureAt,
      scheduledTakeoffAt: snapshot.scheduledTakeoffAt,
      scheduledLandingAt: snapshot.scheduledLandingAt,
      scheduledArrivalAt: snapshot.scheduledArrivalAt,
      estimatedDepartureAt: snapshot.estimatedDepartureAt,
      estimatedTakeoffAt: snapshot.estimatedTakeoffAt,
      estimatedLandingAt: snapshot.estimatedLandingAt,
      estimatedArrivalAt: snapshot.estimatedArrivalAt,
      actualDepartureAt: snapshot.actualDepartureAt,
      actualTakeoffAt: snapshot.actualTakeoffAt,
      actualLandingAt: snapshot.actualLandingAt,
      actualArrivalAt: snapshot.actualArrivalAt
    },
    alerting: alerting(process.env.VOYA_API_PUBLIC_BASE_URL),
    nextActions: nextActions(snapshot),
    provider: {
      name: "FlightAware AeroAPI",
      connected: true,
      attribution: "Flight status, schedules, gate assignments, and alert capability from FlightAware AeroAPI."
    },
    warnings: []
  };
}

function flightStatusError(
  lookup: FlightLookup,
  state: FlightStatusResponse["validation"]["state"],
  reasons: string[]
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
    schedule: {},
    alerting: alerting(process.env.VOYA_API_PUBLIC_BASE_URL),
    nextActions: nextActions(),
    provider: {
      name: "FlightAware AeroAPI",
      connected: state !== "provider_not_connected",
      attribution: "Flight status, schedules, gate assignments, and alert capability from FlightAware AeroAPI."
    },
    warnings: reasons
  };
}
