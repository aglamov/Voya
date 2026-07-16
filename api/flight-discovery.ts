import type { VercelRequest, VercelResponse } from "@vercel/node";
import {
  discoverFlightNumber,
  flightDiscoverySchema,
  type FlightSnapshot
} from "./_flight.js";
import { protectPublicEndpoint } from "./_security.js";

function primaryDeparture(snapshot: FlightSnapshot) {
  return snapshot.scheduledDepartureAt
    ?? snapshot.estimatedDepartureAt
    ?? snapshot.actualDepartureAt;
}

function primaryArrival(snapshot: FlightSnapshot) {
  return snapshot.scheduledArrivalAt
    ?? snapshot.estimatedArrivalAt
    ?? snapshot.actualArrivalAt;
}

function durationMinutes(start?: string, end?: string) {
  const startMs = start ? Date.parse(start) : Number.NaN;
  const endMs = end ? Date.parse(end) : Number.NaN;
  if (Number.isNaN(startMs) || Number.isNaN(endMs) || endMs < startMs) return undefined;
  return Math.round((endMs - startMs) / 60000);
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!await protectPublicEndpoint(req, res, { name: "flight-discovery", hourlyIPLimit: 180, hourlyInstallLimit: 60, maxBodyBytes: 12_000 })) return;

  const parsedRequest = flightDiscoverySchema.safeParse(req.body);
  if (!parsedRequest.success) {
    return res.status(400).json({
      error: "Invalid flight discovery payload",
      details: parsedRequest.error.flatten()
    });
  }

  try {
    const result = await discoverFlightNumber(parsedRequest.data);
    const snapshot = result.snapshot;
    const departureAt = snapshot ? primaryDeparture(snapshot) : undefined;
    const arrivalAt = snapshot ? primaryArrival(snapshot) : undefined;

    return res.status(200).json({
      validation: result.validation,
      candidate: snapshot ? {
        flightNumber: snapshot.flightIata ?? snapshot.flightNumber,
        flightIata: snapshot.flightIata,
        flightIcao: snapshot.flightIcao,
        operatingFlightNumber: snapshot.codeshares?.[0],
        originAirport: snapshot.originAirport,
        originAirportIcao: snapshot.originAirportIcao,
        destinationAirport: snapshot.destinationAirport,
        destinationAirportIcao: snapshot.destinationAirportIcao,
        departureAt,
        arrivalAt,
        durationMinutes: durationMinutes(departureAt, arrivalAt),
        aircraftType: snapshot.aircraftType,
        providerStatus: snapshot.providerStatus,
        dataMode: snapshot.dataMode,
        confidence: result.validation.confidence
      } : undefined,
      warnings: result.warnings
    });
  } catch (error) {
    console.error("Flight discovery failed", error);
    return res.status(502).json({ error: "Flight discovery failed" });
  }
}
