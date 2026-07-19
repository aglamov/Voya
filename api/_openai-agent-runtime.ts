import { Agent, run, tool } from "@openai/agents";
import { z } from "zod";
import { googleTravelContext } from "./_google-context.js";
import { openAIModelFor } from "./_ai-models.js";
import type { SpecialistResult } from "./specialist-agents.js";

const planDaySchema = z.object({
  day: z.number().int().min(1).max(21),
  title: z.string().min(1).max(160),
  area: z.string().min(1).max(160),
  morning: z.string().max(320),
  afternoon: z.string().max(320),
  evening: z.string().max(320),
  evidence: z.enum(["verified", "suggested", "needs_confirmation"])
});

const planDecisionSchema = z.object({
  title: z.string().min(1).max(180),
  detail: z.string().min(1).max(500),
  required: z.boolean()
});

const sourceCheckSchema = z.object({
  label: z.string().min(1).max(160),
  status: z.enum(["verified", "partial", "missing"]),
  detail: z.string().min(1).max(500)
});

export const tripPlanArtifactSchema = z.object({
  kind: z.literal("trip_plan"),
  title: z.string().min(1).max(240),
  summary: z.string().min(1).max(1_500),
  timingRecommendation: z.string().min(1).max(500),
  days: z.array(planDaySchema).min(1).max(14),
  decisions: z.array(planDecisionSchema).max(8),
  risks: z.array(z.string().min(1).max(500)).max(8),
  sourceChecks: z.array(sourceCheckSchema).max(8),
  nextActions: z.array(z.string().min(1).max(500)).min(1).max(6),
  confidence: z.number().min(0).max(1)
});

export type TripPlanArtifact = z.infer<typeof tripPlanArtifactSchema>;

type PlanningRuntimeContext = {
  trip: Record<string, unknown>;
  locale: string;
  toolsUsed: string[];
};

const readTripParameters = z.object({});
const inspectDestinationParameters = z.object({
  query: z.string().min(2).max(300)
});

const readTripContext = tool<typeof readTripParameters, PlanningRuntimeContext>({
  name: "read_trip_context",
  description: "Read the saved Voya trip draft, its inspiration evidence, dates, notes, and existing itinerary before planning.",
  parameters: readTripParameters,
  async execute(_input, runContext) {
    runContext?.context.toolsUsed.push("read_trip_context");
    return runContext?.context.trip ?? {};
  }
});

const inspectDestination = tool<typeof inspectDestinationParameters, PlanningRuntimeContext>({
  name: "inspect_destination",
  description: "Verify one destination with Google Places and return available air-quality and pollen context. Use it before finalizing a route.",
  parameters: inspectDestinationParameters,
  async execute({ query }, runContext) {
    runContext?.context.toolsUsed.push("inspect_destination");
    const locale = runContext?.context.locale ?? "en";
    return googleTravelContext(query, locale);
  }
});

function isRussian(locale?: string) {
  return locale?.toLowerCase().startsWith("ru") ?? false;
}

function planningInstructions(locale: string) {
  const outputLanguage = isRussian(locale) ? "Russian" : "English";
  return `Role: Voya's trip planning coordinator.

Goal: turn one saved inspiration into a realistic, editable trip draft.

Success criteria:
- call read_trip_context before planning
- call inspect_destination for the primary destination
- preserve the original reason to travel and timing evidence
- produce a day-by-day shape, not bookings or prices
- clearly separate verified facts, suggestions, and details that need confirmation
- name the smallest decisions the traveller must make next

Constraints:
- never claim that tickets, hotels, transport, or reservations were booked
- never invent a confirmed date, opening time, event status, price, or availability
- a tool error or missing result is missing evidence, not a negative fact
- spending, reservations, cancellation, or external communication always requires user approval
- use only the supplied trip context and tool results

Output language: ${outputLanguage}.
Stop after the structured trip plan is complete.`;
}

function deterministicPlan(input: PlanningAgentInput): TripPlanArtifact {
  const russian = isRussian(input.locale);
  const destination = typeof input.context.destination === "string" && input.context.destination.trim()
    ? input.context.destination.trim()
    : russian ? "направление уточняется" : "destination to confirm";
  return {
    kind: "trip_plan",
    title: russian ? `Черновик поездки: ${destination}` : `Trip draft: ${destination}`,
    summary: russian
      ? "Voya сохранила идею и подготовила безопасный черновик. Для полноценного плана нужен серверный OpenAI API key."
      : "Voya saved the idea and prepared a safe draft. A server-side OpenAI API key is required for the full agent plan.",
    timingRecommendation: typeof input.context.dates === "string" && input.context.dates.trim()
      ? input.context.dates
      : russian ? "Выберите даты внутри рекомендованного окна" : "Choose dates inside the recommended window",
    days: [{
      day: 1,
      title: russian ? "Сформировать основу поездки" : "Shape the journey",
      area: destination,
      morning: russian ? "Подтвердить даты и главный повод поездки" : "Confirm the dates and core reason to travel",
      afternoon: russian ? "Проверить логичный порядок районов и переездов" : "Check a sensible order for areas and transfers",
      evening: russian ? "Оставить свободное время вокруг главного события" : "Keep flexible time around the main experience",
      evidence: "needs_confirmation"
    }],
    decisions: [{
      title: russian ? "Подтвердить даты" : "Confirm dates",
      detail: russian ? "Без точных дат нельзя проверить расписания и доступность." : "Exact dates are required before schedules and availability can be checked.",
      required: true
    }],
    risks: [russian ? "Расписания и доступность пока не проверены." : "Schedules and availability have not been checked yet."],
    sourceChecks: [{
      label: russian ? "Исходная идея" : "Inspiration evidence",
      status: "partial",
      detail: russian ? "Сохранена в черновике Trip; агентный run ожидает серверный ключ." : "Saved in the Trip draft; the agent run is waiting for a server key."
    }],
    nextActions: [russian ? "Выберите точные даты поездки." : "Choose exact travel dates."],
    confidence: 0.35
  };
}

export type PlanningAgentInput = {
  mission: string;
  context: Record<string, unknown>;
  locale?: string;
};

export async function runPlanningAgent(input: PlanningAgentInput) {
  const locale = input.locale?.trim() || "en";
  if (!process.env.OPENAI_API_KEY) {
    const artifact = deterministicPlan({ ...input, locale });
    return {
      result: artifactToSpecialistResult(artifact),
      artifact,
      toolsUsed: [] as string[],
      responseId: undefined,
      usedAI: false
    };
  }

  const runtimeContext: PlanningRuntimeContext = {
    trip: input.context,
    locale,
    toolsUsed: []
  };
  const planner = new Agent<PlanningRuntimeContext, typeof tripPlanArtifactSchema>({
    name: "Voya Planning Coordinator",
    instructions: planningInstructions(locale),
    model: openAIModelFor("brief"),
    tools: [readTripContext, inspectDestination],
    outputType: tripPlanArtifactSchema,
    modelSettings: {
      reasoning: { effort: "medium" }
    }
  });
  const agentRun = await run(
    planner,
    `Mission:\n${input.mission}\n\nCreate the strongest useful draft possible without inventing missing facts.`,
    { context: runtimeContext, maxTurns: 6 }
  );
  const artifact = tripPlanArtifactSchema.parse(agentRun.finalOutput);
  return {
    result: artifactToSpecialistResult(artifact),
    artifact,
    toolsUsed: [...new Set(runtimeContext.toolsUsed)],
    responseId: agentRun.lastResponseId,
    usedAI: true
  };
}

function artifactToSpecialistResult(artifact: TripPlanArtifact): SpecialistResult {
  return {
    title: artifact.title,
    summary: artifact.summary,
    observations: [
      artifact.timingRecommendation,
      ...artifact.sourceChecks.map((check) => `${check.label}: ${check.detail}`),
      ...artifact.risks
    ].slice(0, 6),
    nextActions: artifact.nextActions,
    needsApproval: artifact.decisions.some((decision) => decision.required),
    confidence: artifact.confidence
  };
}
