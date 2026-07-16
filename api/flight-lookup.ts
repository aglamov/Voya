import type { VercelRequest, VercelResponse } from "@vercel/node";
import { getFlightHistoryStats, getFlightStatus, flightLookupSchema, type FlightSnapshot } from "./_flight.js";
import { protectPublicEndpoint } from "./_security.js";

function queryValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function minutesBetween(start?: string, end?: string) {
  if (!start || !end) {
    return undefined;
  }

  const startMs = Date.parse(start);
  const endMs = Date.parse(end);
  if (Number.isNaN(startMs) || Number.isNaN(endMs) || endMs < startMs) {
    return undefined;
  }

  return Math.round((endMs - startMs) / 60000);
}

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

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET" && req.method !== "POST") {
    res.setHeader("Allow", "GET, POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!await protectPublicEndpoint(req, res, { name: "flight-lookup", hourlyIPLimit: 360, hourlyInstallLimit: 120, maxBodyBytes: 24_000 })) return;

  const payload = req.method === "GET"
    ? {
        flightNumber: queryValue(req.query.flightNumber),
        date: queryValue(req.query.date),
        originAirport: queryValue(req.query.originAirport),
        destinationAirport: queryValue(req.query.destinationAirport)
      }
    : req.body;

  const parsedRequest = flightLookupSchema.safeParse(payload);
  if (!parsedRequest.success) {
    return res.status(400).json({
      error: "Invalid flight lookup payload",
      details: parsedRequest.error.flatten()
    });
  }

  try {
    const status = await getFlightStatus(parsedRequest.data);
    const history = status.intelligence.history ?? await getFlightHistoryStats(parsedRequest.data);
    const snapshot = status.snapshot;
    const departureAt = snapshot ? primaryDeparture(snapshot) : undefined;
    const arrivalAt = snapshot ? primaryArrival(snapshot) : undefined;
    const durationMinutes = snapshot ? minutesBetween(departureAt, arrivalAt) : undefined;

    return res.status(200).json({
      query: status.query,
      validation: status.validation,
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
        durationMinutes,
        departureTerminal: snapshot.departureTerminal,
        departureGate: snapshot.departureGate,
        arrivalTerminal: snapshot.arrivalTerminal,
        arrivalGate: snapshot.arrivalGate,
        baggageClaim: snapshot.baggageClaim,
        aircraftType: snapshot.aircraftType,
        aircraftRegistration: snapshot.aircraftRegistration,
        providerStatus: snapshot.providerStatus,
        dataMode: snapshot.dataMode,
        progressPercent: snapshot.progressPercent,
        position: snapshot.position,
        inboundProviderFlightId: snapshot.inboundProviderFlightId,
        confidence: status.validation.confidence
      } : undefined,
      plane: status.plane,
      delayStats: status.delayStats,
      reliability: history ? {
        sampleSize: history.sampleSize,
        averageDepartureDelayMinutes: history.averageDepartureDelayMinutes,
        averageArrivalDelayMinutes: history.averageArrivalDelayMinutes,
        delayed15Rate: history.delayed15Rate,
        cancelledCount: history.cancelledCount,
        divertedCount: history.divertedCount,
        typicalDepartureGate: history.typicalDepartureGate,
        typicalArrivalGate: history.typicalArrivalGate,
        typicalAircraftTypes: history.typicalAircraftTypes
      } : undefined,
      gate: status.gate,
      alerting: status.alerting,
      warnings: status.warnings,
      provider: status.provider
    });
  } catch (error) {
    console.error("Flight lookup failed", error);
    return res.status(502).json({ error: "Flight lookup failed" });
  }
}
