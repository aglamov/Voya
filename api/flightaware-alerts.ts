import type { VercelRequest, VercelResponse } from "@vercel/node";

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
  estimated_out?: string;
  estimated_in?: string;
  actual_out?: string;
  actual_in?: string;
  [key: string]: unknown;
};

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : undefined;
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

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const payload = req.body as FlightAwareAlertPayload;
  const normalized = {
    provider: "flightaware",
    eventType: eventType(payload),
    providerFlightId: clean(payload.fa_flight_id),
    flightNumber: clean(payload.ident_iata) ?? clean(payload.ident),
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

  return res.status(202).json({
    accepted: true,
    alert: normalized
  });
}
