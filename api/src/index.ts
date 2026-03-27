import { serve } from "bun";
import { getDb, getStaleCells, markCellFetched, upsertStations } from "./db.ts";
import { handleEIAAverages, refreshEIAAverages } from "./handlers/eia.ts";
import { handleHealth } from "./handlers/health.ts";
import { handleRegisterKey } from "./handlers/keys.ts";
import { logged } from "./logger.ts";
import { handleBbox, handleNearby, NEARBY_TTL_MS } from "./handlers/stations.ts";
import { handlePrefetchRoute } from "./handlers/prefetch.ts";
import { fetchStationsByLocation } from "./gasbuddy.ts";
import { cellCenter } from "./geo.ts";

// Initialize DB on startup
getDb();

// Kick off EIA refresh in background (won't block startup)
refreshEIAAverages();

// Proactively re-fetch stale cells that were requested in the last 24 hours.
// Runs every 5 minutes; serializes GasBuddy calls with a 500ms delay.
async function proactiveRefresh() {
	const stale = getStaleCells(NEARBY_TTL_MS, 24 * 60 * 60 * 1000);
	if (stale.length === 0) return;
	console.log(`[refresh] ${stale.length} stale cells to refresh`);
	for (const cellKey of stale) {
		const { lat, lng } = cellCenter(cellKey);
		try {
			const stations = await fetchStationsByLocation(lat, lng);
			upsertStations(stations);
		} catch (e) {
			console.error(`[refresh] GasBuddy fetch failed for ${cellKey}:`, e);
		}
		markCellFetched(cellKey); // always update timestamp to enforce backoff
		await new Promise((r) => setTimeout(r, 500));
	}
}

setInterval(proactiveRefresh, 30 * 60 * 1000); // every 30 minutes

const server = serve({
	port: process.env.PORT ? parseInt(process.env.PORT, 10) : 7878,

	routes: {
		"/health": { GET: logged(handleHealth) },
		"/keys/register": { POST: logged(handleRegisterKey) },
		"/stations/nearby": { GET: logged(handleNearby) },
		"/stations/bbox": { GET: logged(handleBbox) },
		"/prefetch/route": { POST: logged(handlePrefetchRoute) },
		"/eia/averages": { GET: logged(handleEIAAverages) },
	},

	fetch(req) {
		const url = new URL(req.url);
		console.log(`${req.method} ${url.pathname} → 404`);
		return new Response("Not found", { status: 404 });
	},
});

console.log(`gastrack listening on ${server.hostname}:${server.port}`);

process.on("SIGINT", () => process.exit(0));
process.on("SIGTERM", () => process.exit(0));

process.on("unhandledRejection", (reason) => {
	console.error("Unhandled rejection:", reason);
});
