import { timingSafeEqual } from "node:crypto";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { redisCommand, storageConfigured } from "./_storage.js";

type PublicEndpointOptions = {
  name: string;
  hourlyIPLimit: number;
  hourlyInstallLimit: number;
  maxBodyBytes?: number;
};

function firstHeader(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function sameSecret(actual: string | undefined, expected: string) {
  if (!actual) return false;
  const encoder = new TextEncoder();
  const lhs = encoder.encode(actual);
  const rhs = encoder.encode(expected);
  return lhs.length === rhs.length && timingSafeEqual(lhs, rhs);
}

function requestIP(req: VercelRequest) {
  return (firstHeader(req.headers["x-forwarded-for"])?.split(",")[0]
    ?? firstHeader(req.headers["x-real-ip"])
    ?? "unknown").trim().slice(0, 80);
}

function installID(req: VercelRequest) {
  const value = firstHeader(req.headers["x-voya-install-id"])?.trim();
  return value && /^[0-9a-f-]{36}$/i.test(value) ? value.toLowerCase() : undefined;
}

function bodySize(req: VercelRequest) {
  const contentLength = Number(firstHeader(req.headers["content-length"]));
  if (Number.isFinite(contentLength) && contentLength >= 0) return contentLength;
  try {
    return Buffer.byteLength(JSON.stringify(req.body ?? {}));
  } catch {
    return Number.POSITIVE_INFINITY;
  }
}

async function increment(key: string, ttlSeconds: number) {
  const count = await redisCommand<number>(["INCR", key]);
  if (count === 1) await redisCommand(["EXPIRE", key, ttlSeconds]);
  return count ?? 0;
}

export async function protectPublicEndpoint(
  req: VercelRequest,
  res: VercelResponse,
  options: PublicEndpointOptions
) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");

  const maxBodyBytes = options.maxBodyBytes ?? 128_000;
  if (bodySize(req) > maxBodyBytes) {
    res.status(413).json({ error: "Request payload is too large." });
    return false;
  }

  const expectedClientKey = process.env.VOYA_CLIENT_API_KEY?.trim();
  const suppliedClientKey = firstHeader(req.headers["x-voya-client-key"])?.trim();
  if (expectedClientKey && !sameSecret(suppliedClientKey, expectedClientKey)) {
    res.status(401).json({ error: "Unauthorized Voya client." });
    return false;
  }

  const install = installID(req);
  if (process.env.VERCEL_ENV === "production" && !install) {
    res.status(400).json({ error: "Missing app installation identifier." });
    return false;
  }

  if (!storageConfigured()) {
    if (process.env.VERCEL_ENV === "production") {
      res.status(503).json({ error: "API protection storage is not configured." });
      return false;
    }
    return true;
  }

  const bucket = Math.floor(Date.now() / 3_600_000);
  const ipCount = await increment(`voya:rate:${options.name}:ip:${requestIP(req)}:${bucket}`, 3_700);
  const installCount = install
    ? await increment(`voya:rate:${options.name}:install:${install}:${bucket}`, 3_700)
    : 0;
  const limited = ipCount > options.hourlyIPLimit
    || (install ? installCount > options.hourlyInstallLimit : false);
  if (limited) {
    res.setHeader("Retry-After", "3600");
    res.status(429).json({ error: "Request limit exceeded. Try again later." });
    return false;
  }

  return true;
}
