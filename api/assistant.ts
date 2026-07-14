import type { VercelRequest, VercelResponse } from "@vercel/node";
import { openai } from "@ai-sdk/openai";
import { generateObject } from "ai";
import { z } from "zod";
import { openAIModelFor } from "./_ai-models.js";
import { protectPublicEndpoint } from "./_security.js";

type AssistantSignal = {
  title: string;
  message: string;
  severity: "calm" | "watch" | "action";
  sourceTitle?: string;
  sourceDetail?: string;
};

type AssistantRequest = {
  locale?: string;
  languageCode?: string;
  languageName?: string;
  question?: string;
  trip?: {
    title?: string;
    dates?: string;
    destination?: string | null;
    startsAt?: string | null;
    endsAt?: string | null;
  };
  assessment?: {
    score?: number;
    riskLabel?: string;
    readyCount?: number;
    watchCount?: number;
    actionCount?: number;
  };
  nextItem?: {
    kind?: string;
    title?: string;
    location?: string;
    status?: string;
    startsAt?: string | null;
    endsAt?: string | null;
  } | null;
  itinerary?: Array<{
    kind?: string;
    title?: string;
    location?: string;
    status?: string;
    startsAt?: string | null;
    endsAt?: string | null;
    hasBoardingPass?: boolean;
    hasSourceDocument?: boolean;
  }>;
  alerts?: AssistantSignal[];
  weather?: {
    title?: string;
    summary?: string;
    recommendation?: string;
    items?: string[];
    severity?: "calm" | "watch" | "action";
  };
  sources?: Array<{
    title?: string;
    detail?: string;
    count?: number;
    severity?: "calm" | "watch" | "action";
  }>;
};

type AssistantResponse = {
  summary: string;
  assessmentTitle: string;
  assessmentDetail: string;
  answer: string;
  packingAdvice: string;
  nextActions: string[];
  confidence: number;
  usedAI: boolean;
};

const assistantResponseSchema = z.object({
  summary: z.string().min(1),
  assessmentTitle: z.string().min(1),
  assessmentDetail: z.string().min(1),
  answer: z.string().min(1),
  packingAdvice: z.string().min(1),
  nextActions: z.array(z.string().min(1)).min(1).max(5),
  confidence: z.number().min(0).max(1)
});

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function responseLanguageInstruction(languageCode?: string, languageName?: string, locale?: string) {
  const code = clean(languageCode) || "en";
  const name = clean(languageName) || code;
  const region = clean(locale) || code;

  if (code.toLowerCase().startsWith("en")) {
    return "Write all human-facing assistant text in English.";
  }

  return [
    `Write all human-facing assistant text in ${name} (locale ${region}).`,
    "Keep airline codes, flight numbers, airport codes, confirmation codes, URLs, hotel/venue names, street addresses, provider values, and proper nouns as shown unless a localized form is obvious.",
    "Do not translate machine enum values, provider names, URLs, or booking references."
  ].join(" ");
}

function severityRank(value?: string) {
  switch (value) {
    case "action": return 2;
    case "watch": return 1;
    default: return 0;
  }
}

function isRussianRequest(body: AssistantRequest) {
  return [body.languageCode, body.locale, body.languageName]
    .map((value) => clean(value).toLowerCase())
    .some((value) => value === "ru" || value.startsWith("ru-") || value.startsWith("ru_") || value.includes("russian") || value.includes("рус"));
}

function deterministicResponse(body: AssistantRequest): AssistantResponse {
  const isRussian = isRussianRequest(body);
  const tripTitle = clean(body.trip?.title) || (isRussian ? "эта поездка" : "this trip");
  const alerts = body.alerts ?? [];
  const highest = alerts.reduce((current, alert) => Math.max(current, severityRank(alert.severity)), 0);
  const topAlert = [...alerts].sort((a, b) => severityRank(b.severity) - severityRank(a.severity))[0];
  const nextItemTitle = clean(body.nextItem?.title);
  const score = Math.round(body.assessment?.score ?? 0);
  const weatherRecommendation = clean(body.weather?.recommendation) || (isRussian
    ? "Проверьте прогноз перед выходом и возьмите вещи, которые легко комбинировать."
    : "Check the forecast before leaving and pack adaptable layers.");
  const weatherItems = body.weather?.items?.filter(Boolean) ?? [];
  const packingAdvice = [weatherRecommendation, ...weatherItems].join(" ");

  const assessmentTitle = highest >= 2
    ? (isRussian ? `${tripTitle}: нужно действие` : `${tripTitle} needs action`)
    : highest === 1
      ? (isRussian ? `${tripTitle}: нужно следить` : `${tripTitle} needs watching`)
      : (isRussian ? `${tripTitle} выглядит готовой` : `${tripTitle} looks ready`);

  const assessmentDetail = topAlert
    ? `${topAlert.title}: ${topAlert.message}`
    : nextItemTitle
      ? (isRussian
        ? `Дальше: ${nextItemTitle}. Живые сигналы провайдеров появятся после обновления.`
        : `Next up: ${nextItemTitle}. Live provider signals will appear as they refresh.`)
      : (isRussian
        ? "Добавьте элементы маршрута, чтобы включить подсказки по маршрутам, рейсам, погоде и готовности."
        : "Add itinerary items to unlock route, flight, weather, and readiness guidance.");

  const nextActions = alerts
    .filter((alert) => alert.severity === "action" || alert.severity === "watch")
    .slice(0, 4)
    .map((alert) => `${alert.title}: ${alert.message}`);

  if (nextActions.length === 0 && nextItemTitle) {
    nextActions.push(isRussian ? `Подготовьтесь к ${nextItemTitle}.` : `Prepare for ${nextItemTitle}.`);
  }
  if (nextActions.length === 0) {
    nextActions.push(isRussian ? "Импортируйте или добавьте подтвержденный пункт маршрута." : "Import or add a confirmed itinerary item.");
  }

  const question = clean(body.question);
  const answer = question
    ? [assessmentDetail, packingAdvice].filter(Boolean).join(" ")
    : assessmentDetail;

  return {
    summary: score > 0
      ? (isRussian ? `Оценка готовности поездки: ${score}. ${assessmentDetail}` : `Trip readiness score: ${score}. ${assessmentDetail}`)
      : assessmentDetail,
    assessmentTitle,
    assessmentDetail,
    answer,
    packingAdvice,
    nextActions,
    confidence: body.alerts?.length ? 0.72 : 0.48,
    usedAI: false
  };
}

async function aiResponse(body: AssistantRequest, fallback: AssistantResponse): Promise<AssistantResponse> {
  if (!process.env.OPENAI_API_KEY) {
    return fallback;
  }

  const languageInstruction = responseLanguageInstruction(body.languageCode, body.languageName, body.locale);

  try {
    const { object } = await generateObject({
      model: openai(openAIModelFor("brief")),
      schema: assistantResponseSchema,
      schemaName: "VoyaAssistantDecision",
      schemaDescription: "Travel assistant decision summary grounded only in trusted app/provider facts.",
      system: [
        "You are Voya, a practical travel assistant inside a travel app.",
        "Use only the provided facts. Do not invent gates, delays, routes, weather, prices, documents, opening hours, or policy details.",
        "Provider facts are more authoritative than user-facing labels. Missing facts should be named as missing.",
        "Translate facts into decisions: what matters now, why it matters, what to pack, and what to do next.",
        "Keep copy concise enough for a mobile assistant card.",
        "If the user asks a question, answer it directly from the facts. If the facts do not support an answer, say what data is missing.",
        languageInstruction,
        "Return structured JSON only."
      ].join(" "),
      prompt: [
        `Locale: ${body.locale ?? "unknown"}`,
        languageInstruction,
        `User question: ${clean(body.question) || "none"}`,
        "",
        "Trusted assistant facts:",
        JSON.stringify(body, null, 2),
        "",
        "Fallback deterministic response, available if provider data is thin:",
        JSON.stringify(fallback, null, 2)
      ].join("\n")
    });

    return {
      ...object,
      nextActions: object.nextActions.slice(0, 5),
      usedAI: true
    };
  } catch (error) {
    console.error("Assistant AI generation failed", error);
    return fallback;
  }
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!await protectPublicEndpoint(req, res, { name: "assistant", hourlyIPLimit: 180, hourlyInstallLimit: 60, maxBodyBytes: 160_000 })) return;

  const body = req.body as AssistantRequest;
  const fallback = deterministicResponse(body);
  const response = await aiResponse(body, fallback);
  return res.status(200).json(response);
}
