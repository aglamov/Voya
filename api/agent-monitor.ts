import type { VercelRequest, VercelResponse } from "@vercel/node";
import { timingSafeEqual } from "node:crypto";
import { dueMissionMembers, enqueueAgentJob, readMission } from "./_agents.js";
import { processAgentJob } from "./agent-worker.js";
import { processDueFlightWatches } from "./_flight-monitor.js";
import { processNotificationOutbox } from "./_travel-events.js";
import { redisCommand } from "./_storage.js";

function header(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function authorized(req: VercelRequest) {
  const expected = (process.env.AGENT_MONITOR_SECRET ?? process.env.CRON_SECRET)?.trim();
  const authorization = header(req.headers.authorization)?.trim();
  const actual = authorization?.toLowerCase().startsWith("bearer ") ? authorization.slice(7).trim() : undefined;
  if (!expected || !actual) return false;
  const encoder = new TextEncoder();
  const lhs = encoder.encode(actual);
  const rhs = encoder.encode(expected);
  return lhs.length === rhs.length && timingSafeEqual(lhs, rhs);
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST" && req.method !== "GET") return res.status(405).json({ error: "Method not allowed." });
  if (!authorized(req)) return res.status(401).json({ error: "Unauthorized agent monitor invocation." });

  const members = await dueMissionMembers();
  const flightMonitoringPromise = processDueFlightWatches(
    Math.max(1, Math.min(30, Number(process.env.FLIGHT_MONITOR_MAX_PER_RUN) || 12))
  );
  let queued = 0;
  let processedInline = 0;
  const errors: string[] = [];
  for (const member of members) {
    const separator = member.indexOf(":");
    const installId = member.slice(0, separator);
    const missionId = member.slice(separator + 1);
    const mission = await readMission(installId, missionId);
    if (!mission) continue;
    const job = { type: "mission" as const, installId, missionId };
    try {
      if (await enqueueAgentJob(job)) {
        queued += 1;
      } else {
        await processAgentJob(job);
        processedInline += 1;
      }
    } catch (error) {
      errors.push(error instanceof Error ? error.message : "Mission dispatch failed.");
    }
  }
  const flightMonitoring = await flightMonitoringPromise;
  const notificationOutbox = await processNotificationOutbox(40);
  errors.push(...flightMonitoring.errors, ...notificationOutbox.errors);
  const completedAt = new Date().toISOString();
  await redisCommand(["SET", "voya:agent-monitor:last-successful-run", completedAt, "EX", 2 * 60 * 60]);
  return res.status(200).json({
    ok: errors.length === 0,
    missions: { due: members.length, queued, processedInline },
    flightMonitoring,
    notificationOutbox,
    completedAt,
    errors: [...new Set(errors)]
  });
}
