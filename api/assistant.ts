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
    summary?: string;
    destination?: string | null;
    startsAt?: string | null;
    endsAt?: string | null;
    notes?: string | null;
    sourceName?: string;
    startLocationName?: string | null;
    endLocationName?: string | null;
  };
  assessment?: {
    score?: number;
    riskLabel?: string;
    readyCount?: number;
    watchCount?: number;
    actionCount?: number;
  };
  journey?: {
    phase?: "planning" | "preparing" | "active" | "between" | "completed";
    phaseLabel?: string;
    title?: string;
    detail?: string;
    progress?: number;
    completedItems?: number;
    totalItems?: number;
    location?: string | null;
    status?: string | null;
    timeSummary?: string | null;
    timingContext?: string | null;
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
    providerName?: string | null;
    sourceName?: string | null;
    hasConfirmationCode?: boolean;
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
  environment?: Array<{
    kind?: "place" | "weather" | "route" | "event" | "flight" | "warning";
    title?: string;
    value?: string;
    detail?: string | null;
    severity?: "calm" | "watch" | "action";
  }>;
  sources?: Array<{
    title?: string;
    detail?: string;
    count?: number;
    severity?: "calm" | "watch" | "action";
  }>;
  conversation?: Array<{
    role?: "user" | "assistant" | string;
    content?: string;
  }>;
};

type AssistantResponse = {
  summary: string;
  assessmentTitle: string;
  assessmentDetail: string;
  answer: string;
  packingAdvice: string;
  nextActions: string[];
  nextItemDescription: string;
  riskOverview: string;
  additionalRisks: Array<{
    title: string;
    description: string;
    severity: "watch" | "action";
  }>;
  suggestedQuestions: string[];
  answerSources: string[];
  confidence: number;
  usedAI: boolean;
};

const assistantRiskSchema = z.object({
  title: z.string().min(1).max(300),
  description: z.string().min(1).max(1_500),
  severity: z.enum(["watch", "action"])
});

const assistantResponseSchema = z.object({
  summary: z.string().min(1).max(2_000),
  assessmentTitle: z.string().min(1).max(300),
  assessmentDetail: z.string().min(1).max(1_500),
  answer: z.string().min(1).max(4_000),
  packingAdvice: z.string().min(1).max(1_500),
  nextActions: z.array(z.string().min(1).max(1_000)).min(1).max(5),
  nextItemDescription: z.string().min(1).max(1_500),
  riskOverview: z.string().min(1).max(2_000),
  additionalRisks: z.array(assistantRiskSchema).max(5),
  suggestedQuestions: z.array(z.string().min(1).max(200)).min(2).max(4),
  answerSources: z.array(z.string().min(1).max(160)).max(5),
  confidence: z.number().min(0).max(1)
});

function clean(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function boundedText(value: unknown, maximumLength: number) {
  const text = clean(value);
  return text ? text.slice(0, maximumLength) : undefined;
}

function boundedNumber(value: unknown, minimum: number, maximum: number) {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(minimum, Math.min(maximum, value))
    : undefined;
}

function normalizedSeverity(value: unknown): "calm" | "watch" | "action" {
  return value === "action" || value === "watch" ? value : "calm";
}

function normalizedPhase(value: unknown): "planning" | "preparing" | "active" | "between" | "completed" | undefined {
  return value === "planning" || value === "preparing" || value === "active" || value === "between" || value === "completed"
    ? value
    : undefined;
}

function normalizedEnvironmentKind(value: unknown): "place" | "weather" | "route" | "event" | "flight" | "warning" | undefined {
  return value === "place" || value === "weather" || value === "route" || value === "event" || value === "flight" || value === "warning"
    ? value
    : undefined;
}

function normalizedRequest(input: AssistantRequest): AssistantRequest {
  const trip = input.trip && typeof input.trip === "object" ? input.trip : undefined;
  const journey = input.journey && typeof input.journey === "object" ? input.journey : undefined;
  const assessment = input.assessment && typeof input.assessment === "object" ? input.assessment : undefined;
  const weather = input.weather && typeof input.weather === "object" ? input.weather : undefined;
  const itinerary = Array.isArray(input.itinerary) ? input.itinerary : [];
  const alerts = Array.isArray(input.alerts) ? input.alerts : [];
  const environment = Array.isArray(input.environment) ? input.environment : [];
  const sources = Array.isArray(input.sources) ? input.sources : [];
  const conversation = Array.isArray(input.conversation) ? input.conversation : [];
  const normalizeItem = (item: NonNullable<AssistantRequest["itinerary"]>[number]) => ({
    kind: boundedText(item.kind, 32),
    title: boundedText(item.title, 300),
    location: boundedText(item.location, 500),
    status: boundedText(item.status, 500),
    startsAt: boundedText(item.startsAt, 64),
    endsAt: boundedText(item.endsAt, 64),
    providerName: boundedText(item.providerName, 160),
    sourceName: boundedText(item.sourceName, 160),
    hasConfirmationCode: item.hasConfirmationCode === true,
    hasBoardingPass: item.hasBoardingPass === true,
    hasSourceDocument: item.hasSourceDocument === true
  });

  return {
    locale: boundedText(input.locale, 32),
    languageCode: boundedText(input.languageCode, 16),
    languageName: boundedText(input.languageName, 64),
    question: boundedText(input.question, 2_000),
    trip: trip ? {
      title: boundedText(trip.title, 300),
      dates: boundedText(trip.dates, 160),
      summary: boundedText(trip.summary, 1_500),
      destination: boundedText(trip.destination, 500),
      startsAt: boundedText(trip.startsAt, 64),
      endsAt: boundedText(trip.endsAt, 64),
      notes: boundedText(trip.notes, 4_000),
      sourceName: boundedText(trip.sourceName, 160),
      startLocationName: boundedText(trip.startLocationName, 500),
      endLocationName: boundedText(trip.endLocationName, 500)
    } : undefined,
    assessment: assessment ? {
      score: boundedNumber(assessment.score, 0, 100),
      riskLabel: boundedText(assessment.riskLabel, 80),
      readyCount: boundedNumber(assessment.readyCount, 0, 1_000),
      watchCount: boundedNumber(assessment.watchCount, 0, 1_000),
      actionCount: boundedNumber(assessment.actionCount, 0, 1_000)
    } : undefined,
    journey: journey ? {
      phase: normalizedPhase(journey.phase),
      phaseLabel: boundedText(journey.phaseLabel, 120),
      title: boundedText(journey.title, 300),
      detail: boundedText(journey.detail, 1_500),
      progress: boundedNumber(journey.progress, 0, 1),
      completedItems: boundedNumber(journey.completedItems, 0, 1_000),
      totalItems: boundedNumber(journey.totalItems, 0, 1_000),
      location: boundedText(journey.location, 500),
      status: boundedText(journey.status, 500),
      timeSummary: boundedText(journey.timeSummary, 160),
      timingContext: boundedText(journey.timingContext, 160)
    } : undefined,
    nextItem: input.nextItem && typeof input.nextItem === "object"
      ? normalizeItem(input.nextItem)
      : null,
    itinerary: itinerary.slice(0, 80).map(normalizeItem),
    alerts: alerts.slice(0, 60).map((alert) => ({
      title: boundedText(alert.title, 300) ?? "",
      message: boundedText(alert.message, 1_500) ?? "",
      severity: normalizedSeverity(alert.severity),
      sourceTitle: boundedText(alert.sourceTitle, 160),
      sourceDetail: boundedText(alert.sourceDetail, 1_000)
    })),
    weather: weather ? {
      title: boundedText(weather.title, 200),
      summary: boundedText(weather.summary, 1_500),
      recommendation: boundedText(weather.recommendation, 1_500),
      items: Array.isArray(weather.items)
        ? weather.items.slice(0, 12).map((item) => boundedText(item, 500) ?? "").filter(Boolean)
        : [],
      severity: normalizedSeverity(weather.severity)
    } : undefined,
    environment: environment.slice(0, 20).map((signal) => ({
      kind: normalizedEnvironmentKind(signal.kind),
      title: boundedText(signal.title, 200),
      value: boundedText(signal.value, 500),
      detail: boundedText(signal.detail, 1_000),
      severity: normalizedSeverity(signal.severity)
    })),
    sources: sources.slice(0, 20).map((source) => ({
      title: boundedText(source.title, 160),
      detail: boundedText(source.detail, 1_000),
      count: boundedNumber(source.count, 0, 1_000),
      severity: normalizedSeverity(source.severity)
    })),
    conversation: conversation.slice(-12).map((turn) => ({
      role: turn.role === "assistant" ? "assistant" : "user",
      content: boundedText(turn.content, 2_000)
    })).filter((turn) => Boolean(turn.content))
  };
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
  const stageTitle = clean(body.journey?.title) || nextItemTitle;
  const stageTiming = clean(body.journey?.timingContext);
  const stageLocation = clean(body.journey?.location);
  const stageContext = stageTitle
    ? [
        isRussian ? `Текущий фокус: ${stageTitle}.` : `Current focus: ${stageTitle}.`,
        stageTiming,
        stageLocation ? (isRussian ? `Место: ${stageLocation}.` : `Place: ${stageLocation}.`) : ""
      ].filter(Boolean).join(" ")
    : "";
  const score = Math.round(body.assessment?.score ?? 0);
  const weatherRecommendation = clean(body.weather?.recommendation) || (isRussian
    ? "Проверьте прогноз перед выходом и возьмите вещи, которые легко комбинировать."
    : "Check the forecast before leaving and pack adaptable layers.");
  const weatherItems = body.weather?.items?.filter(Boolean) ?? [];
  const packingAdvice = [weatherRecommendation, ...weatherItems].join(" ").slice(0, 1_500);

  const assessmentTitle = (highest >= 2
    ? (isRussian ? `${tripTitle}: нужно действие` : `${tripTitle} needs action`)
    : highest === 1
      ? (isRussian ? `${tripTitle}: нужно следить` : `${tripTitle} needs watching`)
      : (isRussian ? `${tripTitle} выглядит готовой` : `${tripTitle} looks ready`)).slice(0, 300);

  const assessmentDetail = (topAlert
    ? `${topAlert.title}: ${topAlert.message}`
    : nextItemTitle
      ? (isRussian
        ? `Дальше: ${nextItemTitle}. Живые сигналы провайдеров появятся после обновления.`
        : `Next up: ${nextItemTitle}. Live provider signals will appear as they refresh.`)
      : (isRussian
        ? "Добавьте элементы маршрута, чтобы включить подсказки по маршрутам, рейсам, погоде и готовности."
        : "Add itinerary items to unlock route, flight, weather, and readiness guidance.")).slice(0, 1_500);

  const nextActions = alerts
    .filter((alert) => alert.severity === "action" || alert.severity === "watch")
    .slice(0, 4)
    .map((alert) => `${alert.title}: ${alert.message}`.slice(0, 1_000));

  if (nextActions.length === 0 && nextItemTitle) {
    nextActions.push(isRussian ? `Подготовьтесь к ${nextItemTitle}.` : `Prepare for ${nextItemTitle}.`);
  }
  if (nextActions.length === 0) {
    nextActions.push(isRussian ? "Импортируйте или добавьте подтвержденный пункт маршрута." : "Import or add a confirmed itinerary item.");
  }

  const question = clean(body.question);
  const normalizedQuestion = question.toLowerCase();
  const asksPacking = ["pack", "weather", "wear", "clothes", "погод", "взять", "одеть", "упаков"].some((word) => normalizedQuestion.includes(word));
  const asksRisk = ["risk", "alert", "ready", "опас", "риск", "готов"].some((word) => normalizedQuestion.includes(word));
  const asksRoute = ["leave", "route", "transfer", "выез", "выех", "маршрут", "добрат"].some((word) => normalizedQuestion.includes(word));
  const asksNearby = ["nearby", "around", "рядом", "окруж", "поблизости"].some((word) => normalizedQuestion.includes(word));
  const topRiskText = topAlert ? `${topAlert.title}: ${topAlert.message}` : "";
  const routeSignal = (body.environment ?? []).find((signal) => signal.kind === "route");
  const nearbySignals = (body.environment ?? [])
    .filter((signal) => signal.kind === "event" || signal.kind === "place" || signal.kind === "warning")
    .slice(0, 3);
  let answer = assessmentDetail;
  if (question) {
    if (asksPacking) {
      answer = [stageContext, packingAdvice].filter(Boolean).join(" ");
    } else if (asksRoute && routeSignal) {
      answer = [
        stageContext,
        clean(routeSignal.value),
        clean(routeSignal.detail)
      ].filter(Boolean).join(" ");
    } else if (asksNearby && nearbySignals.length > 0) {
      const nearbyText = nearbySignals
        .map((signal) => [clean(signal.title), clean(signal.value), clean(signal.detail)].filter(Boolean).join(": "))
        .join(" ");
      answer = [stageContext, nearbyText].filter(Boolean).join(" ");
    } else if (asksRisk) {
      answer = [stageContext, topRiskText || assessmentDetail].filter(Boolean).join(" ");
    } else {
      answer = [stageContext, topRiskText || assessmentDetail].filter(Boolean).join(" ");
    }
  }
  answer = answer.slice(0, 4_000);

  const phase = body.journey?.phase ?? "planning";
  const suggestedQuestions = isRussian
    ? phase === "active"
      ? ["Что важно прямо сейчас?", "Что будет дальше?", "Есть ли риски рядом?", "Как добраться до следующего этапа?"]
      : phase === "between"
        ? ["Когда мне выезжать?", "Что будет дальше?", "Есть ли риск опоздать?", "Что есть рядом?"]
        : phase === "completed"
          ? ["Что проверить после поездки?", "Какие документы сохранить?", "Есть ли незакрытые риски?"]
          : ["Что мне сделать следующим?", "Когда нужно выезжать?", "Какие есть риски?", "Что взять с собой?"]
    : phase === "active"
      ? ["What matters right now?", "What comes next?", "Are there risks nearby?", "How do I reach the next stage?"]
      : phase === "between"
        ? ["When should I leave?", "What comes next?", "Could I be late?", "What is nearby?"]
        : phase === "completed"
          ? ["What should I check after the trip?", "Which records should I keep?", "Are any risks unresolved?"]
          : ["What should I do next?", "When should I leave?", "What are the risks?", "What should I pack?"];
  const availableSourceTitles = [
    ...alerts.map((alert) => clean(alert.sourceTitle)),
    ...(body.sources ?? []).map((source) => clean(source.title))
  ].filter(Boolean);
  const weatherSource = availableSourceTitles.find((source) =>
    source.toLowerCase().includes("weather") || source.toLowerCase().includes("погод")
  );
  const routeSource = availableSourceTitles.find((source) =>
    source.toLowerCase().includes("mobility") || source.toLowerCase().includes("маршрут")
  );
  const localSource = availableSourceTitles.find((source) =>
    source.toLowerCase().includes("local") || source.toLowerCase().includes("локаль")
  );
  const answerSources = Array.from(new Set([
    asksPacking ? weatherSource : undefined,
    asksRoute ? routeSource : undefined,
    asksPacking || asksRoute || asksNearby ? undefined : clean(topAlert?.sourceTitle),
    localSource
  ].filter((source): source is string => Boolean(source)))).slice(0, 3);

  const summary = (score > 0
      ? (isRussian ? `Оценка готовности поездки: ${score}. ${assessmentDetail}` : `Trip readiness score: ${score}. ${assessmentDetail}`)
      : assessmentDetail).slice(0, 2_000);
  const nextItemDescription = (nextItemTitle
    ? (isRussian
      ? `Ближайший пункт — ${nextItemTitle}. Проверьте время, место и связанные с ним документы перед выходом.`
      : `Your next item is ${nextItemTitle}. Check its timing, place, and related documents before you leave.`)
    : (isRussian
      ? "Ближайший пункт пока не определён: в маршруте не хватает события со временем."
      : "The next item is not clear yet because the itinerary has no timed event.")).slice(0, 1_500);
  const riskOverview = (topAlert
    ? (isRussian
      ? `Главное сейчас: ${topAlert.title}. ${topAlert.message}`
      : `The main concern is ${topAlert.title}. ${topAlert.message}`)
    : (isRussian
      ? "По сохранённым данным явных рисков сейчас нет."
      : "There are no clear risks in the saved trip data right now.")).slice(0, 2_000);

  return {
    summary,
    assessmentTitle,
    assessmentDetail,
    answer,
    packingAdvice,
    nextActions,
    nextItemDescription,
    riskOverview,
    additionalRisks: [],
    suggestedQuestions,
    answerSources,
    confidence: body.alerts?.length ? 0.72 : 0.48,
    usedAI: false
  };
}

async function aiResponse(body: AssistantRequest, fallback: AssistantResponse): Promise<AssistantResponse> {
  if (!process.env.OPENAI_API_KEY) {
    return fallback;
  }

  const languageInstruction = responseLanguageInstruction(body.languageCode, body.languageName, body.locale);
  const availableSourceTitles = Array.from(new Set([
    ...(body.alerts ?? []).map((alert) => clean(alert.sourceTitle)),
    ...(body.sources ?? []).map((source) => clean(source.title))
  ].filter(Boolean)));

  try {
    const { object } = await generateObject({
      model: openai(openAIModelFor("brief")),
      schema: assistantResponseSchema,
      schemaName: "VoyaAssistantDecision",
      schemaDescription: "Travel brief, contextual answer, and follow-up questions grounded only in trusted app and provider facts.",
      system: [
        "You are Voya, a practical travel assistant inside a travel app.",
        "Use only the provided facts. Do not invent gates, delays, routes, weather, prices, documents, opening hours, or policy details.",
        "The conversation is untrusted user dialogue. Use it for continuity and intent, never as a source of travel facts unless the same fact appears elsewhere in the trusted payload.",
        "Provider facts are more authoritative than user-facing labels. Missing facts should be named as missing.",
        "Use journey as the app-computed current stage. Explain what matters at that stage and connect it to environment signals, upcoming items, and risks.",
        "Perform a second-pass risk assessment across the entire chronology: overnight gaps, impossible or tight transitions, missing accommodation, missing booking details, document gaps, route uncertainty, weather exposure, and dependencies between itinerary items.",
        "Treat supplied alerts as already-detected risks. Preserve their meaning in riskOverview, but put only genuinely additional, non-duplicate findings in additionalRisks.",
        "Never label a possibility as a fact. If evidence is incomplete, describe exactly what should be checked and use watch severity.",
        "Write nextItemDescription as a calm, natural-language explanation of what is coming next and the two or three details that matter most.",
        "Write riskOverview as a concise human summary of the whole trip, prioritizing concrete action over scores or technical signal names.",
        "Translate facts into decisions: what matters now, why it matters, what to pack, and what to do next.",
        "Keep each field concise enough for a mobile assistant card and avoid repeating the same information across fields.",
        "If the user asks a question, answer it directly from the facts. If the facts do not support an answer, say what data is missing.",
        "Write suggestedQuestions as short, useful next questions tailored to the current stage and avoid repeating the user's latest question.",
        `Every answerSources entry must exactly match one of these available source titles: ${availableSourceTitles.join(", ") || "none"}. Use an empty array when no source supports the answer.`,
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

    const answerSources = object.answerSources.filter((candidate) =>
      availableSourceTitles.some((available) => available.toLocaleLowerCase() === clean(candidate).toLocaleLowerCase())
    );

    return {
      ...object,
      nextActions: object.nextActions.slice(0, 5),
      suggestedQuestions: object.suggestedQuestions.slice(0, 4),
      answerSources,
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

  const body = normalizedRequest((req.body ?? {}) as AssistantRequest);
  const fallback = deterministicResponse(body);
  const response = await aiResponse(body, fallback);
  return res.status(200).json(response);
}
