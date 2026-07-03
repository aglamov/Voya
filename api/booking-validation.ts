import type { VercelRequest, VercelResponse } from "@vercel/node";
import { z } from "zod";
import { getFlightStatus, flightLookupSchema } from "./_flight.js";

const bookingValidationSchema = z.object({
  sourceName: z.string().min(1).max(240).optional(),
  extractionConfidence: z.number().min(0).max(1).optional(),
  userReviewed: z.boolean().default(false),
  confirmationCodePresent: z.boolean().default(false),
  ticketNumberPresent: z.boolean().default(false),
  passengerNamePresent: z.boolean().default(false),
  flight: flightLookupSchema
});

function bookingProofReasons(input: z.infer<typeof bookingValidationSchema>) {
  return [
    input.sourceName ? `Imported from ${input.sourceName}.` : "Imported confirmation source exists.",
    input.extractionConfidence == null
      ? "Extraction confidence was not supplied."
      : `Extraction confidence is ${Math.round(input.extractionConfidence * 100)}%.`,
    input.userReviewed ? "User reviewed and accepted the extracted itinerary item." : "User review is still needed.",
    input.confirmationCodePresent ? "Confirmation code is present but not sent to the status provider." : "No confirmation code was included.",
    input.ticketNumberPresent ? "Ticket number is present but not sent to the status provider." : "No ticket number was included.",
    input.passengerNamePresent ? "Passenger name is present in the source document." : "Passenger name was not included."
  ];
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const parsedRequest = bookingValidationSchema.safeParse(req.body);
  if (!parsedRequest.success) {
    return res.status(400).json({
      error: "Invalid booking validation payload",
      details: parsedRequest.error.flatten()
    });
  }

  try {
    const input = parsedRequest.data;
    const flightStatus = await getFlightStatus(input.flight);
    const sourceConfidence = input.extractionConfidence ?? 0;
    const reviewed = input.userReviewed;
    const providerValidated = flightStatus.validation.state === "validated";
    const state = providerValidated && reviewed && sourceConfidence >= 0.7
      ? "validated_for_trip"
      : providerValidated
        ? "flight_exists_review_needed"
        : "not_validated";

    return res.status(200).json({
      state,
      confidence: providerValidated
        ? Math.min(0.96, (sourceConfidence * 0.35) + (reviewed ? 0.25 : 0) + (flightStatus.validation.confidence * 0.4))
        : 0,
      bookingProof: {
        canValidatePnr: false,
        reasons: bookingProofReasons(input),
        boundary: "Public flight-status APIs can validate that a flight exists, but cannot prove that this passenger's PNR or ticket is active. True booking validation needs an airline, OTA, NDC, GDS, or booking-provider integration."
      },
      flightStatus,
      warnings: [
        ...flightStatus.warnings,
        "Do not log or send confirmation codes, ticket numbers, or passenger names to generic flight-status providers."
      ]
    });
  } catch (error) {
    console.error("Booking validation failed", error);
    return res.status(502).json({ error: "Booking validation failed" });
  }
}
