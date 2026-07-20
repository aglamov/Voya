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
  selectionReason?: string;
  verificationSummary?: string;
  agentChecks?: string[];
  place?: {
    id: string;
    name: string;
    address?: string;
    rating?: number;
    userRatingCount?: number;
    mapsURL?: string;
  };
};

function normalizedTokens(value: string) {
  return value.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((token) => token.length > 2).map((token) => {
    if (token.startsWith("музык") || token.startsWith("концерт") || token.startsWith("джаз")) return "music";
    if (token.startsWith("океан") || token.startsWith("мор")) return "ocean";
    if (token.startsWith("тишин") || token.startsWith("спокой")) return "quiet";
    if (token.startsWith("природ") || token.startsWith("дик")) return "nature";
    if (token.startsWith("искус") || token.startsWith("архитект") || token.startsWith("культур")) return "culture";
    if (token.startsWith("чуд") || token.startsWith("восхищ") || token.startsWith("удив")) return "wonder";
    return token;
  });
}

function moodMatch(story: InspirationStory, mood: string) {
  const moodTokens = normalizedTokens(mood);
  if (!moodTokens.length) return 0;
  const storyText = `${story.title} ${story.hook} ${story.theme} ${story.moods.join(" ")}`.toLowerCase();
  return moodTokens.filter((token) => storyText.includes(token)).length / moodTokens.length;
}

function qualityScore(story: InspirationStory, mood: string, order: number) {
  const hasSpecificDate = /^\d{4}-\d{2}-\d{2}$/.test(story.timing);
  const verifiedSource = /^https:\/\//.test(story.sourceURL);
  const evidence = (verifiedSource ? 0.1 : 0) + (hasSpecificDate ? 0.12 : 0.06);
  const relevance = Math.min(0.16, moodMatch(story, mood) * 0.16);
  const editorialOrder = Math.max(0, 0.12 - order * 0.012);
  return story.confidence * 0.58 + evidence + relevance + editorialOrder;
}

function isRussianLocale(locale?: string) {
  return locale?.toLowerCase().startsWith("ru") ?? false;
}

function selectionReason(story: InspirationStory, mood: string, russian: boolean) {
  const hasMoodMatch = moodMatch(story, mood) > 0;
  const moodLead = hasMoodMatch && mood.trim()
    ? russian ? `Это соответствует настроению «${mood.trim()}». ` : `It matches the feeling “${mood.trim()}”. `
    : "";
  if (russian) {
    switch (story.theme) {
      case "music": return `${moodLead}Реальное выступление с известной датой задаёт поездке центр и оставляет время узнать город.`;
      case "phenomenon": return `${moodLead}Природное явление создаёт настоящий повод отправиться в путь именно сейчас.`;
      case "seasonal": return `${moodLead}Впечатление доступно лишь в короткий сезон, поэтому время определяет характер всей поездки.`;
      case "culture": return `${moodLead}Культурная программа даёт путешествию идею и делает его содержательнее обычной поездки в город.`;
      case "nature": return `${moodLead}Место само по себе стоит путешествия, даже если природа или животные поведут себя не так, как хотелось бы.`;
    }
  }
  switch (story.theme) {
    case "music": return `${moodLead}A real dated performance gives the journey a clear centre while leaving room to discover the city.`;
    case "phenomenon": return `${moodLead}The natural phenomenon creates a genuine reason to travel now, not just another destination on a list.`;
    case "seasonal": return `${moodLead}The experience depends on a limited season, so timing changes the character of the whole journey.`;
    case "culture": return `${moodLead}A cultural programme gives the trip a point of view and a stronger shape than a generic city break.`;
    case "nature": return `${moodLead}The place supports a complete journey even if wildlife or conditions do not behave exactly as hoped.`;
  }
}

function diversifiedSelection(stories: InspirationStory[], mood: string, limit = 6) {
  const ranked = stories
    .map((story, index) => ({ story, score: qualityScore(story, mood, index) }))
    .sort((lhs, rhs) => rhs.score - lhs.score);
  const selected: InspirationStory[] = [];
  const destinations = new Set<string>();
  const themeCounts = new Map<InspirationStory["theme"], number>();

  for (const { story } of ranked) {
    const destinationKey = `${story.destination}|${story.country}`.toLowerCase();
    const themeCount = themeCounts.get(story.theme) ?? 0;
    if (destinations.has(destinationKey) || themeCount >= 2) continue;
    selected.push(story);
    destinations.add(destinationKey);
    themeCounts.set(story.theme, themeCount + 1);
    if (selected.length === limit) return selected;
  }
  for (const { story } of ranked) {
    if (selected.some((candidate) => candidate.id === story.id)) continue;
    selected.push(story);
    if (selected.length === limit) break;
  }
  return selected;
}

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

const RUSSIAN_STORY_COPY: Record<string, Partial<InspirationStory>> = {
  "lofoten-aurora": {
    title: "Северное сияние над Лофотенскими островами",
    hook: "Долгие синие сумерки, рыбацкие деревни и четыре ночи с шансом увидеть зелёное небо.",
    destination: "Лофотенские острова",
    country: "Норвегия",
    timing: "Сентябрь–март",
    whyNow: "Тёмный сезон даёт долгие окна для наблюдения, а острова остаются прекрасным путешествием, даже если сияние не появится.",
    experience: ["Ночи в поисках сияния", "Живописные островные дороги", "Арктические рыбацкие деревни"],
    practicalNotes: ["С автомобилем исследовать острова намного проще", "Оставьте не меньше четырёх ночей для наблюдения"],
    mainRisk: "Облачность непредсказуема, поэтому увидеть сияние в конкретную ночь нельзя гарантировать."
  },
  "japan-sakura": {
    title: "Пройти за весной по Японии",
    hook: "Медленное путешествие от храмовых садов к горным онсэнам вслед за цветением сакуры на север.",
    destination: "Киото и Японские Альпы",
    country: "Япония",
    timing: "Конец марта–апрель",
    whyNow: "Прогноз цветения превращает обычный маршрут в путешествие через несколько этапов весны, где время действительно имеет значение.",
    experience: ["Храмовые сады", "Горные онсэны", "Сезонная кухня"],
    practicalNotes: ["Точные даты цветения меняются каждый год", "Популярные города лучше бронировать заранее"],
    mainRisk: "Пик цветения короток, а погода может сдвинуть его на более ранний или поздний срок."
  },
  "azores-whales": {
    title: "Встретить китов у Азорских островов",
    hook: "Вулканические озёра, атлантические скалы и дни, планы которых зависят от того, кто появится на горизонте.",
    destination: "Сан-Мигел",
    country: "Португалия",
    timing: "Апрель–октябрь",
    whyNow: "В течение сезона через архипелаг проходят разные виды китов, а наблюдение за ними становится частью большого путешествия по вулканическому острову.",
    experience: ["Наблюдение за китами", "Вулканические горячие источники", "Прогулки у кратерных озёр"],
    practicalNotes: ["Оставьте запасной день на случай плохой погоды", "Выберите ответственного оператора"],
    mainRisk: "Из-за состояния моря выходы отменяют, а встречу с животными невозможно гарантировать."
  },
  "venice-biennale": {
    title: "Пожить внутри Венецианской биеннале",
    hook: "Искусство в палаццо, верфях и скрытых дворах — и ранние утра для почти пустой Венеции.",
    destination: "Венеция",
    country: "Италия",
    timing: "Сезон биеннале",
    whyNow: "Выставка меняет географию города и открывает пространства, которые обычно не входят в классическое путешествие по Венеции.",
    experience: ["Павильоны Джардини", "Арсенале", "Независимые выставки"],
    practicalNotes: ["Проверьте даты текущей биеннале до бронирования", "Разделите главные площадки на два дня"],
    mainRisk: "Даты и программа зависят от конкретного выпуска биеннале."
  },
  "namibia-desert-sky": {
    title: "Спать под небом пустыни Намиб",
    hook: "Красные дюны на рассвете, огромная тишина и одно из самых тёмных звёздных небес на Земле.",
    destination: "Пустыня Намиб",
    country: "Намибия",
    timing: "Май–октябрь",
    whyNow: "Сухой сезон приносит более прохладную погоду и ясные ночи, подходящие для долгого путешествия по пустыне.",
    experience: ["Рассвет в Соссусфлее", "Лоджи под тёмным небом", "Автопутешествие по пустыне"],
    practicalNotes: ["Расстояния здесь очень большие", "Планируйте запас топлива и воды с осторожностью"],
    mainRisk: "Это путешествие требует тщательной логистики и включает долгие переезды по удалённым дорогам."
  }
};

function localizedStory(story: InspirationStory, russian: boolean): InspirationStory {
  if (!russian) return story;
  return { ...story, ...(RUSSIAN_STORY_COPY[story.id] ?? {}) };
}

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

async function ticketmasterStories(mood: string, russian: boolean): Promise<InspirationStory[]> {
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
      const countryCode = venue?.country?.countryCode?.trim();
      const originalCountry = venue?.country?.name?.trim() ?? countryCode;
      const country = russian && countryCode
        ? new Intl.DisplayNames(["ru"], { type: "region" }).of(countryCode) ?? originalCountry
        : originalCountry;
      const date = event.dates?.start?.localDate;
      const sourceURL = event.url?.trim();
      if (!name || !city || !country || !date || !sourceURL) return [];
      const genre = event.classifications?.[0]?.genre?.name?.trim();
      return [{
        id: `ticketmaster-${event.id ?? Buffer.from(sourceURL).toString("base64url").slice(0, 24)}`,
        title: russian ? `${name} — и несколько дней в городе ${city}` : `${name} — and a few days in ${city}`,
        hook: russian
          ? "Постройте путешествие вокруг настоящего концерта, а остальную историю пусть расскажет город."
          : `Build a journey around a real night of ${genre && genre !== "Undefined" ? genre.toLowerCase() : "live music"}, then let the city become the rest of the story.`,
        destination: city,
        country,
        theme: "music",
        moods: ["music", "event", "city", genre ?? "live"],
        timing: date,
        idealDays: 4,
        whyNow: russian
          ? `${name} запланирован на ${date}${venue?.name ? ` на площадке ${venue.name}` : ""}. Событие задаёт поездке центр, не предписывая весь маршрут.`
          : `${name} is scheduled for ${date}${venue?.name ? ` at ${venue.name}` : ""}. The event gives the trip a fixed centre without prescribing everything around it.`,
        experience: russian
          ? [name, `Свободный день в городе ${city}`, "Вечер в другом районе города"]
          : [name, `A free day in ${city}`, "A neighbourhood evening away from the venue"],
        practicalNotes: russian
          ? ["Проверьте наличие билетов до покупки транспорта", "Храните подтверждение события отдельно от транспортных броней"]
          : ["Verify ticket availability before arranging travel", "Keep the event confirmation separate from transport bookings"],
        mainRisk: russian
          ? "Дата и состав участников могут измениться; Voya считает афишу организатора подтверждением, но не гарантией."
          : "Event dates and line-ups can change; Voya treats the organiser listing as evidence, not a guarantee.",
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

export async function scoutInspirationCandidates(mood: string, savedThemes: string[] = [], locale = "en") {
  const russian = isRussianLocale(locale);
  const liveStories = await ticketmasterStories(mood, russian);
  const local = localCuration(mood, savedThemes);
  return [...liveStories, ...local.stories.map((story) => localizedStory(story, russian))];
}

export async function verifyInspirationCandidates(candidates: InspirationStory[], mood: string, locale = "en") {
  const russian = isRussianLocale(locale);
  const shortlist = diversifiedSelection(candidates, mood, 8);
  return await Promise.all(shortlist.map(async (story) => {
    const result = await findGooglePlace(`${story.destination}, ${story.country}`, russian ? "ru" : "en");
    const place = "data" in result ? result.data : undefined;
    return {
      ...story,
      verificationSummary: [
        story.timing,
        place
          ? russian ? "место проверено через Google Places" : "destination verified with Google Places"
          : russian ? "место сверено с редакционным источником" : "destination checked against the editorial source",
        story.sourceTitle
      ].join(" · "),
      agentChecks: russian
        ? ["Повод для поездки", "Время проверено", place ? "Место проверено" : "Источник проверен"]
        : ["Reason to travel", "Timing checked", place ? "Place verified" : "Source verified"],
      place: place ? {
        id: place.id,
        name: place.name,
        address: place.address,
        rating: place.rating,
        userRatingCount: place.userRatingCount,
        mapsURL: place.mapsURL
      } : undefined
    };
  }));
}

export function editInspirationCandidates(candidates: InspirationStory[], mood: string, locale = "en") {
  const russian = isRussianLocale(locale);
  return candidates.map((story) => ({
    ...story,
    selectionReason: selectionReason(story, mood, russian)
  }));
}

export async function curateInspirationCandidates(
  candidates: InspirationStory[],
  mood: string,
  savedThemes: string[] = [],
  locale = "en"
) {
  const russian = isRussianLocale(locale);
  let ordered = candidates;
  let usedAI = false;
  let aiCuratorNote: string | undefined;
  if (mood && process.env.OPENAI_API_KEY) {
    try {
      const { object } = await generateObject({
        model: openai(openAIModelFor("brief")),
        schema: curationSchema,
        system: "You are Voya's travel editor. Rank only the supplied verified story IDs. Never invent an event, date, price, or destination. Prefer a varied, emotionally coherent collection over generic popularity.",
        prompt: JSON.stringify({ mood, savedThemes, candidates: candidates.map(({ id, title, hook, theme, moods, timing, mainRisk }) => ({ id, title, hook, theme, moods, timing, mainRisk })) })
      });
      const byId = new Map(candidates.map((story) => [story.id, story]));
      const ranked = object.orderedIds.flatMap((id) => byId.get(id) ?? []);
      const remainder = candidates.filter((story) => !object.orderedIds.includes(story.id));
      ordered = [...ranked, ...remainder];
      aiCuratorNote = object.curatorNote;
      usedAI = true;
    } catch {
      // The deterministic editorial feed is intentionally usable without AI.
    }
  }
  return {
    stories: diversifiedSelection(ordered, mood, 6),
    curatorNote: aiCuratorNote ?? (russian
      ? mood.trim()
        ? `Агенты сравнили ${candidates.length} проверенных вариантов по запросу «${mood.trim()}». Здесь самые сильные и разнообразные поводы отправиться в путь.`
        : `Агенты сравнили ${candidates.length} проверенных вариантов. Здесь самые сильные и разнообразные поводы отправиться в путь.`
      : mood.trim()
        ? `${candidates.length} verified candidates were compared for “${mood.trim()}”. These are the strongest and most varied reasons to travel.`
        : `${candidates.length} verified candidates were compared. These are the strongest and most varied reasons to travel.`),
    usedAI
  };
}

export async function buildInspirationFeed(mood: string, savedThemes: string[] = [], locale = "en") {
  const scouted = await scoutInspirationCandidates(mood, savedThemes, locale);
  const verified = await verifyInspirationCandidates(scouted, mood, locale);
  const edited = editInspirationCandidates(verified, mood, locale);
  return await curateInspirationCandidates(edited, mood, savedThemes, locale);
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
  const locale = typeof body.locale === "string" ? body.locale.trim().slice(0, 40) || "en" : "en";
  const release = newInspirationRelease(installId, mood, deviceToken, locale);
  await saveInspirationRelease(release);
  const queued = await enqueueAgentJob({ type: "inspiration", installId, releaseId: release.id, stage: "scouting" });
  if (queued) {
    return res.status(202).json({ release, queued: true });
  }

  const curated = await buildInspirationFeed(mood, savedThemes, locale);
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
