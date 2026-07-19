# Voya demo video

Final file: `Voya-OpenAI-Build-Week-Demo-final-v2.mp4`

Duration: 1:48. Language: English. Format: 1920×1080 MP4 (H.264 video, AAC audio) with OpenAI narration.

## Storyboard

- 00:00–00:35 — Inspiration, live text entry, and feeling-first discovery.
- 00:35–01:00 — Live navigation to Smart Import and its input choices.
- 01:00–01:17 — Living itinerary and the next useful action.
- 01:17–01:48 — Trip Guardian, bounded specialist agents, Codex, GPT-5.6, and closing.

The updated narration in `voiceover-v2.txt` explicitly covers what was built and how both Codex and GPT-5.6 were used, as required by OpenAI Build Week.

## Generate natural OpenAI narration

Add `OPENAI_API_KEY=...` to the git-ignored project file `.env.local`, then run:

`node docs/devpost-video/generate_openai_voice.mjs`

This uses `gpt-4o-mini-tts`, the `marin` voice, and product-demo delivery instructions. The key is read locally and is never printed.

## YouTube upload

Title:

`Voya — The Agentic Travel Companion | OpenAI Build Week`

Description:

`Voya turns scattered travel confirmations into a verified, living journey. This demo shows feeling-first Inspiration, smart confirmation import, a unified itinerary, and Trip Guardian — bounded specialist agents that continuously surface the next best action. Built for OpenAI Build Week with Codex and GPT-5.6.`

Set visibility to **Public**, then paste the public YouTube URL into the Devpost video field.
