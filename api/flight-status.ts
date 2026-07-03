import type { VercelRequest, VercelResponse } from "@vercel/node";
import { getFlightStatus, flightLookupSchema } from "./_flight.js";

function queryValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET" && req.method !== "POST") {
    res.setHeader("Allow", "GET, POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

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
    return res.status(200).json(await getFlightStatus(parsedRequest.data));
  } catch (error) {
    console.error("Flight status lookup failed", error);
    return res.status(502).json({ error: "Flight status lookup failed" });
  }
}
