# gastrack spec

Local gas price cache server with a public API. Sits on terebithia, prefetches
station-level price data along routes for offline iOS use, and exposes a
rate-limited public REST API under Dunkirk Corp.

---

## Data sources

### GasBuddy (primary)

Hits GasBuddy's internal GraphQL API directly. No API key or account required.
Returns station name, coordinates, address, and prices (regular/midgrade/premium/diesel)
with a per-price timestamp indicating when a user last reported it.
Unofficial — could break if GasBuddy changes their internals.

**⚠️ Cloudflare protection:** As of May 2025, GasBuddy added Cloudflare bot
protection. Requests may be intermittently blocked. If blocking becomes
persistent, [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) can
be run as a sidecar on terebithia to bypass it — the Bun client would proxy
requests through `http://localhost:8191/v1` instead of hitting GasBuddy directly.

#### Endpoint

```
POST https://www.gasbuddy.com/graphql
Content-Type: application/json
User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ...
Origin: https://www.gasbuddy.com
Referer: https://www.gasbuddy.com/
```

No auth headers required.

#### Query: `StationsByLocation`

Used by `/stations/nearby` and `/prefetch/route`. Returns up to ~20 stations
near a coordinate pair.

```graphql
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
        nickname       # "Regular" | "Midgrade" | "Premium" | "Diesel"
        formattedPrice # "$3.29" or null if no recent report
        postedTime     # ISO 8601 timestamp of last user report
      }
    }
  }
}
```

Variables: `{ lat: 39.9556, lng: -83.1763, fuel: 1 }`

Fuel type codes: `1` = regular unleaded (used for all fetches — prices for
other grades are returned in the same response via the `prices` array).

#### Query: `GetStation`

Used for single-station lookups by ID (e.g. enriching a specific station).
Returns cash and credit prices separately.

```graphql
query GetStation($id: ID!) {
  station(id: $id) {
    fuels
    prices {
      cash   { postedTime price }
      credit { postedTime price }
    }
  }
}
```

Variables: `{ id: "12345" }` — GasBuddy station ID as a string.

#### Response shape

```json
{
  "data": {
    "stations": {
      "results": [
        {
          "id": "12345",
          "name": "Circle K",
          "latitude": 39.9556,
          "longitude": -83.1763,
          "address": {
            "line1": "123 Main St",
            "city": "Cedarville",
            "state": "OH",
            "zip": "45314"
          },
          "prices": [
            { "nickname": "Regular",  "formattedPrice": "$3.29", "postedTime": "2026-03-26T08:00:00Z" },
            { "nickname": "Midgrade", "formattedPrice": "$3.59", "postedTime": "2026-03-26T07:30:00Z" },
            { "nickname": "Premium",  "formattedPrice": "$3.89", "postedTime": null },
            { "nickname": "Diesel",   "formattedPrice": null,    "postedTime": null }
          ]
        }
      ]
    }
  }
}
```

`formattedPrice` and `postedTime` are `null` when no user has reported that
fuel type recently. Treat null prices as unknown, not zero.

#### Rate limiting / etiquette

GasBuddy does not publish rate limits. Based on community reverse engineering:
- Stay under ~1 request per 5 seconds sustained
- Fetches are serialized in the Bun server with a 500ms delay between calls
- Grid cell deduplication prevents re-fetching the same ~5km area within the TTL
- Never call `StationsByLocation` more than once per grid cell per 30 minutes

### EIA API (baseline)
Free official US government API. Weekly state-level average prices by fuel type.
Used as a sanity check — flag any cached station price that deviates more than
~20% from the current state average as potentially stale. Never used as a
primary price source.

### Google Places (enrichment, optional)
`fuelOptions` field on Place Details. Used selectively to enrich the top N
cheapest stations along a route with hours, ratings, and a second price
data point for cross-validation. Only called for stations the app will
actually surface to the user, not for bulk fetches. Burns into the $200/month
free credit — monitor usage.

---

## Caching

SQLite via Bun's built-in driver. Single `gastrack.db` file next to the process.

### Schema

```sql
CREATE TABLE stations (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  lat         REAL NOT NULL,
  lng         REAL NOT NULL,
  address     TEXT,
  city        TEXT,
  state       TEXT,
  zip         TEXT,
  prices_json TEXT NOT NULL,   -- JSON array of { nickname, formattedPrice, postedTime }
  fetched_at  INTEGER NOT NULL  -- unix ms
);

CREATE INDEX idx_stations_lat_lng ON stations (lat, lng);

CREATE TABLE prefetch_cells (
  cell_key   TEXT PRIMARY KEY,  -- "latGrid:lngGrid" (~5km cells)
  fetched_at INTEGER NOT NULL
);

CREATE TABLE api_keys (
  key        TEXT PRIMARY KEY,  -- "gt_" prefixed random token
  email      TEXT,
  created_at INTEGER,
  last_seen  INTEGER
);

CREATE TABLE rate_limit (
  key    TEXT NOT NULL,
  window INTEGER NOT NULL,  -- floor(unix_ms / 60000), i.e. minute bucket
  count  INTEGER DEFAULT 0,
  PRIMARY KEY (key, window)
);
```

### TTLs

| Context | TTL |
|---|---|
| Live queries (`/stations/nearby`) | 30 minutes |
| Morning prefetch (`/prefetch/route`) | 6 hours |
| Offline reads (`/stations/bbox`) | No expiry — serves stale indefinitely |

Grid cells (~5km squares) are deduplicated so overlapping route samples
don't double-fetch the same area from GasBuddy.

### Price change frequency
Real-world gas prices change 3–4 times per week on average. The main
risk window is late afternoon (~3–7pm local) when wholesale markets close
and stations cascade updates. The 6-hour prefetch TTL covers a full driving
day safely. A soft re-fetch can be triggered by the iOS app if it's opened
after 4pm and cached data is from before noon.

---

## Auth model

Two separate credentials. Neither has elevated data access — the distinction
is purely about which endpoints are accessible.

### Device secret (`GASTRACK_DEVICE_SECRET`)
A single env var. Baked into the iOS app's Keychain at install time.
Only unlocks `POST /keys/register`. Has no access to data endpoints.
Not stored in the database.

### User API keys
Minted via `/keys/register`. Stored in the `api_keys` table.
Required on all data endpoints via `Authorization: Bearer <key>`.
All keys are subject to identical rate limits and size caps — there are
no tiers.

---

## Rate limiting

Sliding window over the `rate_limit` table. Per key, per minute bucket.

**Limit: 60 requests / hour**

Implementation: on each request, increment the current minute bucket and
sum the last 60 buckets. Reject with 429 if the sum exceeds the limit.
Expire old buckets (>2 hours) lazily on write.

---

## Request size caps

Prevent bulk GasBuddy fetches regardless of rate limit status.

### Bbox endpoints (`/stations/nearby`, `/stations/bbox`)
Max area: **0.5 degree²** (~50×50km at US latitudes).
Reject with 400 if `(max_lat - min_lat) * (max_lng - min_lng) > 0.5`.

### Route endpoint (`/prefetch/route`)
Three independent checks, all enforced before any fetching:

| Check | Limit | Rationale |
|---|---|---|
| Raw input points | 500 max | Prevent oversized payloads |
| Total route distance | 200km max | Prevent cross-country routes |
| Generated sample count | 25 max | Direct cap on GasBuddy fetches |

At the default 8km sample interval, a 200km route generates exactly 25
samples — the checks are consistent. The sample count check is the critical
one since a dense squiggly route could pass the distance check but still
generate excessive samples.

---

## Endpoints

All data endpoints require `Authorization: Bearer <key>`.
`/keys/register` requires `Authorization: Bearer <device_secret>`.
`/health` is unauthenticated.

### `GET /health`
Cache stats. Unauthenticated. Used for a debug screen in the iOS app.

```json
{
  "ok": true,
  "cached_stations": 412,
  "oldest_fetch": "2026-03-26T08:00:00.000Z",
  "newest_fetch": "2026-03-26T14:32:11.000Z"
}
```

### `POST /keys/register`
Mint a new API key. Requires device secret.

Request:
```json
{ "email": "user@example.com" }
```

Response:
```json
{ "key": "gt_abc123..." }
```

### `GET /stations/nearby`
Live-first. Fetches from GasBuddy if area isn't cached, otherwise serves cache.
Use for the current-location view.

Params: `lat`, `lng`, `radius_km` (default 8)
Caps: bbox derived from radius must be ≤ 0.5 deg²

### `GET /stations/bbox`
Cache-only. Never triggers a GasBuddy fetch. Serves stale data indefinitely.
Use for offline map rendering — pass the MapKit viewport bounds.

Params: `min_lat`, `min_lng`, `max_lat`, `max_lng`
Caps: area ≤ 0.5 deg²

### `POST /prefetch/route`
The main morning prefetch call. Samples the route polyline, fetches GasBuddy
for uncached cells, returns all stations in the corridor plus the bounding box
to store for offline use.

Request:
```json
{
  "points": [[39.95, -83.17], [40.00, -82.99], ...],
  "interval_km": 8
}
```

Response:
```json
{
  "bbox": { "minLat": 39.9, "minLng": -83.2, "maxLat": 40.2, "maxLng": -82.7 },
  "samples": 5,
  "stations": [...],
  "count": 87,
  "cached_at": 1743000000000
}
```

### Station object
```typescript
{
  id: string
  name: string
  lat: number
  lng: number
  address: string
  city: string
  state: string
  zip: string
  fetchedAt: number  // unix ms
  prices: {
    nickname: string         // "Regular" | "Midgrade" | "Premium" | "Diesel"
    formattedPrice: string | null  // "$3.29" or null if unreported
    postedTime: string | null      // ISO timestamp of last user report
  }[]
}
```

---

## iOS integration

### Auth
Device secret stored in Keychain at install. User key minted on first launch
via `/keys/register`, also stored in Keychain. User key attached to all
subsequent requests as a Bearer token.

### Prefetch flow
Triggered once per day via a background task or Shortcuts/Focus automation:
1. Fetch the day's route from MapKit Directions
2. Extract polyline coordinates
3. `POST /prefetch/route` with the coordinate array
4. Store returned `bbox` in UserDefaults
5. Stations are now cached on the server for offline use

### Offline flow
While driving, pass the current MapKit viewport to `GET /stations/bbox`.
Pure cache read — works with no connectivity to the homelab as long as
the prefetch ran. Falls back gracefully if the server is unreachable
(show last known data with a stale timestamp indicator).

### Price staleness indicator
Show a warning in the UI if `fetchedAt` is older than 6 hours, or if the
station's reported price deviates more than 20% from the EIA state average
for that day.

---

## Deployment (terebithia)

Bun process managed by NixOS systemd via `mkService`. Binds to Tailscale
interface only — not exposed on public interfaces. `gastrack.db` persists
next to the process.

For the public API, put Cloudflare as a reverse proxy in front with the
origin locked to Cloudflare IPs only. The Bun server handles all auth and
rate limiting itself — no Cloudflare-specific features needed.

Environment variables:
```
PORT=7878
GASTRACK_DEVICE_SECRET=<random secret>
EIA_API_KEY=<from api.eia.gov>
GOOGLE_PLACES_KEY=<optional, for enrichment>
FLARESOLVERR_URL=http://localhost:8191  # optional, set if Cloudflare blocking becomes persistent
```