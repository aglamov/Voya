import type { VercelRequest } from "@vercel/node";
import { randomUUID } from "node:crypto";
import { normalizeDeviceToken, redisCommand, storageConfigured } from "./_storage.js";

export type AgentMissionStatus = "queued" | "active" | "running" | "waiting" | "completed" | "failed" | "cancelled";

export type AgentMission = {
  id: string;
  installId: string;
  tripId?: string;
  inspirationId?: string;
  kind: "guardian" | "inspiration" | "planning" | "recovery" | "concierge";
  title: string;
  detail: string;
  status: AgentMissionStatus;
  deviceToken?: string;
  context?: Record<string, unknown>;
  assignedAgents?: string[];
  resultTitle?: string;
  resultSummary?: string;
  resultActions?: string[];
  resultArtifact?: unknown;
  requiresApproval?: boolean;
  usedAI?: boolean;
  toolsUsed?: string[];
  responseId?: string;
  lastRunAt?: string;
  runCount?: number;
  lastError?: string;
  createdAt: string;
  updatedAt: string;
  nextCheckAt?: string;
};

export type InspirationReleaseStatus = "preparing" | "ready" | "failed";

export type InspirationRelease = {
  id: string;
  installId: string;
  status: InspirationReleaseStatus;
  mood: string;
  locale?: string;
  deviceToken?: string;
  stage: "scouting" | "verifying" | "editing" | "curating" | "ready" | "failed";
  progress: number;
  requestedAt: string;
  updatedAt: string;
  readyAt?: string;
  curatorNote?: string;
  stories?: unknown[];
  usedAI?: boolean;
  error?: string;
  agents: Array<{
    id: "scout" | "verifier" | "editor" | "curator";
    name: string;
    state: "waiting" | "working" | "complete" | "failed";
    detail: string;
  }>;
};

export type InspirationAgentStage = "scouting" | "verifying" | "editing" | "curating";

export type AgentJob =
  | { type: "inspiration"; installId: string; releaseId: string; stage?: InspirationAgentStage }
  | { type: "mission"; installId: string; missionId: string };

const developmentMissions = new Map<string, AgentMission>();
const developmentReleases = new Map<string, InspirationRelease>();

export function requestInstallId(req: VercelRequest) {
  const raw = req.headers["x-voya-install-id"];
  const value = (Array.isArray(raw) ? raw[0] : raw)?.trim().toLowerCase();
  return value && /^[0-9a-f-]{36}$/i.test(value) ? value : "development";
}

function missionKey(installId: string) {
  return `voya:agent-missions:${installId}`;
}

function releaseKey(installId: string) {
  return `voya:inspiration-release:${installId}`;
}

function parseHash(value: unknown): Array<[string, string]> {
  if (Array.isArray(value)) {
    const entries: Array<[string, string]> = [];
    for (let index = 0; index + 1 < value.length; index += 2) {
      if (typeof value[index] === "string" && typeof value[index + 1] === "string") {
        entries.push([value[index], value[index + 1]]);
      }
    }
    return entries;
  }
  return value && typeof value === "object"
    ? Object.entries(value).flatMap(([key, item]) => typeof item === "string" ? [[key, item]] : [])
    : [];
}

export async function listMissions(installId: string) {
  if (!storageConfigured()) {
    return [...developmentMissions.values()]
      .filter((mission) => mission.installId === installId)
      .sort((lhs, rhs) => rhs.updatedAt.localeCompare(lhs.updatedAt));
  }
  const raw = await redisCommand<unknown>(["HGETALL", missionKey(installId)]);
  return parseHash(raw).flatMap(([, value]) => {
    try {
      return [JSON.parse(value) as AgentMission];
    } catch {
      return [];
    }
  }).sort((lhs, rhs) => rhs.updatedAt.localeCompare(lhs.updatedAt));
}

export async function readMission(installId: string, id: string) {
  if (!storageConfigured()) return developmentMissions.get(`${installId}:${id}`);
  const raw = await redisCommand<string>(["HGET", missionKey(installId), id]);
  if (!raw) return undefined;
  try {
    return JSON.parse(raw) as AgentMission;
  } catch {
    return undefined;
  }
}

export async function saveMission(mission: AgentMission) {
  if (!storageConfigured()) {
    developmentMissions.set(`${mission.installId}:${mission.id}`, mission);
    return mission;
  }
  const key = missionKey(mission.installId);
  await redisCommand(["HSET", key, mission.id, JSON.stringify(mission)]);
  await redisCommand(["EXPIRE", key, 180 * 24 * 60 * 60]);
  const dueMember = `${mission.installId}:${mission.id}`;
  if ((mission.status === "active" || mission.status === "queued") && mission.nextCheckAt) {
    await redisCommand(["ZADD", "voya:agent-missions:due", Date.parse(mission.nextCheckAt), dueMember]);
  } else {
    await redisCommand(["ZREM", "voya:agent-missions:due", dueMember]);
  }
  if (mission.kind === "guardian" && mission.tripId) {
    const tripKey = `voya:guardian-missions:trip:${mission.tripId}`;
    if (mission.status === "cancelled" || mission.status === "completed" || mission.status === "failed") {
      await redisCommand(["SREM", tripKey, dueMember]);
    } else {
      await redisCommand(["SADD", tripKey, dueMember]);
      await redisCommand(["EXPIRE", tripKey, 180 * 24 * 60 * 60]);
    }
  }
  return mission;
}

export async function dispatchGuardianEvent(tripId: string | undefined, event: Record<string, unknown>) {
  if (!tripId || !storageConfigured()) return 0;
  const members = await redisCommand<string[]>(["SMEMBERS", `voya:guardian-missions:trip:${tripId}`]);
  let dispatched = 0;
  for (const member of members ?? []) {
    const separator = member.indexOf(":");
    const installId = member.slice(0, separator);
    const missionId = member.slice(separator + 1);
    const mission = await readMission(installId, missionId);
    if (!mission || mission.status === "cancelled") continue;
    mission.status = "queued";
    mission.nextCheckAt = new Date().toISOString();
    mission.updatedAt = new Date().toISOString();
    mission.context = {
      ...(mission.context ?? {}),
      latestEvent: JSON.stringify(event).slice(0, 4_000)
    };
    await saveMission(mission);
    if (await enqueueAgentJob({ type: "mission", installId, missionId })) dispatched += 1;
  }
  return dispatched;
}

export async function dueMissionMembers(now = Date.now(), limit = 20) {
  if (!storageConfigured()) return [];
  return await redisCommand<string[]>(["ZRANGEBYSCORE", "voya:agent-missions:due", 0, now, "LIMIT", 0, limit]) ?? [];
}

export async function readInspirationRelease(installId: string) {
  if (!storageConfigured()) return developmentReleases.get(installId);
  const raw = await redisCommand<string>(["GET", releaseKey(installId)]);
  if (!raw) return undefined;
  try {
    return JSON.parse(raw) as InspirationRelease;
  } catch {
    return undefined;
  }
}

export async function saveInspirationRelease(release: InspirationRelease) {
  if (!storageConfigured()) {
    developmentReleases.set(release.installId, release);
    return release;
  }
  await redisCommand(["SET", releaseKey(release.installId), JSON.stringify(release), "EX", 90 * 24 * 60 * 60]);
  return release;
}

export function newInspirationRelease(installId: string, mood: string, deviceToken?: string, locale = "en"): InspirationRelease {
  const now = new Date().toISOString();
  const russian = locale.toLowerCase().startsWith("ru");
  return {
    id: randomUUID(),
    installId,
    status: "preparing",
    mood,
    locale,
    deviceToken: normalizeDeviceToken(deviceToken),
    stage: "scouting",
    progress: 0.08,
    requestedAt: now,
    updatedAt: now,
    agents: [
      {
        id: "scout",
        name: russian ? "Исследователь" : "Scout",
        state: "working",
        detail: russian
          ? "Ищет события, природные явления, культурные поводы и удивительные места"
          : "Searching live events, natural moments, culture, and remarkable places"
      },
      {
        id: "verifier",
        name: russian ? "Проверяющий" : "Verifier",
        state: "waiting",
        detail: russian
          ? "Проверяет источник, время, место и реальность повода для поездки"
          : "Checking the source, timing, destination, and whether the reason is real"
      },
      {
        id: "editor",
        name: russian ? "Редактор историй" : "Story Editor",
        state: "waiting",
        detail: russian
          ? "Объясняет, почему поездка того стоит, и называет главный риск"
          : "Explaining why the journey is worth taking and naming the main risk"
      },
      {
        id: "curator",
        name: russian ? "Куратор" : "Curator",
        state: "waiting",
        detail: russian
          ? "Сравнивает варианты, убирает повторы и оставляет самые сильные"
          : "Comparing candidates, removing repetition, and keeping only the strongest"
      }
    ]
  };
}

export async function enqueueAgentJob(job: AgentJob, delaySeconds = 0) {
  const token = process.env.QSTASH_TOKEN?.trim();
  const secret = process.env.AGENT_WORKER_SECRET?.trim();
  const baseURL = process.env.VOYA_API_PUBLIC_BASE_URL?.trim().replace(/\/$/, "");
  if (!token || !secret || !baseURL) return false;
  const destination = `${baseURL}/api/agent-worker`;
  const response = await fetch(`https://qstash.upstash.io/v2/publish/${encodeURIComponent(destination)}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "Upstash-Forward-Authorization": `Bearer ${secret}`,
      ...(delaySeconds > 0 ? { "Upstash-Delay": `${Math.max(1, Math.floor(delaySeconds))}s` } : {})
    },
    body: JSON.stringify(job)
  });
  return response.ok;
}

export function newMission(
  installId: string,
  input: Pick<AgentMission, "kind" | "title" | "detail"> & Partial<Pick<AgentMission, "tripId" | "inspirationId" | "nextCheckAt" | "deviceToken" | "context">>
): AgentMission {
  const now = new Date().toISOString();
  return {
    id: randomUUID(),
    installId,
    tripId: input.tripId,
    inspirationId: input.inspirationId,
    kind: input.kind,
    title: input.title,
    detail: input.detail,
    status: "queued",
    deviceToken: normalizeDeviceToken(input.deviceToken),
    context: input.context,
    assignedAgents: agentsForMission(input.kind),
    runCount: 0,
    createdAt: now,
    updatedAt: now,
    nextCheckAt: input.nextCheckAt
  };
}

function agentsForMission(kind: AgentMission["kind"]) {
  switch (kind) {
    case "guardian": return ["sentinel", "navigator", "clerk", "coordinator"];
    case "inspiration": return ["scout", "coordinator"];
    case "recovery": return ["recovery", "navigator", "coordinator"];
    case "concierge": return ["concierge", "navigator", "coordinator"];
    case "planning": return ["scout", "navigator", "coordinator"];
  }
}

export function cleanText(value: unknown, maximum = 1_000) {
  return typeof value === "string" ? value.trim().slice(0, maximum) : "";
}
