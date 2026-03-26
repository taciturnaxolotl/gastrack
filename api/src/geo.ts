// ~5km grid cell size (in degrees)
const CELL_SIZE = 0.045; // ~5km at US latitudes

export function latLngToCell(lat: number, lng: number): string {
	const latGrid = Math.floor(lat / CELL_SIZE);
	const lngGrid = Math.floor(lng / CELL_SIZE);
	return `${latGrid}:${lngGrid}`;
}

export function cellCenter(cellKey: string): { lat: number; lng: number } {
	const [latGrid, lngGrid] = cellKey.split(":").map(Number);
	return {
		lat: (latGrid! + 0.5) * CELL_SIZE,
		lng: (lngGrid! + 0.5) * CELL_SIZE,
	};
}

// Haversine distance in km
export function distanceKm(
	lat1: number,
	lng1: number,
	lat2: number,
	lng2: number,
): number {
	const R = 6371;
	const dLat = ((lat2 - lat1) * Math.PI) / 180;
	const dLng = ((lng2 - lng1) * Math.PI) / 180;
	const a =
		Math.sin(dLat / 2) ** 2 +
		Math.cos((lat1 * Math.PI) / 180) *
			Math.cos((lat2 * Math.PI) / 180) *
			Math.sin(dLng / 2) ** 2;
	return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Sample points along a polyline at a given interval (km)
export function sampleRoute(
	points: [number, number][],
	intervalKm: number,
): Array<{ lat: number; lng: number }> {
	if (points.length === 0) return [];

	const samples: Array<{ lat: number; lng: number }> = [];
	let accumulated = 0;

	const first = points[0]!;
	samples.push({ lat: first[0], lng: first[1] });

	for (let i = 1; i < points.length; i++) {
		const prev = points[i - 1]!;
		const curr = points[i]!;
		const segLen = distanceKm(prev[0], prev[1], curr[0], curr[1]);
		accumulated += segLen;

		while (accumulated >= intervalKm) {
			accumulated -= intervalKm;
			// Interpolate backwards along segment
			const t = (segLen - accumulated) / segLen;
			samples.push({
				lat: prev[0] + t * (curr[0] - prev[0]),
				lng: prev[1] + t * (curr[1] - prev[1]),
			});
		}
	}

	const last = points[points.length - 1]!;
	const lastSample = samples[samples.length - 1]!;
	if (
		distanceKm(lastSample.lat, lastSample.lng, last[0], last[1]) > 0.1
	) {
		samples.push({ lat: last[0], lng: last[1] });
	}

	return samples;
}

export function totalRouteDistanceKm(points: [number, number][]): number {
	let total = 0;
	for (let i = 1; i < points.length; i++) {
		const prev = points[i - 1]!;
		const curr = points[i]!;
		total += distanceKm(prev[0], prev[1], curr[0], curr[1]);
	}
	return total;
}

export function routeBbox(points: [number, number][]): {
	minLat: number;
	minLng: number;
	maxLat: number;
	maxLng: number;
} {
	let minLat = Infinity,
		minLng = Infinity,
		maxLat = -Infinity,
		maxLng = -Infinity;
	for (const [lat, lng] of points) {
		if (lat < minLat) minLat = lat;
		if (lat > maxLat) maxLat = lat;
		if (lng < minLng) minLng = lng;
		if (lng > maxLng) maxLng = lng;
	}
	return { minLat, minLng, maxLat, maxLng };
}
