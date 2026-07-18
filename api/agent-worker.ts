import type { VercelRequest, VercelResponse } from "@vercel/node";
import { timingSafeEqual } from "node:crypto";
import { sendAPNsAlert } from "./_apns.js";
import {
  type AgentJob,
  readInspirationRelease,
  readMission,
  saveInspirationRelease,
  saveMission
} from "./_agents.js";
import { buildInspirationFeed } from "./inspiration.js";
import { runSpecialistAgent, type SpecialistAgent } from "./specialist-agents.js";
import { redisCommand, storageConfigured } from "./_storage.js";

function firstHeader(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function authorized(req: VercelRequest) {
  const expected = process.env.AGENT_WORKER_SECRET?.trim();
  const authorization = firstHeader(req.headers.authorization)?.trim();
  const actual = authorization?.toLowerCase().startsWith("bearer ")
    ? authorization.slice("bearer ".length).trim()
    : firstHeader(req.headers["x-voya-agent-secret"])?.trim();
  if (!expected || !actual) return false;
  const encoder = new TextEncoder();
  const lhs = encoder.encode(actual);
  const rhs = encoder.encode(expected);
  return lhs.length === rhs.length && timingSafeEqual(lhs, rhs);
}

function primaryAgent(kind: string): SpecialistAgent {
  switch (kind) {
    case "guardian": return "coordinator";
    case "inspiration": return "scout";
    case "recovery": return "recovery";
    case "concierge": return "concierge";
    default: return "coordinator";
  }
}

async function claim(job: AgentJob) {
  if (!storageConfigured()) return true;
  const id = job.type === "mission" ? job.missionId : job.releaseId;
  const result = await redisCommand<string | null>([
    "SET",
    `voya:agent-job-lock:${job.type}:${id}`,
    new Date().toISOString(),
    "EX",
    10 * 60,
    "NX"
  ]);
  return result === "OK";
}

async function processInspiration(job: Extract<AgentJob, { type: "inspiration" }>) {
  const release = await readInspirationRelease(job.installId);
  if (!release || release.id !== job.releaseId || release.status === "ready") {
    return { skipped: true, reason: "Release is missing, replaced, or already ready." };
  }

  const update = async (
    stage: typeof release.stage,
    progress: number,
    active: "scout" | "verifier" | "editor" | "curator"
  ) => {
    const next = {
      ...release,
      stage,
      progress,
      updatedAt: new Date().toISOString(),
      agents: release.agents.map((agent) => ({
        ...agent,
        state: agent.id === active ? "working" as const
          : release.agents.findIndex((item) => item.id === agent.id) < release.agents.findIndex((item) => item.id === active)
            ? "complete" as const
            : "waiting" as const
      }))
    };
    Object.assign(release, next);
    await saveInspirationRelease(release);
  };

  try {
    await update("scouting", 0.2, "scout");
    await update("verifying", 0.45, "verifier");
    await update("editing", 0.68, "editor");
    await update("curating", 0.86, "curator");
    const feed = await buildInspirationFeed(release.mood);
    const now = new Date().toISOString();
    const ready = {
      ...release,
      status: "ready" as const,
      stage: "ready" as const,
      progress: 1,
      updatedAt: now,
      readyAt: now,
      curatorNote: feed.curatorNote,
      stories: feed.stories,
      usedAI: feed.usedAI,
      agents: release.agents.map((agent) => ({ ...agent, state: "complete" as const }))
    };
    await saveInspirationRelease(ready);
    if (ready.deviceToken) {
      await sendAPNsAlert([ready.deviceToken], {
        title: "Your Voya collection is ready",
        body: ready.curatorNote ?? "Voya found a small collection of journeys worth wanting.",
        threadId: "voya-inspiration",
        data: { eventType: "inspiration_ready", releaseId: ready.id }
      });
    }
    return { ready: true, releaseId: ready.id, stories: ready.stories.length };
  } catch (error) {
    release.status = "failed";
    release.stage = "failed";
    release.error = error instanceof Error ? error.message : "Inspiration preparation failed.";
    release.updatedAt = new Date().toISOString();
    release.agents = release.agents.map((agent) => agent.state === "working" ? { ...agent, state: "failed" } : agent);
    await saveInspirationRelease(release);
    throw error;
  }
}

async function processMission(job: Extract<AgentJob, { type: "mission" }>) {
  const mission = await readMission(job.installId, job.missionId);
  if (!mission || mission.status === "cancelled" || mission.status === "completed") {
    return { skipped: true, reason: "Mission is missing or terminal." };
  }
  mission.status = "running";
  mission.updatedAt = new Date().toISOString();
  mission.lastError = undefined;
  await saveMission(mission);

  try {
    const specialist = primaryAgent(mission.kind);
    const run = await runSpecialistAgent({
      agent: specialist,
      mission: `${mission.title}\n${mission.detail}`,
      context: mission.context ?? {},
      locale: typeof mission.context?.locale === "string" ? mission.context.locale : undefined
    });
    const now = new Date();
    const recurring = mission.kind === "guardian";
    mission.status = recurring ? "active" : run.result.needsApproval ? "waiting" : "completed";
    mission.resultTitle = run.result.title;
    mission.resultSummary = run.result.summary;
    mission.resultActions = run.result.nextActions;
    mission.requiresApproval = run.result.needsApproval;
    mission.lastRunAt = now.toISOString();
    mission.updatedAt = now.toISOString();
    mission.runCount = (mission.runCount ?? 0) + 1;
    mission.nextCheckAt = recurring ? new Date(now.getTime() + 6 * 60 * 60 * 1000).toISOString() : undefined;
    await saveMission(mission);
    if (mission.deviceToken) {
      await sendAPNsAlert([mission.deviceToken], {
        title: run.result.title,
        body: run.result.summary.slice(0, 220),
        threadId: `voya-mission-${mission.id}`,
        data: { eventType: "mission_result", missionId: mission.id, tripId: mission.tripId, requiresApproval: run.result.needsApproval }
      });
    }
    return { completed: !recurring, recurring, missionId: mission.id, usedAI: run.usedAI };
  } catch (error) {
    mission.status = "failed";
    mission.lastError = error instanceof Error ? error.message : "Agent run failed.";
    mission.updatedAt = new Date().toISOString();
    await saveMission(mission);
    throw error;
  }
}

export async function processAgentJob(job: AgentJob) {
  if (!(await claim(job))) return { skipped: true, reason: "Job is already running." };
  return job.type === "inspiration" ? processInspiration(job) : processMission(job);
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed." });
  }
  if (!authorized(req)) return res.status(401).json({ error: "Unauthorized agent worker invocation." });
  const job = req.body as AgentJob;
  if (!job || (job.type !== "mission" && job.type !== "inspiration")) {
    return res.status(400).json({ error: "Invalid agent job." });
  }
  try {
    return res.status(200).json({ ok: true, result: await processAgentJob(job) });
  } catch (error) {
    return res.status(500).json({ error: error instanceof Error ? error.message : "Agent job failed." });
  }
}
