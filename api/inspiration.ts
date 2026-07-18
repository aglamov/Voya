import type { VercelRequest, VercelResponse } from "@vercel/node";
import { openai } from "@ai-sdk/openai";
import { generateObject } from "ai";
import { z } from "zod";
import { findGooglePlace } from "./_google-context.js";
import { openAIModelFor } from "./_ai-models.js";
import { protectPublicEndpoint } from "./_security.js";
import { normalizeDeviceToken } from "./_storage.js";
import {
  enqueueAgentJob,
  newInspirationRelease,
  readInspirationRelease,
  requestInstallId,
  saveInspirationRelease
} from "./_agents.js";

export type InspirationStory = {
  id: string;
  title: string;
  hook: string;
  destination: string;
  country: string;
  theme: "music" | "nature" | "culture" | "phenomenon" | "seasonal";
  moods: string[];
  timing: string;
  idealDays: number;
  whyNow: string;
  experience: string[];
  practicalNotes: string[];
  mainRisk: string;
  symbol: string;
  gradient: string[];
  sourceTitle: string;
  sourceURL: string;
  confidence: number;
  place?: {
    id: string;
    name: string;
    address?: string;
    rating?: number;
    userRatingCount?: number;
    mapsURL?: string;
  };
};

export const STORIES: InspirationStory[] = [
  {
    id: "lofoten-aurora",
    title: "Northern lights above the Lofoten Islands",
    hook: "Long blue hours, fishing villages and four nights with a chance to see the sky turn green.",
    destination: "Lofoten Islands",
    country: "Norway",
    theme: "phenomenon",
    moods: ["wonder", "nature", "remote", "winter"],
    timing: "September–March",
    idealDays: 6,
    whyNow: "The dark season creates long viewing windows, while the islands remain a remarkable journey even if the aurora stays hidden.",
    experience: ["Aurora nights", "Scenic island roads", "Arctic fishing villages"],
    practicalNotes: ["A car makes the islands much easier", "Keep at least four viewing nights"],
    mainRisk: "Cloud cover is unpredictable, so no single night can be promised.",
    symbol: "sparkles",
    gradient: ["122B45", "49A99A"],
    sourceTitle: "Visit Norway — Northern Lights",
    sourceURL: "https://www.visitnorway.com/things-to-do/nature-attractions/northern-lights/",
    confidence: 0.92
  },
  {
    id: "japan-sakura",
    title: "Follow spring through Japan",
    hook: "A slow journey from temple gardens to mountain onsen as the cherry blossom season moves north.",
    destination: "Kyoto and the Japanese Alps",
    country: "Japan",
    theme: "seasonal",
    moods: ["beauty", "culture", "slow", "spring"],
    timing: "Late March–April",
    idealDays: 9,
    whyNow: "The blossom forecast turns an ordinary route into a time-sensitive journey through several stages of spring.",
    experience: ["Temple gardens", "Mountain onsen", "Seasonal food"],
    practicalNotes: ["Exact bloom dates vary every year", "Book popular cities well ahead"],
    mainRisk: "Peak bloom is brief and weather can move it earlier or later.",
    symbol: "camera.macro",
    gradient: ["BB6F86", "F1B6A8"],
    sourceTitle: "Japan National Tourism Organization — Cherry Blossoms",
    sourceURL: "https://www.japan.travel/en/uk/inspiration/cherry-blossom-forecast/",
    confidence: 0.9
  },
  {
    id: "azores-whales",
    title: "Meet the whales of the Azores",
    hook: "Volcanic lakes, Atlantic cliffs and days shaped around what appears on the horizon.",
    destination: "São Miguel",
    country: "Portugal",
    theme: "nature",
    moods: ["ocean", "wildlife", "quiet", "nature"],
    timing: "April–October",
    idealDays: 7,
    whyNow: "Different species pass through the archipelago across the season, making the wildlife part of a broader volcanic-island trip.",
    experience: ["Whale watching", "Volcanic hot springs", "Crater-lake walks"],
    practicalNotes: ["Leave a weather buffer for the boat", "Choose a responsible operator"],
    mainRisk: "Sea conditions can cancel departures and sightings are never guaranteed.",
    symbol: "water.waves",
    gradient: ["145B63", "6CB6A6"],
    sourceTitle: "Visit Azores — Whale Watching",
    sourceURL: "https://www.visitazores.com/en/experience-the-azores/whale-watching",
    confidence: 0.91
  },
  {
    id: "venice-biennale",
    title: "Live inside the Venice Biennale",
    hook: "Art spilling from palazzi, shipyards and hidden courtyards — with early mornings reserved for an almost-empty Venice.",
    destination: "Venice",
    country: "Italy",
    theme: "culture",
    moods: ["art", "architecture", "city", "culture"],
    timing: "Biennale season",
    idealDays: 5,
    whyNow: "The exhibition changes the geography of the city and opens spaces that are normally outside a conventional Venice trip.",
    experience: ["Giardini pavilions", "Arsenale", "Independent exhibitions"],
    practicalNotes: ["Verify the edition dates before booking", "Split the main venues across two days"],
    mainRisk: "Dates and programme depend on the current Biennale edition.",
    symbol: "paintpalette.fill",
    gradient: ["623E36", "C98D5B"],
    sourceTitle: "La Biennale di Venezia",
    sourceURL: "https://www.labiennale.org/en",
    confidence: 0.94
  },
  {
    id: "namibia-desert-sky",
    title: "Sleep under Namibia's desert sky",
    hook: "Red dunes at sunrise, immense silence and some of the darkest night skies on Earth.",
    destination: "Namib Desert",
    country: "Namibia",
    theme: "nature",
    moods: ["remote", "roadtrip", "stars", "wonder"],
    timing: "May–October",
    idealDays: 10,
    whyNow: "The dry season brings cooler travel conditions and clear nights suited to a long desert road trip.",
    experience: ["Sossusvlei sunrise", "Dark-sky lodges", "Desert road trip"],
    practicalNotes: ["Distances are large", "Plan fuel and water conservatively"],
    mainRisk: "This is a logistics-heavy journey with long remote driving stages.",
    symbol: "moon.stars.fill",
    gradient: ["6B2C20", "D89048"],
    sourceTitle: "Namibia Tourism Board",
    sourceURL: "https://visitnamibia.com.na/",
    confidence: 0.88
  }
];

const curationSchema = z.object({
  orderedIds: z.array(z.string()).min(1).max(20),
  curatorNote: z.string().min(1).max(400)
});

type TicketmasterDiscoveryEvent = {
  id?: string;
  name?: string;
  url?: string;
  dates?: { start?: { localDate?: string; localTime?: string } };
  classifications?: Array<{ segment?: { name?: string }; genre?: { name?: string } }>;
  _embedded?: {
    venues?: Array<{
      name?: string;
      city?: { name?: string };
      country?: { name?: string; countryCode?: string };
    }>;
  };
};

async function ticketmasterStories(mood: string): Promise<InspirationStory[]> {
  const apiKey = (process.env.TICKETMASTER_API_KEY ?? process.env.TICKETMASTER_CONSUMER_KEY)?.trim();
  if (!apiKey) return [];
  const now = new Date();
  const end = new Date(now.getTime() + 270 * 24 * 60 * 60 * 1000);
  const url = new URL("https://app.ticketmaster.com/discovery/v2/events.json");
  url.searchParams.set("apikey", apiKey);
  url.searchParams.set("classificationName", "music");
  url.searchParams.set("size", "8");
  url.searchParams.set("sort", "date,asc");
  url.searchParams.set("includeTBA", "no");
  url.searchParams.set("includeTBD", "no");
  url.searchParams.set("startDateTime", now.toISOString().replace(/\.\d{3}Z$/, "Z"));
  url.searchParams.set("endDateTime", end.toISOString().replace(/\.\d{3}Z$/, "Z"));
  const normalizedMood = mood.trim();
  if (normalizedMood && !/^(music|concert|festival|музыка|концерт|фестиваль)$/i.test(normalizedMood)) {
    url.searchParams.set("keyword", normalizedMood);
  }
  try {
    const response = await fetch(url);
    if (!response.ok) return [];
    const data = await response.json() as { _embedded?: { events?: TicketmasterDiscoveryEvent[] } };
    return (data._embedded?.events ?? []).flatMap((event): InspirationStory[] => {
      const venue = event._embedded?.venues?.[0];
      const name = event.name?.trim();
      const city = venue?.city?.name?.trim();
      const country = venue?.country?.name?.trim() ?? venue?.country?.countryCode?.trim();
      const date = event.dates?.start?.localDate;
      const sourceURL = event.url?.trim();
      if (!name || !city || !country || !date || !sourceURL) return [];
      const genre = event.classifications?.[0]?.genre?.name?.trim();
      return [{
        id: `ticketmaster-${event.id ?? Buffer.from(sourceURL).toString("base64url").slice(0, 24)}`,
        title: `${name} — and a few days in ${city}`,
        hook: `Build a journey around a real night of ${genre && genre !== "Undefined" ? genre.toLowerCase() : "live music"}, then let the city become the rest of the story.`,
        destination: city,
        country,
        theme: "music",
        moods: ["music", "event", "city", genre ?? "live"],
        timing: date,
        idealDays: 4,
        whyNow: `${name} is scheduled for ${date}${venue?.name ? ` at ${venue.name}` : ""}. The event gives the trip a fixed centre without prescribing everything around it.`,
        experience: [name, `A free day in ${city}`, "A neighbourhood evening away from the venue"],
        practicalNotes: ["Verify ticket availability before arranging travel", "Keep the event confirmation separate from transport bookings"],
        mainRisk: "Event dates and line-ups can change; Voya treats the organiser listing as evidence, not a guarantee.",
        symbol: "music.note",
        gradient: ["51336F", "D14F63"],
        sourceTitle: `Ticketmaster — ${name}`,
        sourceURL,
        confidence: 0.96
      }];
    });
  } catch {
    return [];
  }
}

function localCuration(mood: string, savedThemes: string[]) {
  const tokens = `${mood} ${savedThemes.join(" ")}`.toLowerCase().split(/\W+/).filter(Boolean);
  const stories = [...STORIES].sort((lhs, rhs) => {
    const left = tokens.filter((token) => `${lhs.theme} ${lhs.moods.join(" ")}`.includes(token)).length;
    const right = tokens.filter((token) => `${rhs.theme} ${rhs.moods.join(" ")}`.includes(token)).length;
    return right - left;
  });
  return { stories, curatorNote: mood ? `Ideas selected around “${mood}”.` : "A small collection of journeys worth wanting." };
}

export async function buildInspirationFeed(mood: string, savedThemes: string[] = []) {
  const liveStories = await ticketmasterStories(mood);
  const candidates = [...liveStories, ...STORIES];
  const local = localCuration(mood, savedThemes);
  let curated = { stories: [...liveStories, ...local.stories], curatorNote: local.curatorNote };
  let usedAI = false;
  if (mood && process.env.OPENAI_API_KEY) {
    try {
      const { object } = await generateObject({
        model: openai(openAIModelFor("brief")),
        schema: curationSchema,
        system: "You are Voya's travel editor. Rank only the supplied verified story IDs. Never invent an event, date, price, or destination. Prefer a varied, emotionally coherent collection over generic popularity.",
        prompt: JSON.stringify({ mood, savedThemes, candidates: candidates.map(({ id, title, hook, theme, moods, timing, mainRisk }) => ({ id, title, hook, theme, moods, timing, mainRisk })) })
      });
      const byId = new Map(candidates.map((story) => [story.id, story]));
      const ordered = object.orderedIds.flatMap((id) => byId.get(id) ?? []);
      const remainder = candidates.filter((story) => !object.orderedIds.includes(story.id));
      curated = { stories: [...ordered, ...remainder], curatorNote: object.curatorNote };
      usedAI = true;
    } catch {
      // The deterministic editorial feed is intentionally usable without AI.
    }
  }
  const enrichedStories = await Promise.all(curated.stories.slice(0, 8).map(async (story) => {
    const result = await findGooglePlace(`${story.destination}, ${story.country}`, "en");
    if (!("data" in result)) return story;
    const place = result.data;
    return {
      ...story,
      place: {
        id: place.id,
        name: place.name,
        address: place.address,
        rating: place.rating,
        userRatingCount: place.userRatingCount,
        mapsURL: place.mapsURL
      }
    };
  }));
  return { ...curated, stories: [...enrichedStories, ...curated.stories.slice(8)], usedAI };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET" && req.method !== "POST") {
    res.setHeader("Allow", "GET, POST");
    return res.status(405).json({ error: "Method not allowed." });
  }
  if (!(await protectPublicEndpoint(req, res, {
    name: "inspiration",
    hourlyIPLimit: 100,
    hourlyInstallLimit: 60,
    maxBodyBytes: 24_000
  }))) return;

  const installId = requestInstallId(req);
  if (req.method === "GET") {
    const release = await readInspirationRelease(installId);
    return res.status(200).json({ release: release ?? null });
  }

  const body = req.body && typeof req.body === "object" ? req.body as Record<string, unknown> : {};
  const mood = typeof body.mood === "string" ? body.mood.trim().slice(0, 160) : "";
  const savedThemes = Array.isArray(body.savedThemes)
    ? body.savedThemes.filter((item): item is string => typeof item === "string").slice(0, 12)
    : [];
  const deviceToken = normalizeDeviceToken(body.deviceToken);
  const release = newInspirationRelease(installId, mood, deviceToken);
  await saveInspirationRelease(release);
  const queued = await enqueueAgentJob({ type: "inspiration", installId, releaseId: release.id });
  if (queued) {
    return res.status(202).json({ release, queued: true });
  }

  const curated = await buildInspirationFeed(mood, savedThemes);
  const now = new Date().toISOString();
  const ready = {
    ...release,
    status: "ready" as const,
    stage: "ready" as const,
    progress: 1,
    updatedAt: now,
    readyAt: now,
    curatorNote: curated.curatorNote,
    stories: curated.stories,
    usedAI: curated.usedAI,
    agents: release.agents.map((agent) => ({ ...agent, state: "complete" as const }))
  };
  await saveInspirationRelease(ready);

  return res.status(200).json({ release: ready, queued: false });
}
