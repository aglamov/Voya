import type { VercelRequest, VercelResponse } from "@vercel/node";
import { timingSafeEqual } from "node:crypto";
import { sendAPNsAlert } from "./_apns.js";
import {
  fallbackPushTokens,
  normalizeFlightDate,
  normalizeFlightNumber,
  redisCommand,
  registeredTokensForFlight,
  storageConfigured
} from "./_storage.js";

type FlightAwareAlertPayload = {
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
  [key: string]: unknown;
};

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : undefined;
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
  if (!actual) {
    return false;
  }

  const encoder = new TextEncoder();
  const actualBuffer = encoder.encode(actual);
  const expectedBuffer = encoder.encode(expected);
  return actualBuffer.length === expectedBuffer.length && timingSafeEqual(actualBuffer, expectedBuffer);
}

function authorizeWebhook(req: VercelRequest) {
  const expected = configuredWebhookSecret();
  return !expected || secretsMatch(requestWebhookSecret(req), expected);
}

function eventType(payload: FlightAwareAlertPayload) {
  return clean(payload.eventcode)
    ?? clean(payload.event_code)
    ?? clean(payload.event)
    ?? "flight_update";
}

function headline(payload: FlightAwareAlertPayload) {
  const flight = clean(payload.ident_iata) ?? clean(payload.ident) ?? "Flight";
  const event = eventType(payload).replace(/_/g, " ");
  return `${flight}: ${event}`;
}

function flightDate(payload: FlightAwareAlertPayload) {
  const candidates = [
    clean(payload.scheduled_out),
    clean(payload.estimated_out),
    clean(payload.actual_out),
    clean(payload.scheduled_in),
    clean(payload.estimated_in),
    clean(payload.actual_in)
  ];
  for (const candidate of candidates) {
    const date = normalizeFlightDate(candidate);
    if (date) {
      return date;
    }
  }

  return undefined;
}

function stateKey(flightNumber: string, date?: string) {
  return `voya:flight-alert-state:${flightNumber}:${date ?? "any"}`;
}

type StoredFlightAlertState = {
  departureGate?: string;
  arrivalGate?: string;
  departureTerminal?: string;
  arrivalTerminal?: string;
  eventType?: string;
  updatedAt?: string;
};

function changed(previous: string | undefined, next: string | undefined) {
  return Boolean(previous && next && previous !== next);
}

function pushCopy(
  normalized: {
    eventType: string;
    flightNumber?: string;
    gate: {
      departureTerminal?: string;
      departureGate?: string;
      arrivalTerminal?: string;
      arrivalGate?: string;
    };
    detail?: string;
    headline: string;
  },
  previous?: StoredFlightAlertState
) {
  const flight = normalized.flightNumber ?? "Flight";
  const event = normalized.eventType.toLowerCase();
  const departureGate = normalized.gate.departureGate;
  const arrivalGate = normalized.gate.arrivalGate;
  const departureTerminal = normalized.gate.departureTerminal;

  if (departureGate && previous?.departureGate && previous.departureGate !== departureGate) {
    return {
      title: `${flight} gate changed`,
      body: `Gate ${previous.departureGate} -> ${departureGate}${departureTerminal ? `, terminal ${departureTerminal}` : ""}.`
    };
  }

  if (departureGate && event.includes("gate")) {
    return {
      title: `${flight} gate update`,
      body: `Departure gate is ${departureGate}${departureTerminal ? `, terminal ${departureTerminal}` : ""}.`
    };
  }

  if (arrivalGate && previous?.arrivalGate && previous.arrivalGate !== arrivalGate) {
    return {
      title: `${flight} arrival gate changed`,
      body: `Arrival gate ${previous.arrivalGate} -> ${arrivalGate}.`
    };
  }

  if (event.includes("cancel")) {
    return {
      title: `${flight} cancelled`,
      body: normalized.detail ?? normalized.headline
    };
  }

  if (event.includes("diversion") || event.includes("divert")) {
    return {
      title: `${flight} diverted`,
      body: normalized.detail ?? normalized.headline
    };
  }

  if (event.includes("delay") || event.includes("schedule")) {
    return {
      title: `${flight} schedule update`,
      body: normalized.detail ?? normalized.headline
    };
  }

  return undefined;
}

async function previousState(flightNumber: string, date?: string) {
  if (!storageConfigured()) {
    return undefined;
  }

  const raw = await redisCommand<string>(["GET", stateKey(flightNumber, date)]);
  if (!raw) {
    return undefined;
  }

  try {
    return JSON.parse(raw) as StoredFlightAlertState;
  } catch {
    return undefined;
  }
}

async function saveState(flightNumber: string, date: string | undefined, state: StoredFlightAlertState) {
  if (!storageConfigured()) {
    return;
  }

  await redisCommand(["SET", stateKey(flightNumber, date), JSON.stringify(state), "EX", 14 * 24 * 60 * 60]);
}

async function alreadyProcessed(idempotencyKey: string) {
  if (!storageConfigured()) {
    return false;
  }

  const result = await redisCommand<string | null>(["SET", `voya:flight-alert-event:${idempotencyKey}`, "1", "EX", 24 * 60 * 60, "NX"]);
  return result !== "OK";
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  if (!authorizeWebhook(req)) {
    return res.status(401).json({ error: "Unauthorized FlightAware alert callback." });
  }

  const payload = req.body as FlightAwareAlertPayload;
  const normalized = {
    provider: "flightaware",
    eventType: eventType(payload),
    providerFlightId: clean(payload.fa_flight_id),
    flightNumber: normalizeFlightNumber(clean(payload.ident_iata) ?? clean(payload.ident)),
    flightDate: flightDate(payload),
    headline: headline(payload),
    detail: clean(payload.summary) ?? clean(payload.description) ?? clean(payload.status),
    gate: {
      departureTerminal: clean(payload.terminal_origin),
      departureGate: clean(payload.gate_origin),
      arrivalTerminal: clean(payload.terminal_destination),
      arrivalGate: clean(payload.gate_destination)
    },
    timing: {
      estimatedDepartureAt: clean(payload.estimated_out),
      estimatedArrivalAt: clean(payload.estimated_in),
      actualDepartureAt: clean(payload.actual_out),
      actualArrivalAt: clean(payload.actual_in)
    },
    receivedAt: new Date().toISOString()
  };

  console.log("FlightAware alert received", normalized);

  const flightNumber = normalized.flightNumber;
  if (!flightNumber) {
    return res.status(202).json({
      accepted: true,
      alert: normalized,
      push: {
        attempted: false,
        reason: "Flight number missing from alert payload."
      }
    });
  }

  const previous = await previousState(flightNumber, normalized.flightDate);
  const nextState: StoredFlightAlertState = {
    departureGate: normalized.gate.departureGate,
    arrivalGate: normalized.gate.arrivalGate,
    departureTerminal: normalized.gate.departureTerminal,
    arrivalTerminal: normalized.gate.arrivalTerminal,
    eventType: normalized.eventType,
    updatedAt: normalized.receivedAt
  };
  const idempotencyKey = [
    flightNumber,
    normalized.flightDate ?? "any",
    normalized.eventType,
    normalized.gate.departureTerminal,
    normalized.gate.departureGate,
    normalized.gate.arrivalTerminal,
    normalized.gate.arrivalGate,
    normalized.timing.estimatedDepartureAt,
    normalized.timing.estimatedArrivalAt
  ].filter(Boolean).join(":");
  const duplicate = await alreadyProcessed(idempotencyKey);
  await saveState(flightNumber, normalized.flightDate, nextState);

  const copy = pushCopy(normalized, previous);
  const hasGateDiff = changed(previous?.departureGate, normalized.gate.departureGate)
    || changed(previous?.arrivalGate, normalized.gate.arrivalGate)
    || changed(previous?.departureTerminal, normalized.gate.departureTerminal)
    || changed(previous?.arrivalTerminal, normalized.gate.arrivalTerminal);
  const eventLooksImportant = /gate|delay|schedule|cancel|divert/i.test(normalized.eventType);
  const shouldPush = !duplicate && copy && (hasGateDiff || eventLooksImportant);
  const storedTokens = await registeredTokensForFlight(flightNumber, normalized.flightDate);
  const testTokens = storedTokens.length ? [] : fallbackPushTokens();
  const deviceTokens = [...new Set([...storedTokens, ...testTokens])];
  const push = shouldPush && deviceTokens.length
    ? await sendAPNsAlert(deviceTokens, {
        title: copy.title,
        body: copy.body,
        threadId: flightNumber,
        data: {
          provider: "flightaware",
          eventType: normalized.eventType,
          flightNumber,
          flightDate: normalized.flightDate,
          gate: normalized.gate
        }
      })
    : {
        configured: false,
        attempted: deviceTokens.length,
        sent: 0,
        failed: 0,
        errors: shouldPush ? ["No registered device tokens for this flight."] : ["Alert did not produce a new traveler-facing push."]
      };

  return res.status(202).json({
    accepted: true,
    alert: normalized,
    push: {
      duplicate,
      shouldPush: Boolean(shouldPush),
      matchedRegisteredDevices: storedTokens.length,
      matchedFallbackDevices: testTokens.length,
      ...push
    }
  });
}
