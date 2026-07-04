import { z } from "zod";

const googleRoutesEndpoint = "https://routes.googleapis.com/directions/v2:computeRoutes";

const routeModeSchema = z.enum(["drive", "taxi", "transit", "walk", "bike"]);

const placeSchema = z.object({
  label: z.string().min(1).optional(),
  address: z.string().min(1).optional(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional()
}).refine((place) => Boolean(place.address) || (place.latitude != null && place.longitude != null), {
  message: "Place needs an address or coordinates"
});

export const mobilityPlanSchema = z.object({
  origin: placeSchema,
  destination: placeSchema,
  departureTime: z.string().datetime().optional(),
  arrivalTime: z.string().datetime().optional(),
  locale: z.string().min(2).max(16).optional(),
  modes: z.array(routeModeSchema).min(1).max(5).optional(),
  airportBufferMinutes: z.number().int().min(0).max(240).optional(),
  taxiPickupBufferMinutes: z.number().int().min(0).max(45).optional()
}).refine((request) => !(request.departureTime && request.arrivalTime), {
  message: "Use either departureTime or arrivalTime, not both"
});

type MobilityPlanRequest = z.infer<typeof mobilityPlanSchema>;
type RouteMode = z.infer<typeof routeModeSchema>;

type RouteTone = "recommended" | "good" | "watch" | "unavailable";

export type MobilityRouteOption = {
  mode: RouteMode;
  title: string;
  durationMinutes?: number;
  travelMinutes?: number;
  bufferMinutes: number;
  distanceMeters?: number;
  departureTime?: string;
  arrivalTime?: string;
  leaveBy?: string;
  reliability: "high" | "medium" | "low" | "unknown";
  costLevel: "low" | "medium" | "high" | "unknown";
  comfortLevel: "low" | "medium" | "high";
  emissionsLevel: "low" | "medium" | "high" | "unknown";
  provider: "google_routes" | "voya_estimate";
  providerAttribution?: string;
  mapURL: string;
  summary: string;
  tradeoffs: string[];
  tone: RouteTone;
};

export type MobilityPlanResponse = {
  providerConnected: boolean;
  provider: "google_routes" | "none";
  generatedAt: string;
  originLabel: string;
  destinationLabel: string;
  options: MobilityRouteOption[];
  recommendation?: {
    mode: RouteMode;
    title: string;
    reason: string;
    leaveBy?: string;
  };
  warnings: string[];
};

type GoogleRoute = {
  duration?: string;
  staticDuration?: string;
  distanceMeters?: number;
};

type GoogleRoutesResponse = {
  routes?: GoogleRoute[];
  error?: {
    message?: string;
    status?: string;
  };
};

function mapsApiKey() {
  return process.env.GOOGLE_ROUTES_API_KEY ?? process.env.GOOGLE_MAPS_API_KEY;
}

function labelFor(place: MobilityPlanRequest["origin"]) {
  return place.label ?? place.address ?? `${place.latitude},${place.longitude}`;
}

function googleWaypoint(place: MobilityPlanRequest["origin"]) {
  if (place.latitude != null && place.longitude != null) {
    return {
      location: {
        latLng: {
          latitude: place.latitude,
          longitude: place.longitude
        }
      }
    };
  }

  return { address: place.address ?? place.label };
}

function googleTravelMode(mode: RouteMode) {
  switch (mode) {
  case "drive":
  case "taxi":
    return "DRIVE";
  case "transit":
    return "TRANSIT";
  case "walk":
    return "WALK";
  case "bike":
    return "BICYCLE";
  }
}

function googleMapsTravelMode(mode: RouteMode) {
  switch (mode) {
  case "drive":
  case "taxi":
    return "driving";
  case "transit":
    return "transit";
  case "walk":
    return "walking";
  case "bike":
    return "bicycling";
  }
}

function secondsFromDuration(value?: string) {
  if (!value) {
    return undefined;
  }

  const match = value.match(/^(\d+(?:\.\d+)?)s$/);
  if (!match) {
    return undefined;
  }

  return Math.round(Number(match[1]));
}

function addMinutes(date: Date, minutes: number) {
  return new Date(date.getTime() + minutes * 60_000);
}

function subtractMinutes(date: Date, minutes: number) {
  return new Date(date.getTime() - minutes * 60_000);
}

function mapsURL(origin: MobilityPlanRequest["origin"], destination: MobilityPlanRequest["destination"], mode: RouteMode) {
  const url = new URL("https://www.google.com/maps/dir/");
  url.searchParams.set("api", "1");
  url.searchParams.set("origin", labelFor(origin));
  url.searchParams.set("destination", labelFor(destination));
  url.searchParams.set("travelmode", googleMapsTravelMode(mode));
  return url.toString();
}

async function fetchGoogleRoute(request: MobilityPlanRequest, mode: RouteMode): Promise<GoogleRoute | undefined> {
  const apiKey = mapsApiKey();
  if (!apiKey) {
    return undefined;
  }

  const body: Record<string, unknown> = {
    origin: googleWaypoint(request.origin),
    destination: googleWaypoint(request.destination),
    travelMode: googleTravelMode(mode),
    languageCode: request.locale ?? "en",
    units: "METRIC"
  };

  if (mode === "drive" || mode === "taxi") {
    body.routingPreference = "TRAFFIC_AWARE";
  }

  if (request.departureTime) {
    body.departureTime = request.departureTime;
  }

  if (request.arrivalTime && mode === "transit") {
    body.arrivalTime = request.arrivalTime;
  }

  const response = await fetch(googleRoutesEndpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "routes.duration,routes.staticDuration,routes.distanceMeters"
    },
    body: JSON.stringify(body)
  });

  const payload = await response.json() as GoogleRoutesResponse;
  if (!response.ok) {
    throw new Error(payload.error?.message ?? `Google Routes failed with ${response.status}`);
  }

  return payload.routes?.[0];
}

function routeTitle(mode: RouteMode) {
  switch (mode) {
  case "drive":
    return "Drive";
  case "taxi":
    return "Taxi";
  case "transit":
    return "Public transit";
  case "walk":
    return "Walk";
  case "bike":
    return "Bike";
  }
}

function reliabilityFor(mode: RouteMode, durationMinutes?: number): MobilityRouteOption["reliability"] {
  if (!durationMinutes) {
    return "unknown";
  }

  if (mode === "walk") {
    return "high";
  }

  if (mode === "transit") {
    return durationMinutes > 90 ? "medium" : "high";
  }

  return durationMinutes > 75 ? "medium" : "high";
}

function costLevelFor(mode: RouteMode): MobilityRouteOption["costLevel"] {
  switch (mode) {
  case "walk":
  case "bike":
    return "low";
  case "transit":
    return "low";
  case "drive":
    return "medium";
  case "taxi":
    return "high";
  }
}

function comfortLevelFor(mode: RouteMode): MobilityRouteOption["comfortLevel"] {
  switch (mode) {
  case "taxi":
    return "high";
  case "drive":
    return "medium";
  case "transit":
  case "bike":
    return "medium";
  case "walk":
    return "low";
  }
}

function emissionsLevelFor(mode: RouteMode): MobilityRouteOption["emissionsLevel"] {
  switch (mode) {
  case "walk":
  case "bike":
  case "transit":
    return "low";
  case "drive":
  case "taxi":
    return "high";
  }
}

function bufferFor(request: MobilityPlanRequest, mode: RouteMode) {
  const airportBuffer = request.airportBufferMinutes ?? 0;
  const pickupBuffer = mode === "taxi" ? request.taxiPickupBufferMinutes ?? 10 : 0;
  return airportBuffer + pickupBuffer;
}

function timingFor(request: MobilityPlanRequest, totalMinutes: number) {
  const arrivalTime = request.arrivalTime ? new Date(request.arrivalTime) : undefined;
  const departureTime = request.departureTime ? new Date(request.departureTime) : undefined;

  if (arrivalTime && !Number.isNaN(arrivalTime.getTime())) {
    return {
      leaveBy: subtractMinutes(arrivalTime, totalMinutes).toISOString(),
      arrivalTime: arrivalTime.toISOString()
    };
  }

  if (departureTime && !Number.isNaN(departureTime.getTime())) {
    return {
      departureTime: departureTime.toISOString(),
      arrivalTime: addMinutes(departureTime, totalMinutes).toISOString()
    };
  }

  return {};
}

function optionFromRoute(request: MobilityPlanRequest, mode: RouteMode, route: GoogleRoute): MobilityRouteOption {
  const travelSeconds = secondsFromDuration(route.duration) ?? secondsFromDuration(route.staticDuration);
  const travelMinutes = travelSeconds ? Math.max(1, Math.round(travelSeconds / 60)) : undefined;
  const bufferMinutes = bufferFor(request, mode);
  const durationMinutes = travelMinutes == null ? undefined : travelMinutes + bufferMinutes;
  const timing = durationMinutes == null ? {} : timingFor(request, durationMinutes);

  return {
    mode,
    title: routeTitle(mode),
    durationMinutes,
    travelMinutes,
    bufferMinutes,
    distanceMeters: route.distanceMeters,
    ...timing,
    reliability: reliabilityFor(mode, durationMinutes),
    costLevel: costLevelFor(mode),
    comfortLevel: comfortLevelFor(mode),
    emissionsLevel: emissionsLevelFor(mode),
    provider: "google_routes",
    providerAttribution: "Google Routes",
    mapURL: mapsURL(request.origin, request.destination, mode),
    summary: durationMinutes == null
      ? "Route available in maps, but no duration was returned."
      : `${durationMinutes} min total${bufferMinutes ? ` including ${bufferMinutes} min buffer` : ""}.`,
    tradeoffs: tradeoffsFor(mode, durationMinutes, bufferMinutes),
    tone: "good"
  };
}

function disconnectedOption(request: MobilityPlanRequest, mode: RouteMode): MobilityRouteOption {
  return {
    mode,
    title: routeTitle(mode),
    bufferMinutes: bufferFor(request, mode),
    reliability: "unknown",
    costLevel: costLevelFor(mode),
    comfortLevel: comfortLevelFor(mode),
    emissionsLevel: emissionsLevelFor(mode),
    provider: "voya_estimate",
    mapURL: mapsURL(request.origin, request.destination, mode),
    summary: "Connect a maps provider to show live duration, traffic, and transit timing.",
    tradeoffs: ["Provider key is missing, so Voya can only prepare the map handoff."],
    tone: "unavailable"
  };
}

function tradeoffsFor(mode: RouteMode, durationMinutes?: number, bufferMinutes = 0) {
  const tradeoffs: string[] = [];

  if (mode === "taxi") {
    tradeoffs.push("Highest convenience, but price and pickup time can vary.");
  } else if (mode === "transit") {
    tradeoffs.push("Usually cheaper and lower-emission, but depends on schedules and transfers.");
  } else if (mode === "drive") {
    tradeoffs.push("Flexible timing, but traffic and parking can change the real cost.");
  } else if (mode === "walk") {
    tradeoffs.push("Predictable and free, best only for short distances or light luggage.");
  } else if (mode === "bike") {
    tradeoffs.push("Fast in dense cities, but weather and luggage matter.");
  }

  if (durationMinutes && durationMinutes > 90) {
    tradeoffs.push("Long transfer; consider adding extra recovery time.");
  }

  if (bufferMinutes) {
    tradeoffs.push(`Includes ${bufferMinutes} minutes of Voya buffer.`);
  }

  return tradeoffs;
}

function score(option: MobilityRouteOption) {
  if (option.durationMinutes == null) {
    return -1;
  }

  const reliability = { high: 18, medium: 10, low: 3, unknown: 0 }[option.reliability];
  const comfort = { high: 10, medium: 6, low: 2 }[option.comfortLevel];
  const costPenalty = { low: 0, medium: 5, high: 12, unknown: 4 }[option.costLevel];
  return 120 - option.durationMinutes + reliability + comfort - costPenalty;
}

function recommendationFor(options: MobilityRouteOption[]): MobilityPlanResponse["recommendation"] {
  const available = options.filter((option) => option.durationMinutes != null);
  const best = available.sort((a, b) => score(b) - score(a))[0];
  if (!best) {
    return undefined;
  }

  best.tone = "recommended";

  return {
    mode: best.mode,
    title: best.title,
    reason: best.mode === "taxi"
      ? "Best balance when time, luggage, or arrival stress matter more than price."
      : best.mode === "transit"
        ? "Best balance of duration, cost, and predictability for this transfer."
        : "Best current balance of travel time and reliability.",
    leaveBy: best.leaveBy
  };
}

export async function buildMobilityPlan(request: MobilityPlanRequest): Promise<MobilityPlanResponse> {
  const modes = request.modes ?? ["taxi", "transit", "drive"];
  const warnings: string[] = [];
  const providerConnected = Boolean(mapsApiKey());
  const options: MobilityRouteOption[] = [];

  for (const mode of modes) {
    if (!providerConnected) {
      options.push(disconnectedOption(request, mode));
      continue;
    }

    try {
      const route = await fetchGoogleRoute(request, mode);
      if (route) {
        options.push(optionFromRoute(request, mode, route));
      } else {
        options.push(disconnectedOption(request, mode));
      }
    } catch (error) {
      warnings.push(`${routeTitle(mode)} route unavailable: ${error instanceof Error ? error.message : "provider error"}`);
      options.push(disconnectedOption(request, mode));
    }
  }

  if (!providerConnected) {
    warnings.push("Set GOOGLE_ROUTES_API_KEY or GOOGLE_MAPS_API_KEY on Vercel to enable live route duration and traffic-aware planning.");
  }

  return {
    providerConnected,
    provider: providerConnected ? "google_routes" : "none",
    generatedAt: new Date().toISOString(),
    originLabel: labelFor(request.origin),
    destinationLabel: labelFor(request.destination),
    options,
    recommendation: recommendationFor(options),
    warnings
  };
}
