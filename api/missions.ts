import type { VercelRequest, VercelResponse } from "@vercel/node";
import { z } from "zod";
import { cleanText, enqueueAgentJob, listMissions, newMission, readMission, requestInstallId, saveMission } from "./_agents.js";
import { processAgentJob } from "./agent-worker.js";
import { protectPublicEndpoint } from "./_security.js";

const createSchema = z.object({
  kind: z.enum(["guardian", "inspiration", "planning", "recovery", "concierge"]),
  title: z.string().min(1).max(180),
  detail: z.string().min(1).max(1_500),
  tripId: z.string().uuid().optional(),
  inspirationId: z.string().max(120).optional(),
  nextCheckAt: z.string().datetime().optional(),
  deviceToken: z.string().max(256).optional(),
  context: z.record(z.unknown()).optional()
});

const updateSchema = z.object({
  id: z.string().uuid(),
  status: z.enum(["active", "waiting", "completed", "cancelled"])
});

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (!(await protectPublicEndpoint(req, res, {
    name: "missions",
    hourlyIPLimit: 180,
    hourlyInstallLimit: 120,
    maxBodyBytes: 24_000
  }))) return;

  const installId = requestInstallId(req);
  if (req.method === "GET") {
    return res.status(200).json({ missions: await listMissions(installId) });
  }

  if (req.method === "POST") {
    const parsed = createSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: "Invalid mission.", issues: parsed.error.issues });
    const mission = newMission(installId, { ...parsed.data, nextCheckAt: new Date().toISOString() });
    await saveMission(mission);
    const job = { type: "mission" as const, installId, missionId: mission.id };
    const queued = await enqueueAgentJob(job);
    if (!queued) {
      await processAgentJob(job).catch(() => undefined);
    }
    return res.status(201).json({ mission: await readMission(installId, mission.id) ?? mission, queued });
  }

  if (req.method === "PATCH") {
    const parsed = updateSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: "Invalid mission update." });
    const existing = await readMission(installId, parsed.data.id);
    if (!existing) return res.status(404).json({ error: "Mission not found." });
    const mission = { ...existing, status: parsed.data.status, updatedAt: new Date().toISOString() };
    await saveMission(mission);
    return res.status(200).json({ mission });
  }

  if (req.method === "DELETE") {
    const id = cleanText(req.query.id, 80);
    const existing = id ? await readMission(installId, id) : undefined;
    if (!existing) return res.status(404).json({ error: "Mission not found." });
    const mission = { ...existing, status: "cancelled" as const, updatedAt: new Date().toISOString() };
    await saveMission(mission);
    return res.status(200).json({ mission });
  }

  res.setHeader("Allow", "GET, POST, PATCH, DELETE");
  return res.status(405).json({ error: "Method not allowed." });
}
