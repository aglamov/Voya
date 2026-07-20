import type { VercelRequest, VercelResponse } from "@vercel/node";
import { timingSafeEqual } from "node:crypto";
import { sendAPNsAlert } from "./_apns.js";
import { googleTravelContext } from "./_google-context.js";
import {
  type AgentJob,
  type InspirationAgentStage,
  enqueueAgentJob,
  readInspirationRelease,
  readMission,
  saveInspirationRelease,
  saveMission
} from "./_agents.js";
import {
  curateInspirationCandidates,
  editInspirationCandidates,
  scoutInspirationCandidates,
  verifyInspirationCandidates,
  type InspirationStory
} from "./inspiration.js";
import { runSpecialistAgent, type SpecialistAgent } from "./specialist-agents.js";
import { runPlanningAgent } from "./_openai-agent-runtime.js";
import { redisCommand, storageConfigured } from "./_storage.js";

type InspirationWork = {
  candidates?: InspirationStory[];
  verified?: InspirationStory[];
  edited?: InspirationStory[];
};

const developmentInspirationWork = new Map<string, InspirationWork>();

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

async function providerContext(context: Record<string, unknown>) {
  const destination = typeof context.destination === "string" ? context.destination.trim() : "";
  if (!destination) return context;
  const locale = typeof context.locale === "string" ? context.locale : "en";
  const google = await googleTravelContext(destination, locale);
  if (!("data" in google.place)) return context;
  return {
    ...context,
    verifiedPlace: {
      name: google.place.data.name,
      address: google.place.data.address,
      mapsURL: google.place.data.mapsURL
    },
    airQuality: google.airQuality && "data" in google.airQuality ? google.airQuality.data : undefined,
    pollen: google.pollen && "data" in google.pollen ? google.pollen.data : undefined
  };
}

async function claim(job: AgentJob) {
  if (!storageConfigured()) return true;
  const id = job.type === "mission" ? job.missionId : `${job.releaseId}:${job.stage ?? "scouting"}`;
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

async function readInspirationWork(releaseId: string) {
  if (!storageConfigured()) return developmentInspirationWork.get(releaseId) ?? {};
  const raw = await redisCommand<string>(["GET", `voya:inspiration-work:${releaseId}`]);
  if (!raw) return {};
  try {
    return JSON.parse(raw) as InspirationWork;
  } catch {
    return {};
  }
}

async function saveInspirationWork(releaseId: string, work: InspirationWork) {
  if (!storageConfigured()) {
    developmentInspirationWork.set(releaseId, work);
    return;
  }
  await redisCommand([
    "SET",
    `voya:inspiration-work:${releaseId}`,
    JSON.stringify(work),
    "EX",
    24 * 60 * 60
  ]);
}

async function clearInspirationWork(releaseId: string) {
  developmentInspirationWork.delete(releaseId);
  await redisCommand(["DEL", `voya:inspiration-work:${releaseId}`]);
}

async function processInspiration(
  job: Extract<AgentJob, { type: "inspiration" }>
): Promise<Record<string, unknown>> {
  const release = await readInspirationRelease(job.installId);
  if (!release || release.id !== job.releaseId || release.status === "ready") {
    return { skipped: true, reason: "Release is missing, replaced, or already ready." };
  }

  const update = async (stage: InspirationAgentStage, progress: number) => {
    const active = stage === "scouting" ? "scout"
      : stage === "verifying" ? "verifier"
        : stage === "editing" ? "editor"
          : "curator";
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

  const continueWith = async (stage: InspirationAgentStage): Promise<Record<string, unknown>> => {
    const nextJob = { ...job, stage };
    if (await enqueueAgentJob(nextJob)) {
      return { ready: false, completedStage: job.stage ?? "scouting", queuedStage: stage };
    }
    return await processInspiration(nextJob);
  };

  try {
    const stage = job.stage ?? "scouting";
    const work = await readInspirationWork(release.id);
    if (stage === "scouting") {
      await update("scouting", 0.16);
      work.candidates = await scoutInspirationCandidates(release.mood, [], release.locale);
      await saveInspirationWork(release.id, work);
      await update("verifying", 0.34);
      return await continueWith("verifying");
    }
    if (stage === "verifying") {
      await update("verifying", 0.42);
      if (!work.candidates?.length) throw new Error("Scout candidates are missing.");
      work.verified = await verifyInspirationCandidates(work.candidates, release.mood, release.locale);
      await saveInspirationWork(release.id, work);
      await update("editing", 0.62);
      return await continueWith("editing");
    }
    if (stage === "editing") {
      await update("editing", 0.68);
      if (!work.verified?.length) throw new Error("Verified inspiration candidates are missing.");
      work.edited = editInspirationCandidates(work.verified, release.mood, release.locale);
      await saveInspirationWork(release.id, work);
      await update("curating", 0.82);
      return await continueWith("curating");
    }

    await update("curating", 0.88);
    if (!work.edited?.length) throw new Error("Edited inspiration candidates are missing.");
    const feed = await curateInspirationCandidates(work.edited, release.mood, [], release.locale);
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
    await clearInspirationWork(release.id);
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
    const missionInput = `${mission.title}\n${mission.detail}`;
    const context = mission.kind === "planning"
      ? mission.context ?? {}
      : await providerContext(mission.context ?? {});
    const locale = typeof mission.context?.locale === "string" ? mission.context.locale : undefined;
    const specialist = primaryAgent(mission.kind);
    const run = mission.kind === "planning"
      ? await runPlanningAgent({ mission: missionInput, context, locale })
      : await runSpecialistAgent({ agent: specialist, mission: missionInput, context, locale });
    const now = new Date();
    const recurring = mission.kind === "guardian";
    mission.status = recurring ? "active" : run.result.needsApproval ? "waiting" : "completed";
    mission.resultTitle = run.result.title;
    mission.resultSummary = run.result.summary;
    mission.resultActions = run.result.nextActions;
    mission.resultArtifact = "artifact" in run ? run.artifact : undefined;
    mission.requiresApproval = run.result.needsApproval;
    mission.usedAI = run.usedAI;
    mission.toolsUsed = "toolsUsed" in run && Array.isArray(run.toolsUsed)
      ? run.toolsUsed.filter((value): value is string => typeof value === "string")
      : undefined;
    mission.responseId = "responseId" in run && typeof run.responseId === "string"
      ? run.responseId
      : undefined;
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
