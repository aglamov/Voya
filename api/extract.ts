import type { VercelRequest, VercelResponse } from "@vercel/node";
import { openai } from "@ai-sdk/openai";
import { generateObject, generateText } from "ai";
import { z } from "zod";
import { openAIModelFor } from "./ai-models.js";

const itemSchema = z.object({
  kind: z.enum(["flight", "hotel", "event", "transit"]),
  title: z.string().min(1),
  startsAt: z.string().datetime({ offset: true }).nullable().optional().describe("The actual itinerary start date-time, not a booking, payment, issue, print, or cancellation date."),
  endsAt: z.string().datetime({ offset: true }).nullable().optional().describe("The actual itinerary end date-time, not a booking, payment, issue, print, or cancellation date."),
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
  text: z.string().min(1).max(50000),
  locale: z.string().min(2).max(64).optional(),
  languageCode: z.string().min(2).max(16).optional(),
  languageName: z.string().min(2).max(80).optional()
});

const extractionModelName = () => openAIModelFor("extraction");
const jsonRepairModelName = () => openAIModelFor("jsonRepair");

function responseLanguageInstruction(languageCode?: string, languageName?: string, locale?: string) {
  const code = languageCode?.trim() || "en";
  const name = languageName?.trim() || code;
  const region = locale?.trim() || code;

  if (code.toLowerCase().startsWith("en")) {
    return "Return all human-facing text fields in English.";
  }

  return [
    `Return all human-facing text fields in ${name} (locale ${region}).`,
    "This includes type, title, normalizedDestination when it is a generic place phrase, primaryTime, item titles, item locations when they are generic/missing-field text, item statuses, and warnings.",
    "Keep airline codes, flight numbers, airport codes, confirmation codes, URLs, hotel/venue names, street addresses, and proper nouns as shown unless the source itself provides a localized form.",
    "Keep ISO date-time values unchanged except for choosing the correct local offset."
  ].join(" ");
}

const schemaInstructions = [
  "Return only JSON with this exact shape:",
  "{",
  '  "type": "Flight + Hotel",',
  '  "title": "Trip to Rome",',
  '  "normalizedDestination": "Rome",',
  '  "primaryTime": "Aug 12, 09:40",',
  '  "confidence": 0.91,',
  '  "items": [',
  '    {"kind":"flight","title":"BA2490 to Rome Fiumicino","startsAt":"2026-08-12T09:40:00+01:00","endsAt":"2026-08-12T13:10:00+02:00","location":"London Heathrow to Rome Fiumicino","status":"Confirmed"}',
  "  ],",
  '  "warnings": []',
  "}",
  "kind must be one of: flight, hotel, event, transit.",
  "For each item, startsAt and endsAt must be ISO 8601 date-time strings when the source has those values. Use null only when the value is not visible.",
  "Use the local timezone offset for the departure, arrival, check-in, check-out, or venue location. Do not use Z/UTC unless the source explicitly says the time is UTC.",
  "For flight items, startsAt is departure and endsAt is arrival when arrival is visible.",
  "If a booking contains connecting flights or multiple flight legs, return one flight item per leg. Do not merge connections into a single origin-to-final-destination flight.",
  "For hotel items, startsAt is the check-in date/time and endsAt is the check-out date/time for the stay.",
  "Do not use booking dates, reservation dates, payment dates, cancellation deadlines, invoice dates, print dates, or email dates as startsAt or endsAt.",
  "If several hotel check-in times are visible, use the earliest check-in time for the selected check-in date. If several hotel check-out times are visible, use the latest check-out time for the selected check-out date.",
  "Hotel endsAt must be after startsAt. If a candidate date is before check-in or far outside the stay, reject it as metadata, not itinerary time.",
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
    extractionModel: extractionModelName(),
    jsonRepairModel: jsonRepairModelName()
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

  const { sourceName, text, locale, languageCode, languageName } = parsedRequest.data;
  const languageInstruction = responseLanguageInstruction(languageCode, languageName, locale);

  try {
    const { object } = await generateObject({
      model: openai(extractionModelName()),
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
        languageInstruction,
        schemaInstructions
      ].join(" "),
      prompt: [
        `Source file: ${sourceName}`,
        `App locale: ${locale ?? "en"}`,
        languageInstruction,
        "Extract flights, hotels, events, and transit reservations into itinerary items.",
        "Use kind values only from: flight, hotel, event, transit.",
        "Split connecting flights into separate flight items, one item per flight number and leg.",
        "Use local timezone offsets in startsAt and endsAt for the relevant departure, arrival, hotel, or venue location. Do not use Z/UTC unless the source explicitly says UTC.",
        "For hotels, read the room stay dates semantically: startsAt is the check-in date/time, endsAt is the check-out date/time.",
        "Ignore dates that describe booking creation, reservation confirmation, payment, cancellation policy, invoice, document generation, or email sending.",
        "For hotel check-in/check-out, search the whole visible confirmation text and choose the dates attached to labels such as Check-in, Arrival, Check-out, Departure, Stay dates, or Your booking details.",
        "If multiple check-in time options appear for the same check-in date, choose the earliest. If multiple check-out time options appear for the same check-out date, choose the latest.",
        "Never set hotel startsAt to a date that is not part of the stay, even if it appears near the hotel name or address.",
        "Hotel endsAt must be after startsAt. If the document shows nights count and dates, use that consistency check.",
        "Make title useful in a timeline, normalizedDestination the clean trip place, primaryTime the first relevant date/time, and confidence your extraction confidence.",
        "",
        text
      ].join("\n"),
      experimental_repairText: async ({ text: generatedText, error }) => {
        const { text: repairedText } = await generateText({
          model: openai(jsonRepairModelName()),
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
