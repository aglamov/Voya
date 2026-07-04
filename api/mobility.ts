import type { VercelRequest, VercelResponse } from "@vercel/node";
import { buildMobilityPlan, mobilityPlanSchema } from "./_mobility.js";

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const parsedRequest = mobilityPlanSchema.safeParse(req.body);
  if (!parsedRequest.success) {
    return res.status(400).json({
      error: "Invalid mobility planning payload",
      details: parsedRequest.error.flatten()
    });
  }

  try {
    return res.status(200).json(await buildMobilityPlan(parsedRequest.data));
  } catch (error) {
    console.error("Mobility planning failed", error);
    return res.status(502).json({ error: "Mobility planning failed" });
  }
}
