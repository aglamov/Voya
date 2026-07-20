import { createHash, randomUUID } from "node:crypto";
import { sendAPNsAlert, type APNsAlert } from "./_apns.js";
import {
  normalizeDeviceToken,
  redisCommand,
  storageConfigured,
  type RegisteredFlightTarget
} from "./_storage.js";

export type TravelEventType =
  | "gate_assigned"
  | "gate_changed"
  | "arrival_gate_assigned"
  | "arrival_gate_changed"
  | "terminal_changed"
  | "flight_delayed"
  | "flight_cancelled"
  | "flight_diverted"
  | "flight_updated";

export type TravelEvent = {
  id: string;
  type: TravelEventType;
  provider: string;
  source: "webhook" | "poll" | "app";
  occurredAt: string;
  receivedAt: string;
  flightNumber?: string;
  flightDate?: string;
  title: string;
  summary: string;
  severity: "info" | "warning" | "critical";
  facts: Record<string, unknown>;
};

export type TravelEventTarget = Pick<RegisteredFlightTarget, "appInstallId" | "tripId" | "itemId">;

type NotificationOutboxDelivery = {
  id: string;
  eventId: string;
  deviceToken: string;
  target: TravelEventTarget;
  alert: APNsAlert;
  status: "pending" | "retrying" | "sent" | "failed";
  attempts: number;
  createdAt: string;
  updatedAt: string;
  nextAttemptAt: string;
  sentAt?: string;
  lastError?: string;
};

type OutboxDrainResult = {
  attempted: number;
  sent: number;
  failed: number;
  pending: number;
  invalidDeviceTokens: string[];
  errors: string[];
};

const EVENT_TTL_SECONDS = 180 * 24 * 60 * 60;
const DELIVERY_TTL_SECONDS = 30 * 24 * 60 * 60;
const OUTBOX_DUE_KEY = "voya:notification-outbox:due";

function digest(value: string) {
  return createHash("sha256").update(value).digest("hex");
}

export function travelEventId(input: Omit<TravelEvent, "id">) {
  return digest(JSON.stringify({
    type: input.type,
    provider: input.provider,
    flightNumber: input.flightNumber,
    flightDate: input.flightDate,
    facts: input.facts
  })).slice(0, 40);
}

function eventKey(id: string) {
  return `voya:travel-event:${id}`;
}

function eventIndexKey(installId: string) {
  return `voya:travel-events:${installId}`;
}

function tripEventIndexKey(installId: string, tripId: string) {
  return `voya:travel-events:${installId}:trip:${tripId}`;
}

function deliveryKey(id: string) {
  return `voya:notification-outbox:${id}`;
}

function deliveryId(eventId: string, deviceToken: string) {
  return `${eventId}:${digest(deviceToken).slice(0, 32)}`;
}

function unixMilliseconds(value: string) {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : Date.now();
}

export function newTravelEvent(input: Omit<TravelEvent, "id">): TravelEvent {
  return { ...input, id: travelEventId(input) };
}

export async function recordTravelEvent(event: TravelEvent, targets: TravelEventTarget[]) {
  if (!storageConfigured()) return { stored: false, duplicate: false };

  const stored = await redisCommand<string | null>([
    "SET",
    eventKey(event.id),
    JSON.stringify(event),
    "EX",
    EVENT_TTL_SECONDS,
    "NX"
  ]);
  const score = unixMilliseconds(event.receivedAt);
  const uniqueTargets = new Map<string, TravelEventTarget>();
  for (const target of targets) {
    if (!target.appInstallId) continue;
    uniqueTargets.set(`${target.appInstallId}:${target.tripId ?? ""}`, target);
  }
  for (const target of uniqueTargets.values()) {
    const installKey = eventIndexKey(target.appInstallId!);
    await redisCommand(["ZADD", installKey, score, event.id]);
    await redisCommand(["EXPIRE", installKey, EVENT_TTL_SECONDS]);
    if (target.tripId) {
      const tripKey = tripEventIndexKey(target.appInstallId!, target.tripId);
      await redisCommand(["ZADD", tripKey, score, event.id]);
      await redisCommand(["EXPIRE", tripKey, EVENT_TTL_SECONDS]);
    }
  }
  return { stored: stored === "OK", duplicate: stored !== "OK" };
}

export async function listTravelEvents(installId: string, tripId?: string, limit = 40) {
  if (!storageConfigured()) return [];
  const index = tripId ? tripEventIndexKey(installId, tripId) : eventIndexKey(installId);
  const ids = await redisCommand<string[]>(["ZREVRANGE", index, 0, Math.max(0, Math.min(limit, 100) - 1)]);
  const events: TravelEvent[] = [];
  for (const id of ids ?? []) {
    const raw = await redisCommand<string>(["GET", eventKey(id)]);
    if (!raw) continue;
    try {
      events.push(JSON.parse(raw) as TravelEvent);
    } catch {
      // Ignore an isolated invalid operational record.
    }
  }
  return events;
}

export async function enqueueTravelEventNotifications(
  event: TravelEvent,
  targets: RegisteredFlightTarget[],
  alert: Omit<APNsAlert, "data"> & { data?: Record<string, unknown> }
) {
  const now = new Date().toISOString();
  let queued = 0;

  if (!storageConfigured()) {
    const tokens = targets.flatMap((target) => normalizeDeviceToken(target.deviceToken) ?? []);
    const result = await sendAPNsAlert(tokens, alert);
    return {
      queued: 0,
      duplicate: 0,
      drain: {
        attempted: result.attempted,
        sent: result.sent,
        failed: result.failed,
        pending: 0,
        invalidDeviceTokens: result.invalidDeviceTokens,
        errors: result.errors
      } satisfies OutboxDrainResult
    };
  }

  for (const target of targets) {
    const token = normalizeDeviceToken(target.deviceToken);
    if (!token) continue;
    const id = deliveryId(event.id, token);
    const delivery: NotificationOutboxDelivery = {
      id,
      eventId: event.id,
      deviceToken: token,
      target: {
        appInstallId: target.appInstallId,
        tripId: target.tripId,
        itemId: target.itemId
      },
      alert: {
        ...alert,
        data: {
          ...(alert.data ?? {}),
          travelEventId: event.id,
          tripId: target.tripId,
          itemId: target.itemId
        }
      },
      status: "pending",
      attempts: 0,
      createdAt: now,
      updatedAt: now,
      nextAttemptAt: now
    };
    const inserted = await redisCommand<string | null>([
      "SET",
      deliveryKey(id),
      JSON.stringify(delivery),
      "EX",
      DELIVERY_TTL_SECONDS,
      "NX"
    ]);
    if (inserted !== "OK") continue;
    queued += 1;
    await redisCommand(["ZADD", OUTBOX_DUE_KEY, Date.now(), id]);
  }

  const drain = await processNotificationOutbox(Math.max(10, Math.min(50, queued)));
  return { queued, duplicate: Math.max(0, targets.length - queued), drain };
}

function retryDelaySeconds(attempts: number) {
  return Math.min(60 * 60, Math.max(30, 30 * 2 ** Math.min(attempts, 7)));
}

export async function processNotificationOutbox(limit = 30): Promise<OutboxDrainResult> {
  const summary: OutboxDrainResult = {
    attempted: 0,
    sent: 0,
    failed: 0,
    pending: 0,
    invalidDeviceTokens: [],
    errors: []
  };
  if (!storageConfigured()) return summary;

  const ids = await redisCommand<string[]>([
    "ZRANGEBYSCORE",
    OUTBOX_DUE_KEY,
    0,
    Date.now(),
    "LIMIT",
    0,
    Math.max(1, Math.min(limit, 100))
  ]);

  for (const id of ids ?? []) {
    const raw = await redisCommand<string>(["GET", deliveryKey(id)]);
    if (!raw) {
      await redisCommand(["ZREM", OUTBOX_DUE_KEY, id]);
      continue;
    }
    let delivery: NotificationOutboxDelivery;
    try {
      delivery = JSON.parse(raw) as NotificationOutboxDelivery;
    } catch {
      await redisCommand(["ZREM", OUTBOX_DUE_KEY, id]);
      continue;
    }
    if (delivery.status === "sent" || delivery.status === "failed") {
      await redisCommand(["ZREM", OUTBOX_DUE_KEY, id]);
      continue;
    }

    summary.attempted += 1;
    const result = await sendAPNsAlert([delivery.deviceToken], delivery.alert);
    delivery.attempts += 1;
    delivery.updatedAt = new Date().toISOString();

    if (result.sent > 0) {
      delivery.status = "sent";
      delivery.sentAt = delivery.updatedAt;
      delivery.lastError = undefined;
      summary.sent += 1;
      await redisCommand(["ZREM", OUTBOX_DUE_KEY, id]);
    } else if (result.invalidDeviceTokens.includes(delivery.deviceToken) || delivery.attempts >= 8) {
      delivery.status = "failed";
      delivery.lastError = result.errors.join("; ") || "APNs delivery failed.";
      summary.failed += 1;
      await redisCommand(["ZREM", OUTBOX_DUE_KEY, id]);
    } else {
      delivery.status = "retrying";
      delivery.lastError = result.errors.join("; ") || "APNs delivery will be retried.";
      const next = Date.now() + retryDelaySeconds(delivery.attempts) * 1000;
      delivery.nextAttemptAt = new Date(next).toISOString();
      summary.pending += 1;
      await redisCommand(["ZADD", OUTBOX_DUE_KEY, next, id]);
    }

    summary.invalidDeviceTokens.push(...result.invalidDeviceTokens);
    summary.errors.push(...result.errors);
    await redisCommand(["SET", deliveryKey(id), JSON.stringify(delivery), "EX", DELIVERY_TTL_SECONDS]);
  }

  summary.invalidDeviceTokens = [...new Set(summary.invalidDeviceTokens)];
  summary.errors = [...new Set(summary.errors)];
  return summary;
}

export function provisionalTravelEventId() {
  return randomUUID();
}
