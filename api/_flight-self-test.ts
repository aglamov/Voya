import { normalizeFlightNumber, redisCommand, storageConfigured } from "./_storage.js";

export type FlightAlertSelfTestStatus = "searching" | "armed" | "gate_received" | "failed";

export type FlightAlertSelfTestRecord = {
  status: FlightAlertSelfTestStatus;
  installId: string;
  flightNumber?: string;
  flightDate?: string;
  originAirport?: string;
  destinationAirport?: string;
  departureAt?: string;
  terminal?: string;
  gate?: string;
  alertId?: string;
  monitoringState?: string;
  fallbackPolling?: boolean;
  confirmationPushSent?: boolean;
  gatePushSent?: boolean;
  createdAt: string;
  updatedAt: string;
  gateReceivedAt?: string;
  eventId?: string;
  eventSummary?: string;
  error?: string;
};

const ttlSeconds = 36 * 60 * 60;

function key(installId: string) {
  return `voya:flight-self-test:${installId}`;
}

export async function readFlightAlertSelfTest(installId: string) {
  if (!storageConfigured()) return undefined;
  const raw = await redisCommand<string>(["GET", key(installId)]);
  if (!raw) return undefined;
  try {
    return JSON.parse(raw) as FlightAlertSelfTestRecord;
  } catch {
    return undefined;
  }
}

export async function saveFlightAlertSelfTest(record: FlightAlertSelfTestRecord) {
  if (!storageConfigured()) return;
  await redisCommand(["SET", key(record.installId), JSON.stringify(record), "EX", ttlSeconds]);
}

export async function markFlightAlertSelfTestGateReceived(input: {
  installId: string;
  flightNumber: string;
  flightDate?: string;
  gate?: string;
  terminal?: string;
  eventId: string;
  eventSummary: string;
  receivedAt: string;
  pushSent: boolean;
}) {
  const record = await readFlightAlertSelfTest(input.installId);
  if (!record || record.status !== "armed") return false;
  if (normalizeFlightNumber(record.flightNumber) !== normalizeFlightNumber(input.flightNumber)) return false;
  if (record.flightDate && input.flightDate && record.flightDate !== input.flightDate) return false;

  await saveFlightAlertSelfTest({
    ...record,
    status: "gate_received",
    gate: input.gate,
    terminal: input.terminal,
    gateReceivedAt: input.receivedAt,
    eventId: input.eventId,
    eventSummary: input.eventSummary,
    gatePushSent: input.pushSent,
    updatedAt: input.receivedAt
  });
  return true;
}
