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
  ownedVehicleAvailable: z.boolean().optional(),
  airportBufferMinutes: z.number().int().min(0).max(240).optional(),
  taxiPickupBufferMinutes: z.number().int().min(0).max(45).optional()
}).refine((request) => !(request.departureTime && request.arrivalTime), {
  message: "Use either departureTime or arrivalTime, not both"
});

type MobilityPlanRequest = z.infer<typeof mobilityPlanSchema>;
type MobilityPlace = MobilityPlanRequest["origin"];
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
  steps?: MobilityRouteStep[];
  tone: RouteTone;
};

export type MobilityRouteStep = {
  kind: "walk" | "transit" | "drive" | "other";
  title: string;
  detail?: string;
  durationMinutes?: number;
  distanceMeters?: number;
  lineName?: string;
  vehicleType?: string;
  departureStop?: string;
  arrivalStop?: string;
  departureTime?: string;
  arrivalTime?: string;
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
  legs?: GoogleRouteLeg[];
};

type GoogleRouteLeg = {
  duration?: string;
  staticDuration?: string;
  steps?: GoogleRouteLegStep[];
};

type GoogleRouteLegStep = {
  staticDuration?: string;
  distanceMeters?: number;
  navigationInstruction?: {
    instructions?: string;
  };
  localizedValues?: {
    distance?: { text?: string };
    staticDuration?: { text?: string };
  };
  transitDetails?: {
    stopDetails?: {
      arrivalStop?: {
        name?: string;
      };
      departureStop?: {
        name?: string;
      };
      arrivalTime?: string;
      departureTime?: string;
    };
    transitLine?: {
      name?: string;
      nameShort?: string;
      vehicle?: {
        name?: { text?: string };
        type?: string;
      };
    };
  };
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

function labelFor(place: MobilityPlace) {
  return place.label ?? place.address ?? `${place.latitude},${place.longitude}`;
}

function routeValueFor(place: MobilityPlace) {
  if (place.latitude != null && place.longitude != null) {
    return `${place.latitude},${place.longitude}`;
  }

  return place.address ?? place.label ?? "";
}

function parseCoordinatePair(latValue: string, lonValue: string) {
  const latitude = Number(latValue);
  const longitude = Number(lonValue);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return undefined;
  }
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return undefined;
  }

  return { latitude, longitude };
}

function coordinatesFromText(value: string) {
  const atMatch = value.match(/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)(?:[,/?]|$)/);
  if (atMatch) {
    return parseCoordinatePair(atMatch[1], atMatch[2]);
  }

  const bangMatch = value.match(/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/);
  if (bangMatch) {
    return parseCoordinatePair(bangMatch[1], bangMatch[2]);
  }

  const plainMatch = value.match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/);
  if (plainMatch) {
    return parseCoordinatePair(plainMatch[1], plainMatch[2]);
  }

  return undefined;
}

function isGoogleMapsHost(hostname: string) {
  return [
    "google.com",
    "www.google.com",
    "maps.google.com",
    "maps.app.goo.gl",
    "goo.gl"
  ].some((host) => hostname === host || hostname.endsWith(`.${host}`));
}

function mapURL(value: string) {
  try {
    const url = new URL(value);
    return isGoogleMapsHost(url.hostname) ? url : undefined;
  } catch {
    return undefined;
  }
}

function coordinatesFromMapURL(url: URL) {
  const directCoordinates = coordinatesFromText(decodeURIComponent(url.href));
  if (directCoordinates) {
    return directCoordinates;
  }

  for (const parameter of ["q", "query", "ll", "center"]) {
    const value = url.searchParams.get(parameter);
    if (!value) {
      continue;
    }

    const coordinates = coordinatesFromText(value);
    if (coordinates) {
      return coordinates;
    }
  }

  return undefined;
}

function placeNameFromMapURL(url: URL) {
  const query = url.searchParams.get("q") ?? url.searchParams.get("query");
  if (query && !coordinatesFromText(query)) {
    return query;
  }

  const placeMatch = decodeURIComponent(url.pathname).match(/\/place\/([^/]+)/);
  if (!placeMatch) {
    return undefined;
  }

  return placeMatch[1].replace(/\+/g, " ").trim();
}

async function resolvedGoogleMapURL(value: string) {
  const url = mapURL(value);
  if (!url) {
    return undefined;
  }

  if (coordinatesFromMapURL(url) || placeNameFromMapURL(url)) {
    return url;
  }

  if (url.hostname !== "maps.app.goo.gl" && url.hostname !== "goo.gl") {
    return url;
  }

  try {
    for (const method of ["HEAD", "GET"] as const) {
      const response = await fetch(url, { method, redirect: "follow" });
      const resolvedURL = mapURL(response.url);
      if (resolvedURL && resolvedURL.href !== url.href) {
        return resolvedURL;
      }
    }
    return url;
  } catch {
    return url;
  }
}

async function normalizedPlace(place: MobilityPlace, role: "origin" | "destination") {
  const address = place.address?.trim();
  if (!address) {
    return { place };
  }

  const url = await resolvedGoogleMapURL(address);
  if (!url) {
    const coordinates = coordinatesFromText(address);
    return coordinates ? { place: { ...place, ...coordinates } } : { place };
  }

  const coordinates = coordinatesFromMapURL(url);
  const placeName = placeNameFromMapURL(url);
  if (coordinates) {
    return {
      place: {
        ...place,
        address: undefined,
        label: place.label ?? placeName ?? "Map point",
        ...coordinates
      }
    };
  }

  if (placeName) {
    return {
      place: {
        ...place,
        address: placeName,
        label: place.label ?? placeName
      }
    };
  }

  return {
    place,
    warning: `Google Maps ${role} link could not be resolved to coordinates or a place name.`
  };
}

async function normalizedMobilityRequest(request: MobilityPlanRequest, warnings: string[]): Promise<MobilityPlanRequest> {
  const [origin, destination] = await Promise.all([
    normalizedPlace(request.origin, "origin"),
    normalizedPlace(request.destination, "destination")
  ]);

  for (const warning of [origin.warning, destination.warning]) {
    if (warning) {
      warnings.push(warning);
    }
  }

  return {
    ...request,
    origin: origin.place,
    destination: destination.place
  };
}

function googleWaypoint(place: MobilityPlace) {
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

function sumDurations(values: Array<string | undefined>) {
  let total = 0;
  let hasValue = false;

  for (const value of values) {
    const seconds = secondsFromDuration(value);
    if (seconds == null) {
      continue;
    }

    total += seconds;
    hasValue = true;
  }

  return hasValue ? total : undefined;
}

function minutesFromDuration(value?: string) {
  const seconds = secondsFromDuration(value);
  return seconds == null ? undefined : Math.max(1, Math.round(seconds / 60));
}

function secondsBetween(start?: string, end?: string) {
  if (!start || !end) {
    return undefined;
  }

  const startDate = new Date(start);
  const endDate = new Date(end);
  if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
    return undefined;
  }

  const seconds = Math.round((endDate.getTime() - startDate.getTime()) / 1000);
  return seconds > 0 ? seconds : undefined;
}

function transitScheduledSpanSeconds(route: GoogleRoute) {
  const times = route.legs
    ?.flatMap((leg) => leg.steps ?? [])
    .flatMap((step) => {
      const stopDetails = step.transitDetails?.stopDetails;
      return [stopDetails?.departureTime, stopDetails?.arrivalTime];
    })
    .filter((value): value is string => Boolean(value))
    .map((value) => new Date(value))
    .filter((value) => !Number.isNaN(value.getTime()));

  if (!times?.length) {
    return undefined;
  }

  const first = new Date(Math.min(...times.map((value) => value.getTime())));
  const last = new Date(Math.max(...times.map((value) => value.getTime())));
  return secondsBetween(first.toISOString(), last.toISOString());
}

function travelSecondsFromRoute(route: GoogleRoute, mode: RouteMode) {
  const candidates = [
    secondsFromDuration(route.duration),
    secondsFromDuration(route.staticDuration),
    sumDurations(route.legs?.map((leg) => leg.duration) ?? []),
    sumDurations(route.legs?.map((leg) => leg.staticDuration) ?? [])
  ];

  if (mode === "transit") {
    candidates.push(
      sumDurations(route.legs?.flatMap((leg) => leg.steps?.map((step) => step.staticDuration) ?? []) ?? []),
      transitScheduledSpanSeconds(route)
    );
  }

  const usableCandidates = candidates.filter((value): value is number => value != null && value > 0);
  return usableCandidates.length ? Math.max(...usableCandidates) : undefined;
}

function addMinutes(date: Date, minutes: number) {
  return new Date(date.getTime() + minutes * 60_000);
}

function subtractMinutes(date: Date, minutes: number) {
  return new Date(date.getTime() - minutes * 60_000);
}

function providerArrivalTimeForRoute(request: MobilityPlanRequest, mode: RouteMode) {
  if (!request.arrivalTime || mode !== "transit") {
    return request.arrivalTime;
  }

  const arrivalTime = new Date(request.arrivalTime);
  if (Number.isNaN(arrivalTime.getTime())) {
    return request.arrivalTime;
  }

  return subtractMinutes(arrivalTime, request.airportBufferMinutes ?? 0).toISOString();
}

function mapsURL(origin: MobilityPlace, destination: MobilityPlace, mode: RouteMode) {
  const url = new URL("https://www.google.com/maps/dir/");
  url.searchParams.set("api", "1");
  url.searchParams.set("origin", routeValueFor(origin));
  url.searchParams.set("destination", routeValueFor(destination));
  url.searchParams.set("travelmode", googleMapsTravelMode(mode));
  return url.toString();
}

function compactParts(parts: Array<string | undefined>) {
  return parts
    .map((part) => part?.trim())
    .filter((part): part is string => Boolean(part));
}

function routeStepsFromRoute(route: GoogleRoute, mode: RouteMode): MobilityRouteStep[] | undefined {
  const steps = route.legs?.flatMap((leg) => leg.steps ?? []) ?? [];
  if (!steps.length) {
    return undefined;
  }

  const routeSteps = steps.map((step): MobilityRouteStep | undefined => {
    const transit = step.transitDetails;
    const stopDetails = transit?.stopDetails;
    const lineName = transit?.transitLine?.nameShort ?? transit?.transitLine?.name;
    const vehicleType = transit?.transitLine?.vehicle?.name?.text ?? transit?.transitLine?.vehicle?.type;
    const departureStop = stopDetails?.departureStop?.name;
    const arrivalStop = stopDetails?.arrivalStop?.name;
    const durationMinutes = minutesFromDuration(step.staticDuration);
    const instruction = step.navigationInstruction?.instructions;
    const distance = step.localizedValues?.distance?.text;

    if (transit) {
      return {
        kind: "transit",
        title: compactParts([vehicleType, lineName]).join(" ") || "Public transport",
        detail: compactParts([
          departureStop && arrivalStop ? `${departureStop} → ${arrivalStop}` : undefined,
          distance
        ]).join(" · ") || undefined,
        durationMinutes,
        distanceMeters: step.distanceMeters,
        lineName,
        vehicleType,
        departureStop,
        arrivalStop,
        departureTime: stopDetails?.departureTime,
        arrivalTime: stopDetails?.arrivalTime
      };
    }

    return {
      kind: mode === "drive" || mode === "taxi" ? "drive" : mode === "walk" ? "walk" : "other",
      title: instruction || routeTitle(mode),
      detail: distance,
      durationMinutes,
      distanceMeters: step.distanceMeters
    };
  }).filter((step): step is MobilityRouteStep => Boolean(step));

  return routeSteps.length ? routeSteps : undefined;
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

  const providerArrivalTime = providerArrivalTimeForRoute(request, mode);
  if (providerArrivalTime && mode === "transit") {
    body.arrivalTime = providerArrivalTime;
  }

  const response = await fetch(googleRoutesEndpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": [
        "routes.duration",
        "routes.staticDuration",
        "routes.distanceMeters",
        "routes.legs.duration",
        "routes.legs.staticDuration",
        "routes.legs.steps.staticDuration",
        "routes.legs.steps.distanceMeters",
        "routes.legs.steps.navigationInstruction.instructions",
        "routes.legs.steps.localizedValues.distance.text",
        "routes.legs.steps.transitDetails.stopDetails.departureTime",
        "routes.legs.steps.transitDetails.stopDetails.arrivalTime",
        "routes.legs.steps.transitDetails.stopDetails.departureStop.name",
        "routes.legs.steps.transitDetails.stopDetails.arrivalStop.name",
        "routes.legs.steps.transitDetails.transitLine.name",
        "routes.legs.steps.transitDetails.transitLine.nameShort",
        "routes.legs.steps.transitDetails.transitLine.vehicle.name.text",
        "routes.legs.steps.transitDetails.transitLine.vehicle.type"
      ].join(",")
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
    return "Own car";
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
  const travelSeconds = travelSecondsFromRoute(route, mode);
  const travelMinutes = travelSeconds ? Math.max(1, Math.round(travelSeconds / 60)) : undefined;
  const bufferMinutes = bufferFor(request, mode);
  const durationMinutes = travelMinutes == null ? undefined : travelMinutes + bufferMinutes;
  const timing = durationMinutes == null ? {} : timingFor(request, durationMinutes);
  const tradeoffs = tradeoffsFor(mode, durationMinutes, bufferMinutes);
  const steps = routeStepsFromRoute(route, mode);
  if (mode === "transit" && (request.arrivalTime || request.departureTime)) {
    tradeoffs.push("Google Maps may recalculate this route for the time selected after opening the map.");
  }

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
    tradeoffs,
    steps,
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
    tradeoffs.push("Shown by default so the traveler can see the public transport route first.");
    tradeoffs.push("Check live schedules, transfers, and platform details in maps before leaving.");
  } else if (mode === "drive") {
    tradeoffs.push("Useful only when a personal or rental car is actually available.");
    tradeoffs.push("Flexible timing, but traffic, parking, and airport drop-off rules can change the real cost.");
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

function score(request: MobilityPlanRequest, option: MobilityRouteOption) {
  if (option.durationMinutes == null) {
    return -1;
  }

  const reliability = { high: 18, medium: 10, low: 3, unknown: 0 }[option.reliability];
  const comfort = { high: 10, medium: 6, low: 2 }[option.comfortLevel];
  const costPenalty = { low: 0, medium: 5, high: 12, unknown: 4 }[option.costLevel];
  const isAirportTransfer = (request.airportBufferMinutes ?? 0) > 0;
  const contextBonus =
    option.mode === "transit" ? 22 :
    option.mode === "taxi" && isAirportTransfer ? 10 :
    option.mode === "drive" && request.ownedVehicleAvailable ? 10 :
    0;
  const unavailableVehiclePenalty = option.mode === "drive" && !request.ownedVehicleAvailable ? 35 : 0;

  return 120 - option.durationMinutes + reliability + comfort + contextBonus - costPenalty - unavailableVehiclePenalty;
}

function recommendationFor(request: MobilityPlanRequest, options: MobilityRouteOption[]): MobilityPlanResponse["recommendation"] {
  const available = options.filter((option) => option.durationMinutes != null);
  const transit = available.find((option) => option.mode === "transit");
  const best = transit ?? available.sort((a, b) => score(request, b) - score(request, a))[0];
  if (!best) {
    return undefined;
  }

  best.tone = "recommended";

  return {
    mode: best.mode,
    title: best.title,
    reason: best.mode === "taxi"
      ? "Consider this when time, luggage, or arrival stress matter more than price."
      : best.mode === "transit"
        ? "Public transport is shown first by default; verify the exact route and schedule in maps."
        : best.mode === "drive"
          ? "Useful when a personal or rental car is available for this transfer."
          : "Useful when travel time and reliability fit this transfer.",
    leaveBy: best.leaveBy
  };
}

export async function buildMobilityPlan(request: MobilityPlanRequest): Promise<MobilityPlanResponse> {
  const modes = request.modes ?? ["transit", "taxi", "drive"];
  const warnings: string[] = [];
  request = await normalizedMobilityRequest(request, warnings);
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
    recommendation: recommendationFor(request, options),
    warnings
  };
}
