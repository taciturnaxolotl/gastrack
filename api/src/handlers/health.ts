import { json } from "../auth.ts";
import { getCacheStats } from "../db.ts";

export async function handleHealth(_req: Request): Promise<Response> {
	const stats = getCacheStats();
	return json({
		ok: true,
		cached_stations: stats.cachedStations,
		oldest_fetch: stats.oldestFetch
			? new Date(stats.oldestFetch).toISOString()
			: null,
		newest_fetch: stats.newestFetch
			? new Date(stats.newestFetch).toISOString()
			: null,
	});
}
