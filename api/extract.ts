import type { VercelRequest, VercelResponse } from "@vercel/node";
import { gateway } from "@ai-sdk/gateway";
import { generateObject } from "ai";
import { z } from "zod";

const itemSchema = z.object({
  kind: z.enum(["flight", "hotel", "event", "transit"]),
  title: z.string().min(1),
  time: z.string().min(1),
  location: z.string().min(1),
  status: z.string().min(1)
});

const extractionSchema = z.object({
  type: z.string().min(1),
  title: z.string().min(1),
  primaryTime: z.string().min(1),
  confidence: z.number().min(0).max(1),
  items: z.array(itemSchema).min(1).max(12),
  warnings: z.array(z.string()).default([])
});

const requestSchema = z.object({
  sourceName: z.string().min(1).max(240),
  text: z.string().min(1).max(50000)
});

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
    model: process.env.AI_GATEWAY_MODEL ?? "openai/gpt-5-mini"
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
      model: gateway(process.env.AI_GATEWAY_MODEL ?? "openai/gpt-5-mini"),
      schema: extractionSchema,
      system: [
        "You extract travel booking confirmations for Voya, an iPhone trip companion.",
        "Return concise structured data only.",
        "Use the user's visible confirmation text as the source of truth.",
        "Prefer exact airline flight numbers, airports, terminals, hotel names, venue names, dates, and times.",
        "When details are missing, keep the item but mark the missing field plainly and add a warning.",
        "Do not invent confirmation numbers, addresses, gates, or statuses."
      ].join(" "),
      prompt: [
        `Source file: ${sourceName}`,
        "Extract flights, hotels, events, and transit reservations into itinerary items.",
        "Use kind values only from: flight, hotel, event, transit.",
        "Make title useful in a timeline, primaryTime the first relevant date/time, and confidence your extraction confidence.",
        "",
        text
      ].join("\n")
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
