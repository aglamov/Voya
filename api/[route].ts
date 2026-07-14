import type { VercelRequest, VercelResponse } from "@vercel/node";
import health from "../server/handlers/health.js";
import weatherMonitor from "../server/handlers/weather-monitor.js";
import weatherWatch from "../server/handlers/weather-watch.js";

const handlers: Record<string, (req: VercelRequest, res: VercelResponse) => unknown> = {
  health,
  "weather-monitor": weatherMonitor,
  "weather-watch": weatherWatch
};

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const rawRoute = req.query.route;
  const route = Array.isArray(rawRoute) ? rawRoute[0] : rawRoute;
  const selected = route ? handlers[route] : undefined;
  if (!selected) {
    return res.status(404).json({ error: "Not found" });
  }
  return selected(req, res);
}
