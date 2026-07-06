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
  dataMode?: "published_schedule" | "live_operations" | "history";
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

export type FlightPosition = NonNullable<FlightSnapshot["position"]>;

export type FlightPlaneSegment = {
  flightNumber?: string;
  originAirport?: string;
  destinationAirport?: string;
  status: FlightSnapshotStatus;
  providerStatus?: string;
  scheduledDepartureAt?: string;
  estimatedDepartureAt?: string;
  actualDepartureAt?: string;
  scheduledArrivalAt?: string;
  estimatedArrivalAt?: string;
  actualArrivalAt?: string;
  progressPercent?: number;
  position?: FlightPosition;
};

export type FlightPlaneContext = {
  state:
    | "not_assigned"
    | "assigned"
    | "current_airborne"
    | "current_arrived"
    | "inbound_airborne"
    | "inbound_arrived"
    | "inbound_scheduled"
    | "unknown";
  headline: string;
  detail: string;
  aircraftType?: string;
  aircraftRegistration?: string;
  currentFlight?: FlightPlaneSegment;
  inboundFlight?: FlightPlaneSegment;
  position?: FlightPosition;
  progressPercent?: number;
  sourceUpdatedAt?: string;
  confidence: number;
};

export type FlightAirportWeather = {
  airport?: string;
  observedAt?: string;
  raw?: string;
  summary?: string;
  temperatureC?: number;
  wind?: string;
  visibility?: string;
  forecastIssuedAt?: string;
  forecastSummary?: string;
};

export type FlightDisruptionStats = {
  entityType: "airline" | "origin" | "destination";
  entityId?: string;
  entityName?: string;
  cancellations?: number;
  delays?: number;
  total?: number;
  delayRate?: number;
  cancellationRate?: number;
  timePeriod: string;
};

export type FlightHistoryStats = {
  sampleSize: number;
  averageDepartureDelayMinutes?: number;
  averageArrivalDelayMinutes?: number;
  delayed15Rate?: number;
  cancelledCount: number;
  divertedCount: number;
  typicalDepartureGate?: string;
  typicalArrivalGate?: string;
  typicalAircraftTypes: string[];
  since?: string;
  until?: string;
};

export type FlightRouteInsight = {
  route?: string;
  routeDistance?: string;
  count?: number;
  aircraftTypes?: string[];
  filedAltitudeMinFeet?: number;
  filedAltitudeMaxFeet?: number;
  lastDepartureAt?: string;
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
    position?: FlightPosition;
  };
  plane: FlightPlaneContext;
  intelligence: {
    mode: "published_schedule" | "live_operations" | "not_available";
    scheduleAvailableUntil?: string;
    liveDataAvailableFrom?: string;
    disruptions: FlightDisruptionStats[];
    history?: FlightHistoryStats;
    weather: {
      origin?: FlightAirportWeather;
      destination?: FlightAirportWeather;
    };
    route?: FlightRouteInsight;
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

type FlightAwarePublishedSchedule = {
  ident?: string;
  ident_icao?: string | null;
  ident_iata?: string | null;
  actual_ident?: string | null;
  actual_ident_icao?: string | null;
  actual_ident_iata?: string | null;
  aircraft_type?: string;
  scheduled_out?: string;
  scheduled_in?: string;
  origin?: string;
  origin_icao?: string | null;
  origin_iata?: string | null;
  origin_lid?: string | null;
  destination?: string;
  destination_icao?: string | null;
  destination_iata?: string | null;
  destination_lid?: string | null;
  fa_flight_id?: string | null;
  meal_service?: string;
  seats_cabin_business?: number;
  seats_cabin_coach?: number;
  seats_cabin_first?: number;
};

type FlightAwareSchedulesResponse = {
  scheduled?: FlightAwarePublishedSchedule[];
};

type FlightAwareDisruptionResponse = {
  cancellations?: number;
  delays?: number;
  total?: number;
  entity_name?: string | null;
  entity_id?: string | null;
};

type FlightAwareWeatherObservationsResponse = {
  observations?: Array<{
    airport_code?: string;
    cloud_friendly?: string | null;
    conditions?: string | null;
    raw_data?: string;
    temp_air?: number | null;
    time?: string;
    visibility?: number | null;
    visibility_units?: string | null;
    wind_friendly?: string;
    wind_speed?: number;
    wind_speed_gust?: number;
    wind_units?: string;
  }>;
};

type FlightAwareWeatherForecastResponse = {
  airport_code?: string;
  raw_forecast?: string[];
  time?: string;
  decoded_forecast?: {
    lines?: Array<{
      start?: string;
      end?: string | null;
      significant_weather?: string | null;
      winds?: {
        direction?: string;
        speed?: number;
        units?: string | null;
        peak_gusts?: number | null;
      } | null;
      visibility?: {
        visibility?: string;
        units?: string | null;
      } | null;
      clouds?: Array<{
        coverage?: string | null;
        altitude?: string | null;
        special?: string | null;
      }>;
    }>;
  } | null;
};

type FlightAwareRoutesResponse = {
  routes?: Array<{
    aircraft_types?: string[];
    count?: number;
    filed_altitude_max?: number;
    filed_altitude_min?: number;
    last_departure_time?: string;
    route?: string;
    route_distance?: string;
  }>;
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

function flightNumberParts(value: string) {
  const clean = cleanFlightNumber(value);
  const match = clean.match(/^([A-Z0-9]{2,3})(\d{1,4})[A-Z]?$/);
  if (!match) {
    return undefined;
  }

  return {
    carrier: match[1],
    number: Number(match[2])
  };
}

function airportCode(value?: FlightAwareAirport) {
  return value?.code_iata ?? value?.code ?? value?.code_icao ?? value?.code_lid;
}

function airportCodeFromSchedule(value: FlightAwarePublishedSchedule, prefix: "origin" | "destination") {
  return value[`${prefix}_iata`] ?? value[prefix] ?? value[`${prefix}_icao`] ?? value[`${prefix}_lid`] ?? undefined;
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
    dataMode: "live_operations",
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

function normalizeFlightAwarePublishedSchedule(schedule: FlightAwarePublishedSchedule, fallbackFlightNumber: string): FlightSnapshot {
  return {
    provider: "flightaware",
    dataMode: "published_schedule",
    providerFlightId: schedule.fa_flight_id ?? undefined,
    providerStatus: "Published schedule",
    airlineCode: schedule.ident_iata?.match(/^([A-Z0-9]{2})/)?.[1]
      ?? schedule.ident_icao?.match(/^([A-Z0-9]{3})/)?.[1],
    flightNumber: schedule.ident_iata ?? schedule.ident_icao ?? schedule.ident ?? fallbackFlightNumber,
    flightIata: schedule.ident_iata ?? undefined,
    flightIcao: schedule.ident_icao ?? undefined,
    operatingAirlineCode: schedule.actual_ident_iata?.match(/^([A-Z0-9]{2})/)?.[1]
      ?? schedule.actual_ident_icao?.match(/^([A-Z0-9]{3})/)?.[1]
      ?? undefined,
    codeshares: [
      schedule.actual_ident_iata ?? undefined,
      schedule.actual_ident_icao ?? undefined,
      schedule.actual_ident ?? undefined
    ].filter((value): value is string => Boolean(value)),
    originAirport: airportCodeFromSchedule(schedule, "origin"),
    originAirportIcao: schedule.origin_icao ?? undefined,
    destinationAirport: airportCodeFromSchedule(schedule, "destination"),
    destinationAirportIcao: schedule.destination_icao ?? undefined,
    scheduledDepartureAt: schedule.scheduled_out,
    scheduledArrivalAt: schedule.scheduled_in,
    aircraftType: schedule.aircraft_type,
    status: "scheduled",
    confidence: 0.9,
    sourceUpdatedAt: schedule.scheduled_out,
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

function dateRangeForDay(date?: string) {
  const center = date ? new Date(date) : new Date();
  if (Number.isNaN(center.getTime())) {
    return undefined;
  }

  const start = new Date(center);
  start.setUTCHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 1);

  return { start: start.toISOString().slice(0, 10), end: end.toISOString().slice(0, 10) };
}

function liveDataAvailableFrom(date?: string) {
  if (!date) {
    return undefined;
  }

  const target = new Date(date);
  if (Number.isNaN(target.getTime())) {
    return undefined;
  }

  target.setUTCHours(target.getUTCHours() - 48);
  return target.toISOString();
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

function hoursUntil(date?: string) {
  if (!date) {
    return undefined;
  }

  const target = new Date(date);
  if (Number.isNaN(target.getTime())) {
    return undefined;
  }

  return (target.getTime() - Date.now()) / 36e5;
}

function isTooFarForLiveFlightStatus(date?: string) {
  const hours = hoursUntil(date);
  return hours != null && hours > 48;
}

function isTooOldForLiveFlightStatus(date?: string) {
  const hours = hoursUntil(date);
  return hours != null && hours < -240;
}

function isFlightAwareFutureWindowError(error?: string) {
  const normalized = error?.toLowerCase() ?? "";
  return normalized.includes("too far in the future") || normalized.includes("invalid start bound");
}

function isFlightAwarePastWindowError(error?: string) {
  const normalized = error?.toLowerCase() ?? "";
  return normalized.includes("too far in the past") || normalized.includes("invalid start bound");
}

function futureWindowReason() {
  return "FlightAware opens live flight, gate, and airport schedule data about 2 days before departure. Refresh closer to the flight for validated status.";
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

async function flightAwareFlightById(flightId: string) {
  const url = new URL(`/aeroapi/flights/${encodeURIComponent(flightId)}`, "https://aeroapi.flightaware.com");
  url.searchParams.set("ident_type", "fa_flight_id");

  return flightAwareFetch(`${url.pathname.replace("/aeroapi", "")}${url.search}`);
}

async function flightAwareSnapshotById(flightId?: string) {
  if (!flightId) {
    return undefined;
  }

  const result = await flightAwareFlightById(flightId);
  if (!result.connected || !result.ok) {
    return undefined;
  }

  const data = result.data as FlightAwareFlightsResponse;
  const flight = data.flights?.[0];
  if (!flight) {
    return undefined;
  }

  return normalizeFlightAwareFlight(flight, flight.ident_iata ?? flight.ident_icao ?? flight.ident ?? "inbound");
}

async function flightAwareHistoricalFlights(ident: string, window: { start: string; end: string }) {
  const url = new URL(`/aeroapi/history/flights/${encodeURIComponent(ident)}`, "https://aeroapi.flightaware.com");
  url.searchParams.set("ident_type", "designator");
  url.searchParams.set("start", window.start);
  url.searchParams.set("end", window.end);
  url.searchParams.set("max_pages", "1");

  return flightAwareFetch(`${url.pathname.replace("/aeroapi", "")}${url.search}`);
}

async function flightAwareHistoricalSnapshot(lookup: FlightLookup, window: { start: string; end: string }) {
  let lastError: string | undefined;

  for (const ident of identCandidates(lookup.flightNumber)) {
    const result = await flightAwareHistoricalFlights(ident, window);
    if (!result.connected) {
      return { connected: false as const, snapshot: undefined };
    }
    if (!result.ok) {
      lastError = `FlightAware historical lookup returned HTTP ${result.status}${result.error ? `: ${result.error}` : ""}.`;
      continue;
    }

    const data = result.data as FlightAwareFlightsResponse;
    const snapshots = (data.flights ?? []).map((flight) => ({
      ...normalizeFlightAwareFlight(flight, lookup.flightNumber),
      dataMode: "history" as const
    }));
    const snapshot = verifiedSnapshot(snapshots, lookup);
    if (snapshot) {
      return {
        connected: true as const,
        snapshot
      };
    }
  }

  return {
    connected: true as const,
    snapshot: undefined,
    error: lastError
  };
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

async function flightAwarePublishedSchedulesForIdent(lookup: FlightLookup, ident: string) {
  const range = dateRangeForDay(lookup.date);
  const parts = flightNumberParts(ident);
  if (!range || !parts) {
    return undefined;
  }

  const url = new URL(`/aeroapi/schedules/${range.start}/${range.end}`, "https://aeroapi.flightaware.com");
  url.searchParams.set("airline", parts.carrier);
  url.searchParams.set("flight_number", String(parts.number));
  url.searchParams.set("include_codeshares", "true");
  url.searchParams.set("include_regional", "true");
  url.searchParams.set("max_pages", "1");
  if (lookup.originAirport) {
    url.searchParams.set("origin", lookup.originAirport);
  }
  if (lookup.destinationAirport) {
    url.searchParams.set("destination", lookup.destinationAirport);
  }

  return flightAwareFetch(`${url.pathname.replace("/aeroapi", "")}${url.search}`);
}

async function flightAwarePublishedScheduleSnapshot(lookup: FlightLookup) {
  let lastError: string | undefined;

  for (const ident of identCandidates(lookup.flightNumber)) {
    const result = await flightAwarePublishedSchedulesForIdent(lookup, ident);
    if (!result) {
      continue;
    }
    if (!result.connected) {
      return { connected: false as const, snapshot: undefined };
    }
    if (!result.ok) {
      lastError = `FlightAware published schedule lookup returned HTTP ${result.status}${result.error ? `: ${result.error}` : ""}.`;
      continue;
    }

    const data = result.data as FlightAwareSchedulesResponse;
    const snapshots = (data.scheduled ?? []).map((schedule) => normalizeFlightAwarePublishedSchedule(schedule, lookup.flightNumber));
    const snapshot = verifiedScheduleSnapshot(snapshots, lookup);
    if (snapshot) {
      return {
        connected: true as const,
        snapshot
      };
    }
  }

  return {
    connected: true as const,
    snapshot: undefined,
    error: lastError
  };
}

async function flightAwareScheduleSnapshot(lookup: FlightLookup, window: { start: string; end: string }) {
  const scheduleResult = await flightAwareScheduledDepartures(lookup, window);
  if (!scheduleResult) {
    return { connected: true as const, snapshot: undefined };
  }
  if (!scheduleResult.connected) {
    return { connected: false as const, snapshot: undefined };
  }
  if (!scheduleResult.ok) {
    return {
      connected: true as const,
      snapshot: undefined,
      error: isFlightAwareFutureWindowError(scheduleResult.error)
        ? futureWindowReason()
        : `FlightAware schedule lookup returned HTTP ${scheduleResult.status}${scheduleResult.error ? `: ${scheduleResult.error}` : ""}.`
    };
  }

  const scheduleData = scheduleResult.data as FlightAwareScheduledDeparturesResponse;
  const scheduleFlights = scheduleData.scheduled_departures ?? scheduleData.flights ?? [];
  const scheduleSnapshots = scheduleFlights.map((flight) => normalizeFlightAwareFlight(flight, lookup.flightNumber));

  return {
    connected: true as const,
    snapshot: verifiedScheduleSnapshot(scheduleSnapshots, lookup)
  };
}

async function fetchDisruptionStats(
  entityType: FlightDisruptionStats["entityType"],
  entityId: string | undefined,
  timePeriod = "week"
): Promise<FlightDisruptionStats | undefined> {
  if (!entityId) {
    return undefined;
  }

  const url = new URL(`/aeroapi/disruption_counts/${entityType}/${encodeURIComponent(entityId)}`, "https://aeroapi.flightaware.com");
  url.searchParams.set("time_period", timePeriod);
  const result = await flightAwareFetch(`${url.pathname.replace("/aeroapi", "")}${url.search}`);
  if (!result.connected || !result.ok) {
    return undefined;
  }

  const data = result.data as FlightAwareDisruptionResponse;
  const total = data.total ?? 0;
  return {
    entityType,
    entityId: data.entity_id ?? entityId,
    entityName: data.entity_name ?? undefined,
    cancellations: data.cancellations,
    delays: data.delays,
    total: data.total,
    delayRate: total > 0 && data.delays != null ? data.delays / total : undefined,
    cancellationRate: total > 0 && data.cancellations != null ? data.cancellations / total : undefined,
    timePeriod
  };
}

async function fetchAirportWeather(airport?: string): Promise<FlightAirportWeather | undefined> {
  if (!airport) {
    return undefined;
  }

  const observationsResult = await flightAwareFetch(`/airports/${encodeURIComponent(airport)}/weather/observations?temperature_units=Celsius&return_nearby_weather=true&max_pages=1`);
  const forecastResult = await flightAwareFetch(`/airports/${encodeURIComponent(airport)}/weather/forecast?return_nearby_weather=true`);
  const observationData = observationsResult.connected && observationsResult.ok
    ? observationsResult.data as FlightAwareWeatherObservationsResponse
    : undefined;
  const forecastData = forecastResult.connected && forecastResult.ok
    ? forecastResult.data as FlightAwareWeatherForecastResponse
    : undefined;
  const observation = observationData?.observations?.[0];
  const forecastLine = forecastData?.decoded_forecast?.lines?.[0];

  if (!observation && !forecastData) {
    return undefined;
  }

  const wind = observation?.wind_friendly
    ?? (forecastLine?.winds ? `${forecastLine.winds.speed ?? ""} ${forecastLine.winds.units ?? ""}`.trim() : undefined);
  const visibility = observation?.visibility != null
    ? `${observation.visibility} ${observation.visibility_units ?? ""}`.trim()
    : forecastLine?.visibility
      ? `${forecastLine.visibility.visibility ?? ""} ${forecastLine.visibility.units ?? ""}`.trim()
      : undefined;

  return {
    airport: observation?.airport_code ?? forecastData?.airport_code ?? airport,
    observedAt: observation?.time,
    raw: observation?.raw_data,
    summary: [observation?.cloud_friendly, observation?.conditions].filter(Boolean).join(", ") || undefined,
    temperatureC: observation?.temp_air ?? undefined,
    wind,
    visibility,
    forecastIssuedAt: forecastData?.time,
    forecastSummary: forecastLine
      ? [
        forecastLine.significant_weather,
        forecastLine.clouds?.map((cloud) => [cloud.coverage, cloud.altitude].filter(Boolean).join(" ")).filter(Boolean).join(", "),
        forecastLine.winds ? `wind ${forecastLine.winds.direction ?? ""} ${forecastLine.winds.speed ?? ""}${forecastLine.winds.units ?? ""}`.trim() : undefined
      ].filter(Boolean).join(" · ")
      : forecastData?.raw_forecast?.[0]
  };
}

async function fetchRouteInsight(origin?: string, destination?: string): Promise<FlightRouteInsight | undefined> {
  if (!origin || !destination) {
    return undefined;
  }

  const url = new URL(`/aeroapi/airports/${encodeURIComponent(origin)}/routes/${encodeURIComponent(destination)}`, "https://aeroapi.flightaware.com");
  url.searchParams.set("sort_by", "count");
  url.searchParams.set("max_file_age", "1 month");
  url.searchParams.set("max_pages", "1");
  const result = await flightAwareFetch(`${url.pathname.replace("/aeroapi", "")}${url.search}`);
  if (!result.connected || !result.ok) {
    return undefined;
  }

  const data = result.data as FlightAwareRoutesResponse;
  const route = data.routes?.[0];
  if (!route) {
    return undefined;
  }

  return {
    route: route.route,
    routeDistance: route.route_distance,
    count: route.count,
    aircraftTypes: route.aircraft_types,
    filedAltitudeMinFeet: route.filed_altitude_min == null ? undefined : route.filed_altitude_min * 100,
    filedAltitudeMaxFeet: route.filed_altitude_max == null ? undefined : route.filed_altitude_max * 100,
    lastDepartureAt: route.last_departure_time
  };
}

function daysAgoRange(daysAgo: number, spanDays = 7) {
  const end = new Date();
  end.setUTCDate(end.getUTCDate() - daysAgo);
  end.setUTCHours(0, 0, 0, 0);
  const start = new Date(end);
  start.setUTCDate(start.getUTCDate() - spanDays);

  return {
    start: start.toISOString(),
    end: end.toISOString()
  };
}

function average(values: number[]) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : undefined;
}

function mostCommon(values: Array<string | undefined>) {
  const counts = new Map<string, number>();
  for (const value of values) {
    if (!value) {
      continue;
    }
    counts.set(value, (counts.get(value) ?? 0) + 1);
  }

  return [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
}

async function fetchHistoryStats(lookup: FlightLookup): Promise<FlightHistoryStats | undefined> {
  const range = daysAgoRange(1, 7);
  const snapshots: FlightSnapshot[] = [];

  for (const ident of identCandidates(lookup.flightNumber)) {
    const url = new URL(`/aeroapi/history/flights/${encodeURIComponent(ident)}`, "https://aeroapi.flightaware.com");
    url.searchParams.set("ident_type", "designator");
    url.searchParams.set("start", range.start);
    url.searchParams.set("end", range.end);
    url.searchParams.set("max_pages", "1");
    const result = await flightAwareFetch(`${url.pathname.replace("/aeroapi", "")}${url.search}`);
    if (!result.connected || !result.ok) {
      continue;
    }

    const data = result.data as FlightAwareFlightsResponse;
    snapshots.push(...(data.flights ?? []).map((flight) => ({
      ...normalizeFlightAwareFlight(flight, lookup.flightNumber),
      dataMode: "history" as const
    })));
    if (snapshots.length) {
      break;
    }
  }

  const trusted = snapshots.filter((snapshot) => routeMatches(snapshot, lookup));
  const sample = trusted.length ? trusted : snapshots;
  if (sample.length === 0) {
    return undefined;
  }

  const departureDelays = sample.map((snapshot) => snapshot.departureDelayMinutes).filter((value): value is number => value != null);
  const arrivalDelays = sample.map((snapshot) => snapshot.arrivalDelayMinutes).filter((value): value is number => value != null);
  const delayed15 = sample.filter((snapshot) => (snapshot.delayMinutes ?? 0) >= 15).length;

  return {
    sampleSize: sample.length,
    averageDepartureDelayMinutes: average(departureDelays),
    averageArrivalDelayMinutes: average(arrivalDelays),
    delayed15Rate: sample.length ? delayed15 / sample.length : undefined,
    cancelledCount: sample.filter((snapshot) => snapshot.status === "cancelled").length,
    divertedCount: sample.filter((snapshot) => snapshot.status === "diverted").length,
    typicalDepartureGate: mostCommon(sample.map((snapshot) => snapshot.departureGate)),
    typicalArrivalGate: mostCommon(sample.map((snapshot) => snapshot.arrivalGate)),
    typicalAircraftTypes: [...new Set(sample.map((snapshot) => snapshot.aircraftType).filter((value): value is string => Boolean(value)))].slice(0, 3),
    since: range.start,
    until: range.end
  };
}

async function fetchFlightIntelligence(lookup: FlightLookup, snapshot?: FlightSnapshot): Promise<FlightStatusResponse["intelligence"]> {
  const origin = snapshot?.originAirport ?? lookup.originAirport;
  const destination = snapshot?.destinationAirport ?? lookup.destinationAirport;
  const parts = flightNumberParts(snapshot?.flightIata ?? lookup.flightNumber) ?? flightNumberParts(lookup.flightNumber);
  const airline = snapshot?.operatingAirlineCode ?? snapshot?.airlineCode ?? parts?.carrier;

  const [
    airlineDisruption,
    originDisruption,
    destinationDisruption,
    originWeather,
    destinationWeather,
    route,
    history
  ] = await Promise.all([
    fetchDisruptionStats("airline", airline),
    fetchDisruptionStats("origin", origin),
    fetchDisruptionStats("destination", destination),
    fetchAirportWeather(origin),
    fetchAirportWeather(destination),
    fetchRouteInsight(origin, destination),
    fetchHistoryStats(lookup)
  ]);

  return {
    mode: snapshot?.dataMode === "published_schedule" ? "published_schedule" : snapshot ? "live_operations" : "not_available",
    scheduleAvailableUntil: lookup.date ? new Date(new Date(lookup.date).setUTCFullYear(new Date(lookup.date).getUTCFullYear() + 1)).toISOString() : undefined,
    liveDataAvailableFrom: liveDataAvailableFrom(lookup.date),
    disruptions: [airlineDisruption, originDisruption, destinationDisruption].filter((value): value is FlightDisruptionStats => Boolean(value)),
    history,
    weather: {
      origin: originWeather,
      destination: destinationWeather
    },
    route
  };
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

function primaryDeparture(snapshot?: FlightSnapshot) {
  return snapshot?.actualDepartureAt
    ?? snapshot?.estimatedDepartureAt
    ?? snapshot?.scheduledDepartureAt;
}

function primaryArrival(snapshot?: FlightSnapshot) {
  return snapshot?.actualArrivalAt
    ?? snapshot?.estimatedArrivalAt
    ?? snapshot?.scheduledArrivalAt;
}

function segmentFromSnapshot(snapshot: FlightSnapshot): FlightPlaneSegment {
  return {
    flightNumber: snapshot.flightIata ?? snapshot.flightNumber,
    originAirport: snapshot.originAirport,
    destinationAirport: snapshot.destinationAirport,
    status: snapshot.status,
    providerStatus: snapshot.providerStatus,
    scheduledDepartureAt: snapshot.scheduledDepartureAt,
    estimatedDepartureAt: snapshot.estimatedDepartureAt,
    actualDepartureAt: snapshot.actualDepartureAt,
    scheduledArrivalAt: snapshot.scheduledArrivalAt,
    estimatedArrivalAt: snapshot.estimatedArrivalAt,
    actualArrivalAt: snapshot.actualArrivalAt,
    progressPercent: snapshot.progressPercent,
    position: snapshot.position
  };
}

function routeLabel(segment?: FlightPlaneSegment) {
  return [segment?.originAirport, segment?.destinationAirport].filter(Boolean).join(" to ");
}

function formatPercent(value?: number) {
  return value == null ? undefined : `${Math.round(value)}%`;
}

function compactTimeLabel(value?: string) {
  if (!value) {
    return undefined;
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return undefined;
  }

  return date.toISOString().slice(11, 16);
}

function buildPlaneContext(snapshot?: FlightSnapshot, inboundSnapshot?: FlightSnapshot): FlightPlaneContext {
  if (!snapshot) {
    return {
      state: "unknown",
      headline: "Aircraft status unavailable",
      detail: "Validate the flight first to check aircraft assignment and live position.",
      confidence: 0
    };
  }

  const currentFlight = segmentFromSnapshot(snapshot);
  const inboundFlight = inboundSnapshot ? segmentFromSnapshot(inboundSnapshot) : undefined;
  const aircraftType = snapshot.aircraftType ?? inboundSnapshot?.aircraftType;
  const aircraftRegistration = snapshot.aircraftRegistration ?? inboundSnapshot?.aircraftRegistration;
  const position = snapshot.position ?? inboundSnapshot?.position;
  const progressPercent = snapshot.status === "departed"
    ? snapshot.progressPercent
    : inboundSnapshot?.progressPercent;
  const sourceUpdatedAt = position?.updatedAt
    ?? snapshot.sourceUpdatedAt
    ?? inboundSnapshot?.sourceUpdatedAt
    ?? snapshot.fetchedAt;

  if (snapshot.status === "departed") {
    const progress = formatPercent(snapshot.progressPercent);
    const route = routeLabel(currentFlight);
    const arrivalTime = compactTimeLabel(primaryArrival(snapshot));
    return {
      state: "current_airborne",
      headline: progress ? `This flight is airborne, ${progress} complete` : "This flight is airborne",
      detail: [
        route || undefined,
        snapshot.position ? "Live aircraft position is available." : "FlightAware has marked the flight departed; live position is not available yet.",
        arrivalTime ? `Expected arrival around ${arrivalTime}.` : undefined
      ].filter(Boolean).join(" "),
      aircraftType,
      aircraftRegistration,
      currentFlight,
      position,
      progressPercent,
      sourceUpdatedAt,
      confidence: snapshot.position ? 0.94 : 0.82
    };
  }

  if (snapshot.status === "arrived") {
    const arrivalTime = compactTimeLabel(snapshot.actualArrivalAt ?? snapshot.estimatedArrivalAt);
    return {
      state: "current_arrived",
      headline: "This flight has arrived",
      detail: [
        arrivalTime ? `Arrived around ${arrivalTime}.` : undefined,
        routeLabel(currentFlight) || undefined
      ].filter(Boolean).join(" ") || "FlightAware has marked this flight arrived.",
      aircraftType,
      aircraftRegistration,
      currentFlight,
      position: snapshot.position,
      progressPercent: snapshot.progressPercent,
      sourceUpdatedAt,
      confidence: 0.9
    };
  }

  if (inboundSnapshot) {
    const inboundRoute = routeLabel(inboundFlight);
    const arrivalTime = compactTimeLabel(primaryArrival(inboundSnapshot));
    const isInboundAirborne = inboundSnapshot.status === "departed";
    const isInboundArrived = inboundSnapshot.status === "arrived";

    if (isInboundAirborne) {
      return {
        state: "inbound_airborne",
        headline: "Assigned aircraft is still inbound",
        detail: [
          inboundRoute ? `It is flying ${inboundRoute}.` : "It is flying the previous segment.",
          arrivalTime ? `Expected at ${arrivalTime} before your departure.` : undefined
        ].filter(Boolean).join(" "),
        aircraftType,
        aircraftRegistration,
        currentFlight,
        inboundFlight,
        position,
        progressPercent,
        sourceUpdatedAt,
        confidence: inboundSnapshot.position ? 0.92 : 0.82
      };
    }

    if (isInboundArrived) {
      return {
        state: "inbound_arrived",
        headline: "Assigned aircraft has arrived",
        detail: [
          inboundRoute ? `Previous segment ${inboundRoute} is complete.` : "The previous segment is complete.",
          arrivalTime ? `Arrived around ${arrivalTime}.` : undefined
        ].filter(Boolean).join(" "),
        aircraftType,
        aircraftRegistration,
        currentFlight,
        inboundFlight,
        position,
        progressPercent,
        sourceUpdatedAt,
        confidence: 0.88
      };
    }

    return {
      state: "inbound_scheduled",
      headline: "Assigned aircraft has an inbound segment",
      detail: [
        inboundRoute ? `Inbound segment ${inboundRoute}.` : "Inbound segment is known.",
        arrivalTime ? `Scheduled around ${arrivalTime}.` : undefined
      ].filter(Boolean).join(" "),
      aircraftType,
      aircraftRegistration,
      currentFlight,
      inboundFlight,
      position,
      progressPercent,
      sourceUpdatedAt,
      confidence: 0.76
    };
  }

  if (aircraftRegistration || (snapshot.dataMode !== "published_schedule" && aircraftType)) {
    return {
      state: "assigned",
      headline: "Aircraft is assigned",
      detail: [aircraftRegistration, aircraftType, "No inbound aircraft position is available yet."].filter(Boolean).join(" · "),
      aircraftType,
      aircraftRegistration,
      currentFlight,
      position,
      progressPercent,
      sourceUpdatedAt,
      confidence: 0.72
    };
  }

  return {
    state: "not_assigned",
    headline: "Aircraft not assigned yet",
    detail: "Aircraft assignment and inbound tracking usually appear closer to departure.",
    currentFlight,
    sourceUpdatedAt,
    confidence: snapshot.dataMode === "published_schedule" ? 0.42 : 0.58
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

function delayHeadline(snapshot?: FlightSnapshot, history?: FlightHistoryStats) {
  if (!snapshot) {
    return "Flight status provider is not connected.";
  }

  if (snapshot.dataMode === "published_schedule") {
    if (history?.averageArrivalDelayMinutes != null) {
      return `Schedule confirmed; recent average arrival delay is ${Math.round(history.averageArrivalDelayMinutes)} minutes.`;
    }
    return "Schedule confirmed; live delay data opens closer to departure.";
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

function emptyIntelligence(lookup: FlightLookup): FlightStatusResponse["intelligence"] {
  return {
    mode: "not_available",
    liveDataAvailableFrom: liveDataAvailableFrom(lookup.date),
    disruptions: [],
    weather: {}
  };
}

function normalizedPublicBaseURL(value?: string) {
  const trimmed = value?.trim().replace(/\/$/, "");
  if (!trimmed) {
    return "https://your-voya-backend.example";
  }
  if (trimmed.startsWith("ttps://")) {
    return `h${trimmed}`;
  }
  return trimmed;
}

function alerting(webhookBaseURL?: string): FlightStatusResponse["alerting"] {
  const baseURL = normalizedPublicBaseURL(webhookBaseURL);

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

  if (isTooFarForLiveFlightStatus(normalizedLookup.date)) {
    const scheduleLookup = await flightAwarePublishedScheduleSnapshot(normalizedLookup);
    if (!scheduleLookup.connected) {
      return flightStatusError(normalizedLookup, "provider_not_connected", ["Set FLIGHTAWARE_AEROAPI_KEY to enable FlightAware AeroAPI status, schedule, gate, and alert data."]);
    }
    if (scheduleLookup.snapshot) {
      return flightStatusSuccess(normalizedLookup, scheduleLookup.snapshot, [
        "FlightAware validated this future flight from published airline schedules. Live gate, aircraft, position, and delay data opens closer to departure."
      ]);
    }

    return flightStatusError(normalizedLookup, "not_found", [
      scheduleLookup.error ?? "FlightAware published schedules did not return a route/date match for this future flight."
    ]);
  }

  if (isTooOldForLiveFlightStatus(normalizedLookup.date)) {
    const historyLookup = await flightAwareHistoricalSnapshot(normalizedLookup, window);
    if (!historyLookup.connected) {
      return flightStatusError(normalizedLookup, "provider_not_connected", ["Set FLIGHTAWARE_AEROAPI_KEY to enable FlightAware historical flight data."]);
    }
    if (historyLookup.snapshot) {
      return flightStatusSuccess(normalizedLookup, historyLookup.snapshot, [
        "FlightAware validated this past flight from historical flight data."
      ]);
    }

    return flightStatusError(normalizedLookup, "not_found", [
      historyLookup.error ?? "FlightAware historical data did not return a route/date match for this past flight."
    ]);
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
    if (isFlightAwarePastWindowError(result.error)) {
      const historyLookup = await flightAwareHistoricalSnapshot(normalizedLookup, window);
      if (historyLookup.snapshot) {
        return flightStatusSuccess(normalizedLookup, historyLookup.snapshot, [
          "Live FlightAware status was unavailable, so Voya used historical flight data for this route/date match."
        ]);
      }
    }

    const scheduleLookup = await flightAwarePublishedScheduleSnapshot(normalizedLookup);
    if (scheduleLookup.snapshot) {
      return flightStatusSuccess(normalizedLookup, scheduleLookup.snapshot, [
        "Live FlightAware status was unavailable, so Voya used published schedule data for this route/date match."
      ]);
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
  const inboundSnapshot = await flightAwareSnapshotById(snapshot.inboundProviderFlightId);
  if (inboundSnapshot) {
    inboundSnapshot.position = await fetchTrack(inboundSnapshot);
  }

  return flightStatusSuccess(normalizedLookup, snapshot, [], inboundSnapshot);
}

function flightStatusSuccess(
  normalizedLookup: FlightLookup,
  snapshot: FlightSnapshot,
  warnings: string[] = [],
  inboundSnapshot?: FlightSnapshot
): Promise<FlightStatusResponse> {
  return fetchFlightIntelligence(normalizedLookup, snapshot).then((intelligence) => ({
    query: normalizedLookup,
    validation: {
      state: "validated",
      confidence: routeMatches(snapshot, normalizedLookup) && dateMatches(snapshot, normalizedLookup) ? 0.96 : 0,
      reasons: snapshot.dataMode === "published_schedule"
        ? [
          "FlightAware found this flight in published airline schedules.",
          "Route and date match the imported itinerary item."
        ]
        : [
          "FlightAware found this flight number for the imported service date.",
          "Route and date match the imported itinerary item."
        ]
    },
    snapshot,
    delayStats: {
      headline: delayHeadline(snapshot, intelligence.history),
      delayMinutes: snapshot.delayMinutes,
      onTimeProbability: snapshot.onTimeProbability,
      reasons: [
        "Score is a cautious Voya estimate from FlightAware status, disruption counts, and available history.",
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
    plane: buildPlaneContext(snapshot, inboundSnapshot),
    intelligence,
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
    warnings
  }));
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
    plane: buildPlaneContext(),
    intelligence: emptyIntelligence(lookup),
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
