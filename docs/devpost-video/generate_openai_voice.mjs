import { readFile, writeFile } from "node:fs/promises";

const envText = await readFile(new URL("../../.env.local", import.meta.url), "utf8");
const keyMatch = envText.match(/^OPENAI_API_KEY\s*=\s*(.+)$/m);
if (!keyMatch || !keyMatch[1].trim()) {
  throw new Error("Add OPENAI_API_KEY to .env.local before generating narration.");
}

const apiKey = keyMatch[1].trim().replace(/^['\"]|['\"]$/g, "");
const input = await readFile(new URL("./voiceover-v2.txt", import.meta.url), "utf8");

const response = await fetch("https://api.openai.com/v1/audio/speech", {
  method: "POST",
  headers: {
    Authorization: `Bearer ${apiKey}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    model: "gpt-4o-mini-tts",
    voice: "marin",
    input,
    instructions: [
      "Speak like a warm, confident product designer presenting a project to judges.",
      "Use natural conversational rhythm, varied sentence length, and subtle pauses.",
      "Avoid an announcer voice, exaggerated enthusiasm, and robotic cadence.",
      "Pronounce Voya as VOY-ah, Codex as CO-dex, and GPT-5.6 as G-P-T five point six.",
    ].join(" "),
    response_format: "wav",
    speed: 1.02,
  }),
});

if (!response.ok) {
  const message = await response.text();
  throw new Error(`OpenAI speech generation failed (${response.status}): ${message}`);
}

const output = new URL("./voiceover-openai.wav", import.meta.url);
await writeFile(output, Buffer.from(await response.arrayBuffer()));
console.log(output.pathname);
