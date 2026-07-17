import type { VercelRequest, VercelResponse } from "@vercel/node";
import { z } from "zod";
import { protectPublicEndpoint } from "./_security.js";

const requestSchema = z.object({
  destination: z.string().trim().min(2).max(160)
});

type PexelsPhoto = {
  id: number;
  width: number;
  height: number;
  url: string;
  photographer: string;
  src: {
    large2x?: string;
    large?: string;
    landscape?: string;
  };
};

type PexelsSearchResponse = {
  photos?: PexelsPhoto[];
};

function photoScore(photo: PexelsPhoto, index: number) {
  const aspectRatio = photo.width / Math.max(photo.height, 1);
  const relevance = Math.max(0, 15 - index) * 30;
  const heroFit = Math.max(0, 100 - Math.abs(aspectRatio - 1.55) * 90);
  const resolution = Math.min(50, (photo.width * photo.height) / 1_000_000 * 5);
  return relevance + heroFit + resolution;
}

function bestPhoto(photos: PexelsPhoto[]) {
  return photos
    .filter((photo) => photo.width > photo.height && Boolean(photo.src.large2x ?? photo.src.large ?? photo.src.landscape))
    .map((photo, index) => ({ photo, score: photoScore(photo, index) }))
    .sort((lhs, rhs) => rhs.score - lhs.score)[0]?.photo;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!await protectPublicEndpoint(req, res, {
    name: "destination-image",
    hourlyIPLimit: 180,
    hourlyInstallLimit: 60,
    maxBodyBytes: 2_000
  })) return;

  const parsedRequest = requestSchema.safeParse(req.body);
  if (!parsedRequest.success) {
    return res.status(400).json({ error: "Invalid destination" });
  }

  const apiKey = process.env.PEXELS_API_KEY?.trim();
  if (!apiKey) {
    return res.status(503).json({ error: "Pexels is not configured" });
  }

  const searchURL = new URL("https://api.pexels.com/v1/search");
  searchURL.searchParams.set("query", parsedRequest.data.destination);
  searchURL.searchParams.set("orientation", "landscape");
  searchURL.searchParams.set("size", "large");
  searchURL.searchParams.set("per_page", "15");

  try {
    const response = await fetch(searchURL, {
      headers: { Authorization: apiKey },
      signal: AbortSignal.timeout(7_000)
    });
    if (!response.ok) {
      console.error("Pexels search failed", response.status);
      return res.status(502).json({ error: "Image provider request failed" });
    }

    const payload = await response.json() as PexelsSearchResponse;
    const photo = bestPhoto(payload.photos ?? []);
    const imageURL = photo?.src.large2x ?? photo?.src.large ?? photo?.src.landscape;
    if (!photo || !imageURL) {
      return res.status(404).json({ error: "No destination image found" });
    }

    return res.status(200).json({
      imageURL,
      credit: `Photo by ${photo.photographer} on Pexels`,
      creditURL: photo.url,
      source: "pexels"
    });
  } catch (error) {
    console.error("Destination image lookup failed", error);
    return res.status(502).json({ error: "Image provider request failed" });
  }
}
