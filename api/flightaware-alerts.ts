import type { VercelRequest, VercelResponse } from "@vercel/node";
import { timingSafeEqual } from "node:crypto";
import { processFlightSignal } from "./_flight-events.js";
import { fetchCanonicalFlightSignal } from "./_flight-monitor.js";
import { normalizeFlightDate, normalizeFlightNumber } from "./_storage.js";

export type FlightAwareAlertPayload = {
  eventcode?: string;
  event_code?: string;
  event?: string;
  fa_flight_id?: string;
  ident?: string;
  ident_iata?: string;
  summary?: string;
  description?: string;
  status?: string;
  gate_origin?: string;
  gate_destination?: string;
  terminal_origin?: string;
  terminal_destination?: string;
  scheduled_out?: string;
  scheduled_in?: string;
  estimated_out?: string;
  estimated_in?: string;
  actual_out?: string;
  actual_in?: string;
  long_description?: string;
  short_description?: string;
  flight?: FlightAwareAlertFlight;
  [key: string]: unknown;
};

type FlightAwareAlertFlight = {
  fa_flight_id?: string;
  ident?: string;
  ident_iata?: string;
  gate_origin?: string;
  gate_destination?: string;
  terminal_origin?: string;
  terminal_destination?: string;
  scheduled_out?: string;
  scheduled_in?: string;
  estimated_out?: string;
  estimated_in?: string;
  actual_out?: string;
  actual_in?: string;
};

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() || undefined : undefined;
}

function configuredWebhookSecret() {
  return process.env.FLIGHTAWARE_ALERT_WEBHOOK_SECRET?.trim();
}

function firstHeader(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function requestWebhookSecret(req: VercelRequest) {
  const querySecret = typeof req.query.secret === "string" ? req.query.secret.trim() : undefined;
  const headerSecret = firstHeader(req.headers["x-voya-webhook-secret"])?.trim();
  const authorization = firstHeader(req.headers.authorization)?.trim();
  const bearerSecret = authorization?.toLowerCase().startsWith("bearer ")
    ? authorization.slice("bearer ".length).trim()
    : undefined;
  return querySecret || headerSecret || bearerSecret;
}

function secretsMatch(actual: string | undefined, expected: string) {
  if (!actual) return false;
  const encoder = new TextEncoder();
  const actualBuffer = encoder.encode(actual);
  const expectedBuffer = encoder.encode(expected);
  return actualBuffer.length === expectedBuffer.length && timingSafeEqual(actualBuffer, expectedBuffer);
}

function authorizeWebhook(req: VercelRequest) {
  const expected = configuredWebhookSecret();
  return Boolean(expected && secretsMatch(requestWebhookSecret(req), expected));
}

function eventType(payload: FlightAwareAlertPayload) {
  return clean(payload.eventcode)
    ?? clean(payload.event_code)
    ?? clean(payload.event)
    ?? "flight_update";
}

function flightValue(payload: FlightAwareAlertPayload, key: keyof FlightAwareAlertFlight) {
  return clean(payload.flight?.[key]) ?? clean(payload[key]);
}

function flightDate(payload: FlightAwareAlertPayload) {
  const candidates = [
    flightValue(payload, "scheduled_out"),
    flightValue(payload, "estimated_out"),
    flightValue(payload, "actual_out"),
    flightValue(payload, "scheduled_in"),
    flightValue(payload, "estimated_in"),
    flightValue(payload, "actual_in")
  ];
  for (const candidate of candidates) {
    const date = normalizeFlightDate(candidate);
    if (date) return date;
  }
  return undefined;
}

export function normalizeFlightAwareAlert(payload: FlightAwareAlertPayload, now: Date = new Date()) {
  const number = normalizeFlightNumber(flightValue(payload, "ident_iata") ?? flightValue(payload, "ident"));
  const providerEventType = eventType(payload);
  return {
    provider: "flightaware" as const,
    eventType: providerEventType,
    providerFlightId: flightValue(payload, "fa_flight_id"),
    flightNumber: number,
    flightDate: flightDate(payload),
    headline: `${number ?? "Flight"}: ${providerEventType.replace(/_/g, " ")}`,
    detail: clean(payload.summary)
      ?? clean(payload.short_description)
      ?? clean(payload.long_description)
      ?? clean(payload.description)
      ?? clean(payload.status),
    gate: {
      departureTerminal: flightValue(payload, "terminal_origin"),
      departureGate: flightValue(payload, "gate_origin"),
      arrivalTerminal: flightValue(payload, "terminal_destination"),
      arrivalGate: flightValue(payload, "gate_destination")
    },
    timing: {
      scheduledDepartureAt: flightValue(payload, "scheduled_out"),
      scheduledArrivalAt: flightValue(payload, "scheduled_in"),
      estimatedDepartureAt: flightValue(payload, "estimated_out"),
      estimatedArrivalAt: flightValue(payload, "estimated_in"),
      actualDepartureAt: flightValue(payload, "actual_out"),
      actualArrivalAt: flightValue(payload, "actual_in")
    },
    receivedAt: now.toISOString()
  };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!configuredWebhookSecret()) {
    return res.status(503).json({ error: "FlightAware webhook secret is not configured." });
  }
  if (!authorizeWebhook(req)) {
    return res.status(401).json({ error: "Unauthorized FlightAware alert callback." });
  }

  const normalized = normalizeFlightAwareAlert(req.body as FlightAwareAlertPayload);
  console.log("FlightAware alert received", normalized);
  if (!normalized.flightNumber) {
    return res.status(200).json({
      accepted: true,
      alert: normalized,
      processing: { skipped: true, reason: "Flight number missing from alert payload." }
    });
  }

  try {
    const verified = await fetchCanonicalFlightSignal({
      flightNumber: normalized.flightNumber,
      date: normalized.flightDate,
      departureAt: normalized.timing.scheduledDepartureAt ?? normalized.timing.estimatedDepartureAt,
      source: "webhook",
      providerEventType: normalized.eventType
    }).catch(() => undefined);
    const processing = await processFlightSignal({
      ...normalized,
      ...(verified ?? {}),
      source: "webhook",
      flightNumber: normalized.flightNumber,
      eventType: normalized.eventType,
      detail: verified?.detail ?? normalized.detail,
      gate: {
        departureTerminal: verified?.gate.departureTerminal ?? normalized.gate.departureTerminal,
        departureGate: verified?.gate.departureGate ?? normalized.gate.departureGate,
        arrivalTerminal: verified?.gate.arrivalTerminal ?? normalized.gate.arrivalTerminal,
        arrivalGate: verified?.gate.arrivalGate ?? normalized.gate.arrivalGate
      },
      timing: {
        scheduledDepartureAt: verified?.timing.scheduledDepartureAt ?? normalized.timing.scheduledDepartureAt,
        scheduledArrivalAt: verified?.timing.scheduledArrivalAt ?? normalized.timing.scheduledArrivalAt,
        estimatedDepartureAt: verified?.timing.estimatedDepartureAt ?? normalized.timing.estimatedDepartureAt,
        estimatedArrivalAt: verified?.timing.estimatedArrivalAt ?? normalized.timing.estimatedArrivalAt,
        actualDepartureAt: verified?.timing.actualDepartureAt ?? normalized.timing.actualDepartureAt,
        actualArrivalAt: verified?.timing.actualArrivalAt ?? normalized.timing.actualArrivalAt
      }
    });
    return res.status(200).json({
      accepted: true,
      alert: normalized,
      verification: verified ? "canonical_provider_snapshot" : "webhook_payload",
      processing
    });
  } catch (error) {
    console.error("FlightAware alert processing failed", error);
    return res.status(500).json({
      accepted: false,
      error: error instanceof Error ? error.message : "Flight event processing failed."
    });
  }
}
