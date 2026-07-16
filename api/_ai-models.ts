const DEFAULT_FAST_MODEL = "gpt-5.4-mini";
const DEFAULT_EXTRACTION_MODEL = "gpt-5.5";
const DEFAULT_BRIEF_MODEL = "gpt-5.6-terra";

type AiTask = "extraction" | "jsonRepair" | "location" | "brief";

const taskEnv: Record<AiTask, string> = {
  extraction: "OPENAI_EXTRACT_MODEL",
  jsonRepair: "OPENAI_REPAIR_MODEL",
  location: "OPENAI_LOCATION_MODEL",
  brief: "OPENAI_BRIEF_MODEL"
};

const taskDefaults: Record<AiTask, string> = {
  extraction: DEFAULT_EXTRACTION_MODEL,
  jsonRepair: DEFAULT_FAST_MODEL,
  location: DEFAULT_FAST_MODEL,
  brief: DEFAULT_BRIEF_MODEL
};

export function openAIModelFor(task: AiTask) {
  return process.env[taskEnv[task]] ?? process.env.OPENAI_MODEL ?? taskDefaults[task];
}
