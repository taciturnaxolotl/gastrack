import { err, json, requireApiKey } from "../auth.ts";
import { isCellFresh, markCellFetched, queryStationsInBbox, upsertStations } from "../db.ts";
import { fetchStationsByLocation } from "../gasbuddy.ts";
import {
	latLngToCell,
	routeBbox,
	sampleRoute,
	totalRouteDistanceKm,
} from "../geo.ts";

const PREFETCH_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours
const MAX_POINTS = 500;
const MAX_DISTANCE_KM = 200;
const MAX_SAMPLES = 25;
const DEFAULT_INTERVAL_KM = 8;

export async function handlePrefetchRoute(req: Request): Promise<Response> {
	const authErr = requireApiKey(req);
	if (authErr) return authErr;

	let body: { points?: unknown; interval_km?: unknown };
	try {
		body = (await req.json()) as typeof body;
	} catch {
		return err("Invalid JSON body", 400);
	}

	if (!Array.isArray(body.points)) {
		return err("points must be an array", 400);
	}

	const points = body.points as unknown[];
	if (points.length > MAX_POINTS) {
		return err(`Too many input points (max ${MAX_POINTS})`, 400);
	}

	// Validate each point is [number, number]
	const validated: [number, number][] = [];
	for (const p of points) {
		if (
			!Array.isArray(p) ||
			p.length < 2 ||
			typeof p[0] !== "number" ||
			typeof p[1] !== "number"
		) {
			return err("Each point must be [lat, lng] numbers", 400);
		}
		validated.push([p[0], p[1]]);
	}

	if (validated.length < 2) {
		return err("At least 2 points required", 400);
	}

	const totalDistKm = totalRouteDistanceKm(validated);
	if (totalDistKm > MAX_DISTANCE_KM) {
		return err(`Route too long: ${totalDistKm.toFixed(1)}km (max ${MAX_DISTANCE_KM}km)`, 400);
	}

	const intervalKm =
		typeof body.interval_km === "number" && body.interval_km > 0
			? body.interval_km
			: DEFAULT_INTERVAL_KM;

	const samples = sampleRoute(validated, intervalKm);
	if (samples.length > MAX_SAMPLES) {
		return err(
			`Route generates too many samples: ${samples.length} (max ${MAX_SAMPLES}). Increase interval_km.`,
			400,
		);
	}

	// Fetch uncached cells
	const seenCells = new Set<string>();
	let fetchCount = 0;

	for (const sample of samples) {
		const cellKey = latLngToCell(sample.lat, sample.lng);
		if (seenCells.has(cellKey)) continue;
		seenCells.add(cellKey);

		if (isCellFresh(cellKey, PREFETCH_TTL_MS)) continue;

		try {
			const stations = await fetchStationsByLocation(sample.lat, sample.lng);
			upsertStations(stations);
			markCellFetched(cellKey);
			fetchCount++;
		} catch (e) {
			console.error(`GasBuddy fetch failed for cell ${cellKey}:`, e);
		}
	}

	const bbox = routeBbox(validated);

	// Expand bbox slightly to cover station corridor
	const pad = 0.1;
	const expandedBbox = {
		minLat: bbox.minLat - pad,
		minLng: bbox.minLng - pad,
		maxLat: bbox.maxLat + pad,
		maxLng: bbox.maxLng + pad,
	};

	const stations = queryStationsInBbox(
		expandedBbox.minLat,
		expandedBbox.minLng,
		expandedBbox.maxLat,
		expandedBbox.maxLng,
	);

	return json({
		bbox: expandedBbox,
		samples: fetchCount,
		stations,
		count: stations.length,
		cached_at: Date.now(),
	});
}
