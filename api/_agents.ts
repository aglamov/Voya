import type { VercelRequest } from "@vercel/node";
import { randomUUID } from "node:crypto";
import { redisCommand, storageConfigured } from "./_storage.js";

export type AgentMissionStatus = "active" | "waiting" | "completed" | "cancelled";

export type AgentMission = {
  id: string;
  installId: string;
  tripId?: string;
  inspirationId?: string;
  kind: "guardian" | "inspiration" | "planning" | "recovery" | "concierge";
  title: string;
  detail: string;
  status: AgentMissionStatus;
  createdAt: string;
  updatedAt: string;
  nextCheckAt?: string;
};

export function requestInstallId(req: VercelRequest) {
  const raw = req.headers["x-voya-install-id"];
  const value = (Array.isArray(raw) ? raw[0] : raw)?.trim().toLowerCase();
  return value && /^[0-9a-f-]{36}$/i.test(value) ? value : "development";
}

function missionKey(installId: string) {
  return `voya:agent-missions:${installId}`;
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
  if (!storageConfigured()) return [];
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
  if (!storageConfigured()) return undefined;
  const raw = await redisCommand<string>(["HGET", missionKey(installId), id]);
  if (!raw) return undefined;
  try {
    return JSON.parse(raw) as AgentMission;
  } catch {
    return undefined;
  }
}

export async function saveMission(mission: AgentMission) {
  if (!storageConfigured()) return mission;
  const key = missionKey(mission.installId);
  await redisCommand(["HSET", key, mission.id, JSON.stringify(mission)]);
  await redisCommand(["EXPIRE", key, 180 * 24 * 60 * 60]);
  return mission;
}

export function newMission(
  installId: string,
  input: Pick<AgentMission, "kind" | "title" | "detail"> & Partial<Pick<AgentMission, "tripId" | "inspirationId" | "nextCheckAt">>
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
    status: "active",
    createdAt: now,
    updatedAt: now,
    nextCheckAt: input.nextCheckAt
  };
}

export function cleanText(value: unknown, maximum = 1_000) {
  return typeof value === "string" ? value.trim().slice(0, maximum) : "";
}
