import { serve } from "bun";
import { getDb } from "./db.ts";
import { handleHealth } from "./handlers/health.ts";
import { handleRegisterKey } from "./handlers/keys.ts";
import { handleBbox, handleNearby } from "./handlers/stations.ts";
import { handlePrefetchRoute } from "./handlers/prefetch.ts";

// Initialize DB on startup
getDb();

const server = serve({
	port: process.env.PORT ? parseInt(process.env.PORT, 10) : 7878,

	routes: {
		"/health": { GET: handleHealth },
		"/keys/register": { POST: handleRegisterKey },
		"/stations/nearby": { GET: handleNearby },
		"/stations/bbox": { GET: handleBbox },
		"/prefetch/route": { POST: handlePrefetchRoute },
	},

	fetch(req) {
		return new Response("Not found", { status: 404 });
	},
});

console.log(`gastrack listening on ${server.hostname}:${server.port}`);

process.on("SIGINT", () => process.exit(0));
process.on("SIGTERM", () => process.exit(0));

process.on("unhandledRejection", (reason) => {
	console.error("Unhandled rejection:", reason);
});
