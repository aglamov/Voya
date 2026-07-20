import { dispatchGuardianEvent } from "./_agents.js";
import {
  fallbackPushTokens,
  flightWatchKey,
  flightWatchTargetsKey,
  redisCommand,
  registeredTargetsForFlight,
  storageConfigured,
  type RegisteredFlightTarget
} from "./_storage.js";
import {
  enqueueTravelEventNotifications,
  newTravelEvent,
  recordTravelEvent,
  type TravelEvent,
  type TravelEventType
} from "./_travel-events.js";
import { markFlightAlertSelfTestGateReceived } from "./_flight-self-test.js";

export type FlightSignal = {
  provider: "flightaware";
  source: "webhook" | "poll";
  eventType: string;
  providerFlightId?: string;
  flightNumber: string;
  flightDate?: string;
  headline: string;
  detail?: string;
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
    actualDepartureAt?: string;
    actualArrivalAt?: string;
  };
  receivedAt: string;
};

export type StoredFlightAlertState = {
  departureGate?: string;
  arrivalGate?: string;
  departureTerminal?: string;
  arrivalTerminal?: string;
  scheduledDepartureAt?: string;
  scheduledArrivalAt?: string;
  estimatedDepartureAt?: string;
  estimatedArrivalAt?: string;
  actualDepartureAt?: string;
  actualArrivalAt?: string;
  eventType?: string;
  updatedAt?: string;
};

type ClassifiedFlightEvent = {
  type: TravelEventType;
  title: string;
  summary: string;
  severity: TravelEvent["severity"];
  facts: Record<string, unknown>;
};

function stateKey(flightNumber: string, date?: string) {
  return `voya:flight-alert-state:${flightNumber}:${date ?? "any"}`;
}

function cleanComparable(value: string | undefined) {
  return value?.trim().toUpperCase() || undefined;
}

function changed(previous: string | undefined, next: string | undefined) {
  const before = cleanComparable(previous);
  const after = cleanComparable(next);
  return Boolean(before && after && before !== after);
}

function shiftMinutes(previous: string | undefined, next: string | undefined) {
  if (!previous || !next) return undefined;
  const difference = Math.round((Date.parse(next) - Date.parse(previous)) / 60_000);
  return Number.isFinite(difference) ? difference : undefined;
}

function meaningfulTimeShift(signal: FlightSignal, previous?: StoredFlightAlertState) {
  const departureShift = shiftMinutes(
    previous?.estimatedDepartureAt ?? previous?.scheduledDepartureAt ?? signal.timing.scheduledDepartureAt,
    signal.timing.estimatedDepartureAt
  );
  const arrivalShift = shiftMinutes(
    previous?.estimatedArrivalAt ?? previous?.scheduledArrivalAt ?? signal.timing.scheduledArrivalAt,
    signal.timing.estimatedArrivalAt
  );
  const meaningful = [departureShift, arrivalShift]
    .filter((value): value is number => value !== undefined)
    .sort((lhs, rhs) => Math.abs(rhs) - Math.abs(lhs))[0];
  return meaningful !== undefined && Math.abs(meaningful) >= 15 ? meaningful : undefined;
}

export function classifyFlightEvent(signal: FlightSignal, previous?: StoredFlightAlertState): ClassifiedFlightEvent | undefined {
  const flight = signal.flightNumber;
  const departureGate = cleanComparable(signal.gate.departureGate);
  const arrivalGate = cleanComparable(signal.gate.arrivalGate);
  const departureTerminal = cleanComparable(signal.gate.departureTerminal);
  const arrivalTerminal = cleanComparable(signal.gate.arrivalTerminal);
  const event = signal.eventType.toLowerCase();

  if (departureGate && changed(previous?.departureGate, departureGate)) {
    return {
      type: "gate_changed",
      title: `${flight} gate changed`,
      summary: `Gate ${previous!.departureGate} → ${departureGate}${departureTerminal ? `, terminal ${departureTerminal}` : ""}.`,
      severity: "warning",
      facts: { previousGate: previous?.departureGate, gate: departureGate, terminal: departureTerminal }
    };
  }
  if (departureGate && !previous?.departureGate) {
    return {
      type: "gate_assigned",
      title: `${flight} gate assigned`,
      summary: `Departure gate is ${departureGate}${departureTerminal ? `, terminal ${departureTerminal}` : ""}.`,
      severity: "info",
      facts: { gate: departureGate, terminal: departureTerminal }
    };
  }
  if (arrivalGate && changed(previous?.arrivalGate, arrivalGate)) {
    return {
      type: "arrival_gate_changed",
      title: `${flight} arrival gate changed`,
      summary: `Arrival gate ${previous!.arrivalGate} → ${arrivalGate}${arrivalTerminal ? `, terminal ${arrivalTerminal}` : ""}.`,
      severity: "warning",
      facts: { previousGate: previous?.arrivalGate, gate: arrivalGate, terminal: arrivalTerminal }
    };
  }
  if (arrivalGate && !previous?.arrivalGate) {
    return {
      type: "arrival_gate_assigned",
      title: `${flight} arrival gate assigned`,
      summary: `Arrival gate is ${arrivalGate}${arrivalTerminal ? `, terminal ${arrivalTerminal}` : ""}.`,
      severity: "info",
      facts: { gate: arrivalGate, terminal: arrivalTerminal }
    };
  }
  if (changed(previous?.departureTerminal, departureTerminal) || changed(previous?.arrivalTerminal, arrivalTerminal)) {
    const departureChanged = changed(previous?.departureTerminal, departureTerminal);
    return {
      type: "terminal_changed",
      title: `${flight} terminal changed`,
      summary: departureChanged
        ? `Departure terminal ${previous!.departureTerminal} → ${departureTerminal}.`
        : `Arrival terminal ${previous!.arrivalTerminal} → ${arrivalTerminal}.`,
      severity: "warning",
      facts: {
        departureTerminal,
        arrivalTerminal,
        previousDepartureTerminal: previous?.departureTerminal,
        previousArrivalTerminal: previous?.arrivalTerminal
      }
    };
  }
  if (/cancel/.test(event)) {
    return {
      type: "flight_cancelled",
      title: `${flight} cancelled`,
      summary: signal.detail ?? signal.headline,
      severity: "critical",
      facts: { providerEventType: signal.eventType }
    };
  }
  if (/divert/.test(event)) {
    return {
      type: "flight_diverted",
      title: `${flight} diverted`,
      summary: signal.detail ?? signal.headline,
      severity: "critical",
      facts: { providerEventType: signal.eventType }
    };
  }

  const timeShift = meaningfulTimeShift(signal, previous);
  if (timeShift !== undefined) {
    return {
      type: "flight_delayed",
      title: `${flight} schedule changed`,
      summary: signal.detail ?? `Estimated time moved ${Math.abs(timeShift)} minutes ${timeShift > 0 ? "later" : "earlier"}.`,
      severity: Math.abs(timeShift) >= 45 ? "warning" : "info",
      facts: {
        shiftMinutes: timeShift,
        estimatedDepartureAt: signal.timing.estimatedDepartureAt,
        estimatedArrivalAt: signal.timing.estimatedArrivalAt
      }
    };
  }
  return undefined;
}

function mergedState(signal: FlightSignal, previous?: StoredFlightAlertState): StoredFlightAlertState {
  return {
    departureGate: signal.gate.departureGate ?? previous?.departureGate,
    arrivalGate: signal.gate.arrivalGate ?? previous?.arrivalGate,
    departureTerminal: signal.gate.departureTerminal ?? previous?.departureTerminal,
    arrivalTerminal: signal.gate.arrivalTerminal ?? previous?.arrivalTerminal,
    scheduledDepartureAt: signal.timing.scheduledDepartureAt ?? previous?.scheduledDepartureAt,
    scheduledArrivalAt: signal.timing.scheduledArrivalAt ?? previous?.scheduledArrivalAt,
    estimatedDepartureAt: signal.timing.estimatedDepartureAt ?? previous?.estimatedDepartureAt,
    estimatedArrivalAt: signal.timing.estimatedArrivalAt ?? previous?.estimatedArrivalAt,
    actualDepartureAt: signal.timing.actualDepartureAt ?? previous?.actualDepartureAt,
    actualArrivalAt: signal.timing.actualArrivalAt ?? previous?.actualArrivalAt,
    eventType: signal.eventType,
    updatedAt: signal.receivedAt
  };
}

export async function readFlightAlertState(flightNumber: string, date?: string) {
  if (!storageConfigured()) return undefined;
  const raw = await redisCommand<string>(["GET", stateKey(flightNumber, date)]);
  if (!raw) return undefined;
  try {
    return JSON.parse(raw) as StoredFlightAlertState;
  } catch {
    return undefined;
  }
}

async function saveFlightAlertState(flightNumber: string, date: string | undefined, state: StoredFlightAlertState) {
  if (!storageConfigured()) return;
  await redisCommand(["SET", stateKey(flightNumber, date), JSON.stringify(state), "EX", 14 * 24 * 60 * 60]);
}

async function removeInvalidTargets(flightNumber: string, date: string | undefined, tokens: string[]) {
  for (const token of tokens) {
    await redisCommand(["SREM", `voya:flight-watch:${flightWatchKey(flightNumber, date)}:devices`, token]);
    await redisCommand(["SREM", `voya:flight-watch:${flightWatchKey(flightNumber)}:devices`, token]);
    await redisCommand(["HDEL", flightWatchTargetsKey(flightNumber, date), token]);
    await redisCommand(["HDEL", flightWatchTargetsKey(flightNumber), token]);
  }
}

function targetsOrFallback(targets: RegisteredFlightTarget[]) {
  return targets.length
    ? targets
    : fallbackPushTokens().map((deviceToken) => ({ deviceToken }));
}

export async function processFlightSignal(signal: FlightSignal) {
  const previous = await readFlightAlertState(signal.flightNumber, signal.flightDate);
  const next = mergedState(signal, previous);
  await saveFlightAlertState(signal.flightNumber, signal.flightDate, next);

  const watchMeta = `voya:flight-watch:${flightWatchKey(signal.flightNumber, signal.flightDate)}:meta`;
  await redisCommand([
    "HSET",
    watchMeta,
    signal.source === "webhook" ? "lastProviderEventAt" : "lastCheckedAt",
    signal.receivedAt,
    "lastSignalSource",
    signal.source,
    "lastProviderEventType",
    signal.eventType
  ]);

  const classified = classifyFlightEvent(signal, previous);
  if (!classified) {
    return { event: undefined, state: next, notification: undefined, guardianMissionsDispatched: 0 };
  }

  const storedTargets = await registeredTargetsForFlight(signal.flightNumber, signal.flightDate);
  const deliveryTargets = targetsOrFallback(storedTargets);
  const event = newTravelEvent({
    type: classified.type,
    provider: signal.provider,
    source: signal.source,
    occurredAt: signal.receivedAt,
    receivedAt: signal.receivedAt,
    flightNumber: signal.flightNumber,
    flightDate: signal.flightDate,
    title: classified.title,
    summary: classified.summary,
    severity: classified.severity,
    facts: {
      ...classified.facts,
      providerFlightId: signal.providerFlightId,
      providerEventType: signal.eventType
    }
  });
  const stored = await recordTravelEvent(event, storedTargets);
  const notification = await enqueueTravelEventNotifications(event, deliveryTargets, {
    title: event.title,
    body: event.summary,
    threadId: signal.flightNumber,
    data: {
      provider: signal.provider,
      eventType: event.type,
      flightNumber: signal.flightNumber,
      flightDate: signal.flightDate,
      gate: signal.gate
    }
  });
  if (event.type === "gate_assigned" || event.type === "gate_changed") {
    const installIds = [...new Set(storedTargets.flatMap((target) => target.appInstallId ?? []))];
    await Promise.all(installIds.map((installId) => markFlightAlertSelfTestGateReceived({
      installId,
      flightNumber: signal.flightNumber,
      flightDate: signal.flightDate,
      gate: signal.gate.departureGate,
      terminal: signal.gate.departureTerminal,
      eventId: event.id,
      eventSummary: event.summary,
      receivedAt: signal.receivedAt,
      pushSent: notification.drain.sent > 0
    })));
  }

  const tripIds = [...new Set(storedTargets.flatMap((target) => target.tripId ?? []))];
  const dispatches = await Promise.all(tripIds.map((tripId) => dispatchGuardianEvent(tripId, {
    id: event.id,
    provider: event.provider,
    eventType: event.type,
    flightNumber: signal.flightNumber,
    flightDate: signal.flightDate,
    facts: event.facts,
    occurredAt: event.occurredAt
  })));
  const guardianMissionsDispatched = dispatches.reduce((sum, count) => sum + count, 0);

  await redisCommand(["HSET", watchMeta, "lastTravelEventId", event.id, "lastTravelEventType", event.type]);
  await removeInvalidTargets(signal.flightNumber, signal.flightDate, notification.drain.invalidDeviceTokens);

  return { event, eventStorage: stored, state: next, notification, guardianMissionsDispatched };
}
