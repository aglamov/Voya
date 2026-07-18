import type { VercelRequest, VercelResponse } from "@vercel/node";
import { createHash, timingSafeEqual } from "node:crypto";
import { sendAPNsAlert } from "./_apns.js";
import {
  fallbackPushTokens,
  flightWatchKey,
  flightWatchTargetsKey,
  normalizeFlightDate,
  normalizeFlightNumber,
  redisCommand,
  registeredTargetsForFlight,
  storageConfigured,
  type RegisteredFlightTarget
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
  return Boolean(expected && secretsMatch(requestWebhookSecret(req), expected));
}

function eventType(payload: FlightAwareAlertPayload) {
  return clean(payload.eventcode)
    ?? clean(payload.event_code)
    ?? clean(payload.event)
    ?? "flight_update";
}

function flightValue(
  payload: FlightAwareAlertPayload,
  key: keyof FlightAwareAlertFlight
) {
  return clean(payload.flight?.[key]) ?? clean(payload[key]);
}

function headline(payload: FlightAwareAlertPayload) {
  const flight = flightValue(payload, "ident_iata") ?? flightValue(payload, "ident") ?? "Flight";
  const event = eventType(payload).replace(/_/g, " ");
  return `${flight}: ${event}`;
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
    if (date) {
      return date;
    }
  }

  return undefined;
}

export function normalizeFlightAwareAlert(payload: FlightAwareAlertPayload, now: Date = new Date()) {
  return {
    provider: "flightaware",
    eventType: eventType(payload),
    providerFlightId: flightValue(payload, "fa_flight_id"),
    flightNumber: normalizeFlightNumber(flightValue(payload, "ident_iata") ?? flightValue(payload, "ident")),
    flightDate: flightDate(payload),
    headline: headline(payload),
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

function stateKey(flightNumber: string, date?: string) {
  return `voya:flight-alert-state:${flightNumber}:${date ?? "any"}`;
}

type StoredFlightAlertState = {
  departureGate?: string;
  arrivalGate?: string;
  departureTerminal?: string;
  arrivalTerminal?: string;
  scheduledDepartureAt?: string;
  scheduledArrivalAt?: string;
  estimatedDepartureAt?: string;
  estimatedArrivalAt?: string;
  eventType?: string;
  updatedAt?: string;
};

function changed(previous: string | undefined, next: string | undefined) {
  return Boolean(previous && next && previous !== next);
}

function shiftMinutes(previous: string | undefined, next: string | undefined) {
  if (!previous || !next) return undefined;
  const difference = Math.round((Date.parse(next) - Date.parse(previous)) / 60_000);
  return Number.isFinite(difference) ? difference : undefined;
}

function meaningfulTimeShift(normalized: { timing: { scheduledDepartureAt?: string; scheduledArrivalAt?: string; estimatedDepartureAt?: string; estimatedArrivalAt?: string } }, previous?: StoredFlightAlertState) {
  const departureShift = shiftMinutes(
    previous?.estimatedDepartureAt ?? normalized.timing.scheduledDepartureAt,
    normalized.timing.estimatedDepartureAt
  );
  const arrivalShift = shiftMinutes(
    previous?.estimatedArrivalAt ?? normalized.timing.scheduledArrivalAt,
    normalized.timing.estimatedArrivalAt
  );
  const meaningful = [departureShift, arrivalShift]
    .filter((value): value is number => value !== undefined)
    .sort((lhs, rhs) => Math.abs(rhs) - Math.abs(lhs))[0];
  return meaningful !== undefined && Math.abs(meaningful) >= 15 ? meaningful : undefined;
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
    timing: {
      scheduledDepartureAt?: string;
      scheduledArrivalAt?: string;
      estimatedDepartureAt?: string;
      estimatedArrivalAt?: string;
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
  const timeShift = meaningfulTimeShift(normalized, previous);

  if (departureGate && previous?.departureGate && previous.departureGate !== departureGate) {
    return {
      title: `${flight} gate changed`,
      body: `Gate ${previous.departureGate} -> ${departureGate}${departureTerminal ? `, terminal ${departureTerminal}` : ""}.`
    };
  }

  if (departureGate && !previous?.departureGate) {
    return {
      title: `${flight} gate posted`,
      body: `Departure gate is ${departureGate}${departureTerminal ? `, terminal ${departureTerminal}` : ""}.`
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

  if (arrivalGate && !previous?.arrivalGate) {
    return {
      title: `${flight} arrival gate posted`,
      body: `Arrival gate is ${arrivalGate}.`
    };
  }

  if (departureTerminal && previous?.departureTerminal && previous.departureTerminal !== departureTerminal) {
    return {
      title: `${flight} terminal changed`,
      body: `Departure terminal ${previous.departureTerminal} -> ${departureTerminal}.`
    };
  }

  if (normalized.gate.arrivalTerminal && previous?.arrivalTerminal && previous.arrivalTerminal !== normalized.gate.arrivalTerminal) {
    return {
      title: `${flight} arrival terminal changed`,
      body: `Arrival terminal ${previous.arrivalTerminal} -> ${normalized.gate.arrivalTerminal}.`
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


  if (timeShift !== undefined) {
    const direction = timeShift > 0 ? "later" : "earlier";
    return {
      title: `${flight} schedule changed`,
      body: normalized.detail ?? `Estimated time moved ${Math.abs(timeShift)} minutes ${direction}.`
    };
  }

  // FlightAware reports gate assignments through the bundled `change` event,
  // not only through an event whose code contains `gate`. This fallback also
  // lets a provider retry recover a delivery that previously failed after the
  // latest state had already been persisted.
  if (departureGate && (event.includes("gate") || event.includes("change"))) {
    return {
      title: `${flight} gate update`,
      body: `Departure gate is ${departureGate}${departureTerminal ? `, terminal ${departureTerminal}` : ""}.`
    };
  }

  if (arrivalGate && (event.includes("gate") || event.includes("change"))) {
    return {
      title: `${flight} arrival gate update`,
      body: `Arrival gate is ${arrivalGate}.`
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

function deliveryKey(idempotencyKey: string, deviceToken: string) {
  const recipient = createHash("sha256").update(deviceToken).digest("hex");
  return `voya:flight-alert-delivery:${idempotencyKey}:${recipient}`;
}

async function claimDelivery(idempotencyKey: string, deviceToken: string) {
  if (!storageConfigured()) {
    return true;
  }

  const result = await redisCommand<string | null>([
    "SET",
    deliveryKey(idempotencyKey, deviceToken),
    "1",
    "EX",
    24 * 60 * 60,
    "NX"
  ]);
  return result === "OK";
}

async function releaseDelivery(idempotencyKey: string, deviceToken: string) {
  if (!storageConfigured()) {
    return;
  }
  await redisCommand(["DEL", deliveryKey(idempotencyKey, deviceToken)]);
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

  const payload = req.body as FlightAwareAlertPayload;
  const normalized = normalizeFlightAwareAlert(payload);

  console.log("FlightAware alert received", normalized);

  const flightNumber = normalized.flightNumber;
  if (!flightNumber) {
    return res.status(200).json({
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
    departureGate: normalized.gate.departureGate ?? previous?.departureGate,
    arrivalGate: normalized.gate.arrivalGate ?? previous?.arrivalGate,
    departureTerminal: normalized.gate.departureTerminal ?? previous?.departureTerminal,
    arrivalTerminal: normalized.gate.arrivalTerminal ?? previous?.arrivalTerminal,
    scheduledDepartureAt: normalized.timing.scheduledDepartureAt ?? previous?.scheduledDepartureAt,
    scheduledArrivalAt: normalized.timing.scheduledArrivalAt ?? previous?.scheduledArrivalAt,
    estimatedDepartureAt: normalized.timing.estimatedDepartureAt ?? previous?.estimatedDepartureAt,
    estimatedArrivalAt: normalized.timing.estimatedArrivalAt ?? previous?.estimatedArrivalAt,
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
  await saveState(flightNumber, normalized.flightDate, nextState);

  const copy = pushCopy(normalized, previous);
  const hasGateDiff = changed(previous?.departureGate, normalized.gate.departureGate)
    || changed(previous?.arrivalGate, normalized.gate.arrivalGate)
    || changed(previous?.departureTerminal, normalized.gate.departureTerminal)
    || changed(previous?.arrivalTerminal, normalized.gate.arrivalTerminal);
  const hasNewGateInfo = Boolean((normalized.gate.departureGate && !previous?.departureGate)
    || (normalized.gate.arrivalGate && !previous?.arrivalGate));
  const eventLooksImportant = /gate|change|delay|schedule|cancel|divert/i.test(normalized.eventType);
  const hasTimeDiff = meaningfulTimeShift(normalized, previous) !== undefined;
  const shouldPush = copy && (hasGateDiff || hasNewGateInfo || hasTimeDiff || eventLooksImportant);
  const storedTargets = await registeredTargetsForFlight(flightNumber, normalized.flightDate);
  const testTokens = storedTargets.length ? [] : fallbackPushTokens();
  const targets: RegisteredFlightTarget[] = storedTargets.length
    ? storedTargets
    : testTokens.map((deviceToken) => ({ deviceToken }));
  const deliveryResults: Awaited<ReturnType<typeof sendAPNsAlert>>[] = [];
  let duplicateTargets = 0;
  if (shouldPush && targets.length) {
    for (let index = 0; index < targets.length; index += 10) {
      const batch = await Promise.all(targets.slice(index, index + 10).map(async (target) => {
        const claimed = await claimDelivery(idempotencyKey, target.deviceToken);
        if (!claimed) {
          duplicateTargets += 1;
          return undefined;
        }
        const result = await sendAPNsAlert([target.deviceToken], {
          title: copy.title,
          body: copy.body,
          threadId: flightNumber,
          data: {
            provider: "flightaware",
            eventType: normalized.eventType,
            flightNumber,
            flightDate: normalized.flightDate,
            gate: normalized.gate,
            tripId: target.tripId,
            itemId: target.itemId
          }
        });
        if (result.sent === 0) {
          // A provider retry must be able to redeliver after transient APNs or
          // configuration failures. Only successful recipient deliveries stay
          // deduplicated for the event window.
          await releaseDelivery(idempotencyKey, target.deviceToken);
        }
        return result;
      }));
      deliveryResults.push(...batch.filter((result): result is Awaited<ReturnType<typeof sendAPNsAlert>> => Boolean(result)));
    }
  }
  const push = deliveryResults.length
    ? {
        configured: deliveryResults.some((result) => result.configured),
        attempted: deliveryResults.reduce((sum, result) => sum + result.attempted, 0),
        sent: deliveryResults.reduce((sum, result) => sum + result.sent, 0),
        failed: deliveryResults.reduce((sum, result) => sum + result.failed, 0),
        errors: deliveryResults.flatMap((result) => result.errors),
        invalidDeviceTokens: deliveryResults.flatMap((result) => result.invalidDeviceTokens)
      }
    : {
        configured: false,
        attempted: 0,
        sent: 0,
        failed: 0,
        errors: !shouldPush
          ? ["Alert did not produce a new traveler-facing push."]
          : targets.length === 0
            ? ["No registered device tokens for this flight."]
            : [],
        invalidDeviceTokens: [] as string[]
      };

  for (const token of push.invalidDeviceTokens) {
    await redisCommand(["SREM", `voya:flight-watch:${flightWatchKey(flightNumber, normalized.flightDate)}:devices`, token]);
    await redisCommand(["SREM", `voya:flight-watch:${flightWatchKey(flightNumber)}:devices`, token]);
    await redisCommand(["HDEL", flightWatchTargetsKey(flightNumber, normalized.flightDate), token]);
    await redisCommand(["HDEL", flightWatchTargetsKey(flightNumber), token]);
  }

  return res.status(200).json({
    accepted: true,
    alert: normalized,
    push: {
      duplicate: Boolean(targets.length && duplicateTargets === targets.length),
      duplicateTargets,
      shouldPush: Boolean(shouldPush),
      matchedRegisteredDevices: storedTargets.length,
      matchedFallbackDevices: testTokens.length,
      ...push
    }
  });
}
