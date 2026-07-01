import type { VercelRequest, VercelResponse } from "@vercel/node";
import { openai } from "@ai-sdk/openai";
import { generateObject, generateText } from "ai";
import { z } from "zod";

const itemSchema = z.object({
  kind: z.enum(["flight", "hotel", "event", "transit"]),
  title: z.string().min(1),
  startsAt: z.string().datetime().nullable().optional(),
  endsAt: z.string().datetime().nullable().optional(),
  location: z.string().min(1),
  status: z.string().min(1)
});

const extractionSchema = z.object({
  type: z.string().min(1),
  title: z.string().min(1),
  normalizedDestination: z.string().min(1),
  primaryTime: z.string().min(1),
  confidence: z.number().min(0).max(1),
  items: z.array(itemSchema).min(1).max(12),
  warnings: z.array(z.string()).default([])
});

const requestSchema = z.object({
  sourceName: z.string().min(1).max(240),
  text: z.string().min(1).max(50000)
});

const modelName = () => process.env.OPENAI_MODEL ?? "gpt-4o-mini";

const schemaInstructions = [
  "Return only JSON with this exact shape:",
  "{",
  '  "type": "Flight + Hotel",',
  '  "title": "Trip to Rome",',
  '  "normalizedDestination": "Rome",',
  '  "primaryTime": "Aug 12, 09:40",',
  '  "confidence": 0.91,',
  '  "items": [',
  '    {"kind":"flight","title":"BA2490 to Rome Fiumicino","startsAt":"2026-08-12T09:40:00Z","endsAt":"2026-08-12T13:10:00Z","location":"London Heathrow to Rome Fiumicino","status":"Confirmed"}',
  "  ],",
  '  "warnings": []',
  "}",
  "kind must be one of: flight, hotel, event, transit.",
  "For each item, startsAt and endsAt must be ISO 8601 date-time strings when the source has those values. Use null only when the value is not visible.",
  "For flight items, startsAt is departure and endsAt is arrival when arrival is visible.",
  "For hotel items, startsAt is check-in and endsAt is check-out when visible.",
  "normalizedDestination must be the clean destination/place name for the trip title, without airport codes, hotel names, addresses, dates, or words like Trip to.",
  "When multiple places exist, choose the place where the traveler spends the longest time. For example, if a flight arrives in Zurich but the hotel stay is in Bad Ragaz for several days, normalizedDestination should be Bad Ragaz.",
  "confidence must be a number from 0 to 1."
].join("\n");

function extractionErrorDetails(error: unknown) {
  if (!(error instanceof Error)) {
    return {
      message: "Unknown AI extraction error"
    };
  }

  return {
    name: error.name,
    message: error.message,
    statusCode: "statusCode" in error ? error.statusCode : undefined,
    type: "type" in error ? error.type : undefined,
    model: modelName()
  };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const parsedRequest = requestSchema.safeParse(req.body);
  if (!parsedRequest.success) {
    return res.status(400).json({ error: "Invalid confirmation payload" });
  }

  const { sourceName, text } = parsedRequest.data;

  try {
    const { object } = await generateObject({
      model: openai(modelName()),
      schema: extractionSchema,
      schemaName: "TravelConfirmationExtraction",
      schemaDescription: "Structured itinerary data extracted from a travel booking confirmation.",
      system: [
        "You extract travel booking confirmations for Voya, an iPhone trip companion.",
        "Return concise structured data only as valid JSON.",
        "Use the user's visible confirmation text as the source of truth.",
        "Prefer exact airline flight numbers, airports, terminals, hotel names, venue names, dates, and times.",
        "Infer a clean normalizedDestination from the itinerary, preferring the longest stay/place over a transit airport.",
        "When details are missing, keep the item but mark the missing field plainly and add a warning.",
        "Do not invent confirmation numbers, addresses, gates, or statuses.",
        schemaInstructions
      ].join(" "),
      prompt: [
        `Source file: ${sourceName}`,
        "Extract flights, hotels, events, and transit reservations into itinerary items.",
        "Use kind values only from: flight, hotel, event, transit.",
        "For hotels, set startsAt to check-in and endsAt to check-out whenever both are visible.",
        "Make title useful in a timeline, normalizedDestination the clean trip place, primaryTime the first relevant date/time, and confidence your extraction confidence.",
        "",
        text
      ].join("\n"),
      experimental_repairText: async ({ text: generatedText, error }) => {
        const { text: repairedText } = await generateText({
          model: openai(modelName()),
          system: "Repair invalid JSON so it matches the requested travel extraction schema. Return only JSON.",
          prompt: [
            schemaInstructions,
            "",
            "Validation error:",
            error.message,
            "",
            "Invalid output:",
            generatedText
          ].join("\n")
        });

        return repairedText;
      }
    });

    return res.status(200).json(object);
  } catch (error) {
    console.error("Confirmation extraction failed", error);
    return res.status(502).json({
      error: "AI extraction failed",
      details: extractionErrorDetails(error)
    });
  }
}
