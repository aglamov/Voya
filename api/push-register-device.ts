import type { VercelRequest, VercelResponse } from "@vercel/node";
import { normalizeDeviceToken, redisCommand, storageConfigured } from "./_storage.js";

type RegisterDevicePayload = {
  deviceToken?: string;
  appInstallId?: string;
  platform?: string;
};

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : undefined;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const payload = req.body as RegisterDevicePayload;
  const deviceToken = normalizeDeviceToken(payload.deviceToken);
  if (!deviceToken) {
    return res.status(400).json({ error: "Invalid APNs device token." });
  }

  if (!storageConfigured()) {
    return res.status(202).json({
      accepted: true,
      stored: false,
      warning: "Set UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN to persist registered devices."
    });
  }

  const now = new Date().toISOString();
  await redisCommand(["SADD", "voya:push:devices", deviceToken]);
  await redisCommand([
    "HSET",
    `voya:push:device:${deviceToken}`,
    "platform",
    clean(payload.platform) ?? "ios",
    "appInstallId",
    clean(payload.appInstallId) ?? "",
    "updatedAt",
    now
  ]);

  return res.status(202).json({
    accepted: true,
    stored: true,
    updatedAt: now
  });
}
