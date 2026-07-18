import type { VercelRequest, VercelResponse } from "@vercel/node";
import { z } from "zod";
import { googleTravelContext } from "./_google-context.js";
import { protectPublicEndpoint } from "./_security.js";

const itemSchema = z.object({
  id: z.string().max(80),
  kind: z.string().max(40),
  title: z.string().max(240),
  location: z.string().max(300).optional().default(""),
  status: z.string().max(120).optional().default(""),
  startsAt: z.string().datetime().nullable().optional(),
  endsAt: z.string().datetime().nullable().optional(),
  hasConfirmationCode: z.boolean().optional().default(false)
});

const requestSchema = z.object({
  trip: z.object({
    id: z.string().max(80),
    title: z.string().max(240),
    destination: z.string().max(240).nullable().optional(),
    startsAt: z.string().datetime().nullable().optional(),
    endsAt: z.string().datetime().nullable().optional()
  }),
  itinerary: z.array(itemSchema).max(80),
  locale: z.string().max(40).optional()
});

type Finding = {
  id: string;
  agent: "sentinel" | "navigator" | "clerk" | "coordinator";
  severity: "calm" | "watch" | "action";
  title: string;
  detail: string;
  itemId?: string;
};

function environmentalLocation(input: z.infer<typeof requestSchema>) {
  const now = Date.now();
  const relevantItem = [...input.itinerary]
    .filter((item) => item.location.trim())
    .sort((lhs, rhs) => (lhs.startsAt ?? "9").localeCompare(rhs.startsAt ?? "9"))
    .find((item) => !item.endsAt || Date.parse(item.endsAt) >= now)
    ?? input.itinerary.find((item) => item.location.trim());
  return relevantItem?.location.trim() || input.trip.destination?.trim() || "";
}

async function environmentalFindings(input: z.infer<typeof requestSchema>): Promise<Finding[]> {
  const location = environmentalLocation(input);
  if (!location) return [];
  const isRussian = input.locale?.toLowerCase().startsWith("ru") === true;
  const languageCode = isRussian ? "ru" : "en";
  const context = await googleTravelContext(location, languageCode);
  const place = "data" in context.place ? context.place.data : undefined;
  if (!place) return [];

  const findings: Finding[] = [];
  if (context.airQuality && "data" in context.airQuality) {
    const air = context.airQuality.data;
    const value = air.aqi;
    const severity: Finding["severity"] = value != null && value >= 80 ? "action" : value != null && value >= 60 ? "watch" : "calm";
    findings.push({
      id: `air-quality-${place.id}`,
      agent: "sentinel",
      severity,
      title: severity === "calm"
        ? (isRussian ? `Воздух в ${place.name} в норме` : `Air quality in ${place.name} looks comfortable`)
        : (isRussian ? `Проверьте качество воздуха в ${place.name}` : `Check the air quality in ${place.name}`),
      detail: [
        value == null ? undefined : `UAQI ${value}`,
        air.category,
        air.dominantPollutant ? (isRussian ? `Основной загрязнитель: ${air.dominantPollutant.toUpperCase()}` : `Dominant pollutant: ${air.dominantPollutant.toUpperCase()}`) : undefined,
        severity !== "calm" ? air.recommendation : undefined,
        "Google Air Quality"
      ].filter(Boolean).join(" · ")
    });
  }

  if (context.pollen && "data" in context.pollen) {
    const pollen = context.pollen.data;
    const value = pollen.maximumIndex;
    const severity: Finding["severity"] = value != null && value >= 4 ? "action" : value != null && value >= 3 ? "watch" : "calm";
    const typeNames = pollen.dominantTypes.map((type) => type.name).join(", ");
    findings.push({
      id: `pollen-${place.id}`,
      agent: "sentinel",
      severity,
      title: severity === "calm"
        ? (isRussian ? `Пыльцевая нагрузка в ${place.name} невысокая` : `Pollen levels in ${place.name} are low`)
        : (isRussian ? `Высокий уровень пыльцы в ${place.name}` : `Elevated pollen in ${place.name}`),
      detail: [
        value == null ? undefined : `UPI ${value}/5`,
        typeNames || undefined,
        pollen.peakDate ? (isRussian ? `Пик в ближайшие три дня: ${pollen.peakDate}` : `Three-day peak: ${pollen.peakDate}`) : undefined,
        severity !== "calm" ? pollen.dominantTypes.find((type) => type.recommendation)?.recommendation : undefined,
        "Google Pollen"
      ].filter(Boolean).join(" · ")
    });
  }

  return findings;
}

async function evaluate(input: z.infer<typeof requestSchema>) {
  const now = Date.now();
  const sorted = [...input.itinerary].sort((a, b) => (a.startsAt ?? "9").localeCompare(b.startsAt ?? "9"));
  const findings: Finding[] = [];

  for (const item of sorted) {
    const start = item.startsAt ? Date.parse(item.startsAt) : undefined;
    if (!start) {
      findings.push({
        id: `missing-time-${item.id}`,
        agent: "clerk",
        severity: "watch",
        title: `Add timing for ${item.title}`,
        detail: "Guardian cannot protect the connection until this item's time is known.",
        itemId: item.id
      });
    }
    if (item.kind.toLowerCase() === "flight" && !item.hasConfirmationCode) {
      findings.push({
        id: `missing-confirmation-${item.id}`,
        agent: "clerk",
        severity: "watch",
        title: `Confirmation needed for ${item.title}`,
        detail: "Add the booking reference so Voya can keep the flight evidence together.",
        itemId: item.id
      });
    }
    if (/cancel|отмен/i.test(item.status)) {
      findings.push({
        id: `cancelled-${item.id}`,
        agent: "sentinel",
        severity: "action",
        title: `${item.title} needs a recovery plan`,
        detail: "The current status may break later stages of the trip.",
        itemId: item.id
      });
    }
  }

  for (let index = 1; index < sorted.length; index += 1) {
    const previous = sorted[index - 1];
    const current = sorted[index];
    const previousEnd = Date.parse(previous.endsAt ?? previous.startsAt ?? "");
    const currentStart = Date.parse(current.startsAt ?? "");
    if (!Number.isFinite(previousEnd) || !Number.isFinite(currentStart)) continue;
    const gapMinutes = Math.round((currentStart - previousEnd) / 60_000);
    if (gapMinutes >= 0 && gapMinutes < 60 && previous.kind.toLowerCase() !== "hotel") {
      findings.push({
        id: `tight-${previous.id}-${current.id}`,
        agent: "navigator",
        severity: gapMinutes < 30 ? "action" : "watch",
        title: `Only ${gapMinutes} minutes between stages`,
        detail: `${previous.title} and ${current.title} leave little recovery time.`,
        itemId: current.id
      });
    }
  }

  const upcoming = sorted.filter((item) => item.startsAt && Date.parse(item.startsAt) >= now);
  findings.push(...await environmentalFindings(input));
  if (findings.length === 0) {
    findings.push({
      id: "guardian-calm",
      agent: "coordinator",
      severity: "calm",
      title: "Your trip is holding together",
      detail: upcoming.length > 0 ? `Guardian is watching ${upcoming.length} upcoming stages.` : "No immediate action is needed."
    });
  }

  const severityOrder: Record<Finding["severity"], number> = { action: 0, watch: 1, calm: 2 };
  findings.sort((lhs, rhs) => severityOrder[lhs.severity] - severityOrder[rhs.severity]);

  const actionCount = findings.filter((item) => item.severity === "action").length;
  const watchCount = findings.filter((item) => item.severity === "watch").length;
  return {
    generatedAt: new Date().toISOString(),
    status: actionCount > 0 ? "action" : watchCount > 0 ? "watch" : "calm",
    headline: actionCount > 0
      ? "Guardian found something that needs attention"
      : watchCount > 0
        ? "Guardian is watching a few weak points"
        : "Guardian is watching your journey",
    summary: actionCount > 0
      ? `${actionCount} issue${actionCount === 1 ? "" : "s"} may affect the trip.`
      : watchCount > 0
        ? `${watchCount} detail${watchCount === 1 ? "" : "s"} should be strengthened before departure.`
        : "Everything currently looks coherent.",
    watchCount: Math.max(upcoming.length, input.itinerary.length),
    findings: findings.slice(0, 8),
    agents: [
      { id: "sentinel", name: "Sentinel", responsibility: "Live changes and disruption", state: "watching" },
      { id: "navigator", name: "Navigator", responsibility: "Transfers and connection time", state: "watching" },
      { id: "clerk", name: "Clerk", responsibility: "Bookings and missing details", state: "watching" },
      { id: "coordinator", name: "Coordinator", responsibility: "Trip-wide impact", state: "watching" }
    ]
  };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed." });
  }
  if (!(await protectPublicEndpoint(req, res, {
    name: "guardian",
    hourlyIPLimit: 120,
    hourlyInstallLimit: 80,
    maxBodyBytes: 96_000
  }))) return;

  const parsed = requestSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid trip snapshot.", issues: parsed.error.issues });
  return res.status(200).json(await evaluate(parsed.data));
}
