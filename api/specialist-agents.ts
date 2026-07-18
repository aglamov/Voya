import type { VercelRequest, VercelResponse } from "@vercel/node";
import { openai } from "@ai-sdk/openai";
import { generateObject } from "ai";
import { z } from "zod";
import { openAIModelFor } from "./_ai-models.js";
import { protectPublicEndpoint } from "./_security.js";

const agentSchema = z.object({
  agent: z.enum(["sentinel", "navigator", "clerk", "scout", "recovery", "concierge", "coordinator"]),
  mission: z.string().min(1).max(600),
  context: z.record(z.unknown()).optional().default({}),
  locale: z.string().max(40).optional()
});

const resultSchema = z.object({
  title: z.string().min(1).max(240),
  summary: z.string().min(1).max(1_500),
  observations: z.array(z.string().min(1).max(500)).max(6),
  nextActions: z.array(z.string().min(1).max(500)).max(5),
  needsApproval: z.boolean(),
  confidence: z.number().min(0).max(1)
});

export type SpecialistAgent = z.infer<typeof agentSchema>["agent"];
export type SpecialistResult = z.infer<typeof resultSchema>;

export async function runSpecialistAgent(input: z.infer<typeof agentSchema>) {
  if (!process.env.OPENAI_API_KEY) {
    return {
      result: {
        title: `${input.agent} prepared the next step`,
        summary: `The mission “${input.mission}” is active. Voya has recorded its context and will surface a meaningful change.`,
        observations: [] as string[],
        nextActions: ["Keep the mission active and refresh it when new trip evidence arrives."],
        needsApproval: false,
        confidence: 0.45
      },
      usedAI: false
    };
  }
  const { object } = await generateObject({
    model: openai(openAIModelFor("brief")),
    schema: resultSchema,
    system: `You are Voya's ${input.agent} travel specialist. Use only the supplied context. Separate facts from recommendations, admit missing evidence, and never claim that a booking or external action was performed. Any action with money, cancellation, communication, or reservation requires approval.`,
    prompt: JSON.stringify(input)
  });
  return { result: object, usedAI: true };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed." });
  }
  if (!(await protectPublicEndpoint(req, res, {
    name: "specialist-agents",
    hourlyIPLimit: 80,
    hourlyInstallLimit: 50,
    maxBodyBytes: 64_000
  }))) return;
  const parsed = agentSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid agent run." });
  try {
    const run = await runSpecialistAgent(parsed.data);
    return res.status(200).json({ agent: parsed.data.agent, ...run });
  } catch {
    return res.status(502).json({ error: "The specialist could not complete this run." });
  }
}
