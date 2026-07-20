import { randomUUID } from "node:crypto";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requestInstallId } from "./_agents.js";
import { sendAPNsAlert } from "./_apns.js";
import { readFlightAlertSelfTest, saveFlightAlertSelfTest, type FlightAlertSelfTestRecord } from "./_flight-self-test.js";
import { protectPublicEndpoint } from "./_security.js";
import { normalizeDeviceToken, normalizeFlightNumber, storageConfigured } from "./_storage.js";
import { registerFlightWatch } from "./flight-watch.js";

type FlightAwareAirport = {
  code?: string;
  code_iata?: string;
  code_icao?: string;
  code_lid?: string;
};

type FlightAwareCandidate = {
  ident?: string;
  ident_iata?: string;
  ident_icao?: string;
  fa_flight_id?: string;
  origin?: FlightAwareAirport;
  destination?: FlightAwareAirport;
  scheduled_out?: string;
  estimated_out?: string;
  gate_origin?: string;
  terminal_origin?: string;
  cancelled?: boolean;
  diverted?: boolean;
};

type ScheduledDeparturesResponse = {
  scheduled_departures?: FlightAwareCandidate[];
  flights?: FlightAwareCandidate[];
};

type SelectedFlight = {
  flightNumber: string;
  flightDate: string;
  originAirport: string;
  destinationAirport: string;
  departureAt: string;
  providerFlightId?: string;
};

const airportSearchOrder = ["KATL", "KDFW", "KJFK", "KLAX", "EGLL", "EHAM"];

function airportCode(value: FlightAwareAirport | undefined) {
  return value?.code_iata ?? value?.code_icao ?? value?.code_lid ?? value?.code;
}

function candidateFromFlight(flight: FlightAwareCandidate, now: Date): SelectedFlight | undefined {
  const flightNumber = normalizeFlightNumber(flight.ident_iata ?? flight.ident ?? flight.ident_icao);
  const originAirport = airportCode(flight.origin)?.trim().toUpperCase();
  const destinationAirport = airportCode(flight.destination)?.trim().toUpperCase();
  const departureAt = flight.estimated_out ?? flight.scheduled_out;
  const departureTime = departureAt ? Date.parse(departureAt) : Number.NaN;
  const minutesUntilDeparture = (departureTime - now.getTime()) / 60_000;

  if (!flightNumber || !originAirport || !destinationAirport || !departureAt) return undefined;
  if (flight.cancelled || flight.diverted || flight.gate_origin?.trim()) return undefined;
  if (!Number.isFinite(minutesUntilDeparture) || minutesUntilDeparture < 45 || minutesUntilDeparture > 8 * 60) return undefined;

  return {
    flightNumber,
    flightDate: departureAt.slice(0, 10),
    originAirport,
    destinationAirport,
    departureAt,
    providerFlightId: flight.fa_flight_id
  };
}

async function scheduledDepartures(airport: string, now: Date) {
  const apiKey = process.env.FLIGHTAWARE_AEROAPI_KEY?.trim();
  if (!apiKey) throw new Error("FlightAware AeroAPI is not configured.");

  const aeroAPITimestamp = (value: Date) => value.toISOString().replace(/\.\d{3}Z$/, "Z");
  const start = aeroAPITimestamp(new Date(now.getTime() + 45 * 60_000));
  const end = aeroAPITimestamp(new Date(now.getTime() + 8 * 60 * 60_000));
  const url = new URL(`/aeroapi/airports/${airport}/flights/scheduled_departures`, "https://aeroapi.flightaware.com");
  url.searchParams.set("start", start);
  url.searchParams.set("end", end);

  const response = await fetch(url, {
    headers: { Accept: "application/json", "x-apikey": apiKey }
  });
  const data = await response.json().catch(() => undefined) as ScheduledDeparturesResponse & { detail?: string } | undefined;
  if (!response.ok) {
    throw new Error(`FlightAware departure search at ${airport} failed: ${data?.detail ?? `HTTP ${response.status}`}.`);
  }
  return data?.scheduled_departures ?? data?.flights ?? [];
}

async function findFlightWithoutGate(now = new Date()) {
  const candidates: SelectedFlight[] = [];
  const errors: string[] = [];

  for (const airport of airportSearchOrder.slice(0, 4)) {
    try {
      const flights = await scheduledDepartures(airport, now);
      candidates.push(...flights.flatMap((flight) => {
        const candidate = candidateFromFlight(flight, now);
        return candidate ? [candidate] : [];
      }));
      if (candidates.length >= 8) break;
    } catch (error) {
      errors.push(error instanceof Error ? error.message : `Could not search ${airport}.`);
    }
  }

  candidates.sort((lhs, rhs) => {
    const target = now.getTime() + 2.5 * 60 * 60_000;
    return Math.abs(Date.parse(lhs.departureAt) - target) - Math.abs(Date.parse(rhs.departureAt) - target);
  });
  if (candidates[0]) return candidates[0];
  throw new Error(errors[0] ?? "No upcoming flight without an assigned departure gate was found at the searched hubs.");
}

function publicRecord(record: FlightAlertSelfTestRecord | undefined) {
  return record ?? { status: "idle" };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET" && req.method !== "POST") {
    res.setHeader("Allow", "GET, POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!await protectPublicEndpoint(req, res, {
    name: "flight-alert-self-test",
    hourlyIPLimit: 30,
    hourlyInstallLimit: 8,
    maxBodyBytes: 8_000
  })) return;

  const installId = requestInstallId(req);
  if (req.method === "GET") {
    return res.status(200).json(publicRecord(await readFlightAlertSelfTest(installId)));
  }

  const deviceToken = normalizeDeviceToken((req.body as { deviceToken?: unknown } | undefined)?.deviceToken);
  if (!deviceToken) return res.status(400).json({ error: "A valid APNs device token is required. Open Voya on a physical iPhone and allow notifications." });
  if (!storageConfigured()) return res.status(503).json({ error: "Durable storage is required for the live test." });

  const existing = await readFlightAlertSelfTest(installId);
  if (existing?.status === "armed"
      && existing.departureAt
      && Date.parse(existing.departureAt) > Date.now() - 2 * 60 * 60_000) {
    if (existing.confirmationPushSent !== true && existing.flightNumber) {
      const registration = await registerFlightWatch({
        appInstallId: installId,
        deviceToken,
        itemId: randomUUID(),
        flightNumber: existing.flightNumber,
        date: existing.flightDate,
        departureAt: existing.departureAt,
        originAirport: existing.originAirport,
        destinationAirport: existing.destinationAirport,
        subscribeToAlerts: true
      });
      if (registration.status >= 300) {
        const error = "error" in registration.body
          ? registration.body.error
          : "Could not link the current APNs device token to the existing flight alert.";
        const relinkFailed = {
          ...existing,
          confirmationPushSent: false,
          confirmationPushError: error,
          updatedAt: new Date().toISOString()
        };
        await saveFlightAlertSelfTest(relinkFailed);
        return res.status(502).json(relinkFailed);
      }

      const confirmation = await sendAPNsAlert([deviceToken], {
        title: "Voya live test armed",
        body: `${existing.flightNumber} ${existing.originAirport ?? ""}–${existing.destinationAirport ?? ""}: waiting for FlightAware to assign the gate.`,
        threadId: `self-test-${existing.flightNumber}`,
        data: { eventType: "flight_alert_test_armed", flightNumber: existing.flightNumber, flightDate: existing.flightDate }
      });
      const retried = {
        ...existing,
        confirmationPushSent: confirmation.sent > 0,
        confirmationPushError: confirmation.errors[0],
        updatedAt: new Date().toISOString()
      };
      await saveFlightAlertSelfTest(retried);
      return res.status(200).json(retried);
    }
    return res.status(200).json(existing);
  }

  const now = new Date().toISOString();
  await saveFlightAlertSelfTest({ status: "searching", installId, createdAt: now, updatedAt: now });

  try {
    const flight = await findFlightWithoutGate();
    const registration = await registerFlightWatch({
      appInstallId: installId,
      deviceToken,
      itemId: randomUUID(),
      flightNumber: flight.flightNumber,
      date: flight.flightDate,
      departureAt: flight.departureAt,
      originAirport: flight.originAirport,
      destinationAirport: flight.destinationAirport,
      subscribeToAlerts: true
    });
    const alertWatch = "alertWatch" in registration.body ? registration.body.alertWatch : undefined;
    if (registration.status >= 300 || !alertWatch?.subscribed) {
      const reason = alertWatch && "error" in alertWatch
        ? alertWatch.error
        : "FlightAware did not confirm the alert subscription.";
      throw new Error(`FlightAware alert registration failed: ${reason}`);
    }

    const monitoring = "monitoring" in registration.body ? registration.body.monitoring : undefined;
    const confirmation = await sendAPNsAlert([deviceToken], {
      title: "Voya live test armed",
      body: `${flight.flightNumber} ${flight.originAirport}–${flight.destinationAirport}: waiting for FlightAware to assign the gate.`,
      threadId: `self-test-${flight.flightNumber}`,
      data: { eventType: "flight_alert_test_armed", flightNumber: flight.flightNumber, flightDate: flight.flightDate }
    });
    const record: FlightAlertSelfTestRecord = {
      status: "armed",
      installId,
      flightNumber: flight.flightNumber,
      flightDate: flight.flightDate,
      originAirport: flight.originAirport,
      destinationAirport: flight.destinationAirport,
      departureAt: flight.departureAt,
      alertId: "alertId" in alertWatch ? alertWatch.alertId : undefined,
      monitoringState: monitoring?.state,
      fallbackPolling: monitoring?.fallbackPolling,
      confirmationPushSent: confirmation.sent > 0,
      confirmationPushError: confirmation.errors[0],
      createdAt: now,
      updatedAt: new Date().toISOString()
    };
    await saveFlightAlertSelfTest(record);
    return res.status(202).json(record);
  } catch (error) {
    const failed: FlightAlertSelfTestRecord = {
      status: "failed",
      installId,
      createdAt: now,
      updatedAt: new Date().toISOString(),
      error: error instanceof Error ? error.message : "Live flight alert test failed."
    };
    await saveFlightAlertSelfTest(failed);
    return res.status(502).json(failed);
  }
}
