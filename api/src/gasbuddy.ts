import type { Price, Station } from "./db.ts";

const GASBUDDY_URL = "https://www.gasbuddy.com/graphql";

const STATIONS_BY_LOCATION_QUERY = `
query StationsByLocation($lat: Float!, $lng: Float!, $fuel: Int) {
  stations: stationsByLocation(lat: $lat, lng: $lng, fuel: $fuel) {
    results {
      id
      name
      latitude
      longitude
      address {
        line1
        city
        state
        zip
      }
      prices(fuel: $fuel) {
        nickname
        formattedPrice
        postedTime
      }
    }
  }
}
`;

interface GasBuddyStationResult {
	id: string;
	name: string;
	latitude: number;
	longitude: number;
	address: {
		line1: string | null;
		city: string | null;
		state: string | null;
		zip: string | null;
	};
	prices: Array<{
		nickname: string;
		formattedPrice: string | null;
		postedTime: string | null;
	}>;
}

interface GasBuddyResponse {
	data: {
		stations: {
			results: GasBuddyStationResult[];
		};
	};
	errors?: Array<{ message: string }>;
}

const HEADERS = {
	"Content-Type": "application/json",
	"User-Agent":
		"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
	Origin: "https://www.gasbuddy.com",
	Referer: "https://www.gasbuddy.com/",
};

// Serialize GasBuddy fetches with a 500ms delay between calls
let lastFetchTime = 0;

async function throttledFetch(body: string): Promise<Response> {
	const now = Date.now();
	const elapsed = now - lastFetchTime;
	if (elapsed < 500) {
		await Bun.sleep(500 - elapsed);
	}
	lastFetchTime = Date.now();
	return fetch(GASBUDDY_URL, { method: "POST", headers: HEADERS, body });
}

export async function fetchStationsByLocation(
	lat: number,
	lng: number,
): Promise<Station[]> {
	const body = JSON.stringify({
		query: STATIONS_BY_LOCATION_QUERY,
		variables: { lat, lng, fuel: 1 },
	});

	const res = await throttledFetch(body);

	if (!res.ok) {
		throw new Error(`GasBuddy returned ${res.status}: ${await res.text()}`);
	}

	const json = (await res.json()) as GasBuddyResponse;

	if (json.errors?.length) {
		throw new Error(
			`GasBuddy GraphQL errors: ${json.errors.map((e) => e.message).join(", ")}`,
		);
	}

	const now = Date.now();
	return json.data.stations.results.map((r) => ({
		id: r.id,
		name: r.name,
		lat: r.latitude,
		lng: r.longitude,
		address: r.address.line1 ?? null,
		city: r.address.city ?? null,
		state: r.address.state ?? null,
		zip: r.address.zip ?? null,
		prices: r.prices as Price[],
		fetchedAt: now,
	}));
}
