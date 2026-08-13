# Vehicle selection + capacity-aware Auto Stop — design

Status: approved
Date: 2026-08-13

## Context

EcoCharge already has a `vehicles` table with full CRUD (add/list/delete, a
free-text "Add vehicle" sheet in Profile, an `is_default` flag) and the
charging-session backend already accepts an optional `vehicleId` end to
end — `POST /api/sessions/start` stores it, and there's a dormant
`checkVehicleConnectorCompatible` check that validates the vehicle's
connector type against the connector being used. None of this is actually
exercised, though: the "Charge now" flow never asks the user which vehicle
they're charging, so `vehicleId` is always `null` in practice, and the
compatibility check is a permanent no-op.

Separately, the battery-autostop feature (already shipped) assumes every
session's battery pack is a flat `BATTERY_CAPACITY_KWH = 40` kWh constant.
This spec closes both gaps together: wiring vehicle selection into the
charging flow, and using the *selected vehicle's actual capacity* for the
battery-percentage math instead of the flat constant.

## Vehicle catalog

Hardcoded client-side, no external API — lives in a new file
`frontend/lib/data/vehicle_catalog.dart` as a `const List` of entries
(make, model, battery capacity in kWh, connector type). Verified against
current India-market specs (a few of the user-supplied figures were
corrected during research — see below).

**Cars** (CCS2):

| Make/Model | Capacity (kWh) |
|---|---|
| Tata Tiago EV | 24 |
| Tata Punch EV | 35 |
| Tata Nexon EV | 40.2 |
| Tata Curvv EV | 55 |
| Mahindra XUV400 | 39.4 |
| Mahindra BE 6 | 79 |
| Mahindra XEV 9e | 79 |
| MG Comet EV | 17.3 |
| MG ZS EV | 50.3 |
| MG Windsor EV | 52.9 |
| Hyundai Kona Electric | 39.2 |
| Hyundai Ioniq 5 | 72.6 |
| Hyundai Creta Electric | 51.4 |
| BYD Atto 3 | 60.5 |
| BYD Seal | 82.5 |
| BYD eMax 7 | 71.8 |
| Citroen eC3 | 29.2 |
| Maruti Suzuki e Vitara | 61 |
| Kia EV6 | 77.4 |
| Kia Syros EV | 51.4 |
| Volvo EX30 | 69 |

**Two-wheelers** (Type2 — see note below):

| Make/Model | Capacity (kWh) |
|---|---|
| Ola S1 Pro | 4 |
| Ather 450X | 3.7 |
| TVS iQube | 3.04 |
| Bajaj Chetak | 3 |

Corrections from the user's original list, confirmed via research: BYD
eMax 7 (55.4 → 71.8 kWh — no 55.4 India variant found), Volvo EX30 (51 →
69 kWh — India sells only the single 69 kWh config), Tata Nexon EV (40.5 →
40.2 kWh — minor rounding). Two-wheeler connector type is modeled as
`Type2` even though real Indian EV scooters mostly use proprietary AC
plugs — accepted as close-enough given the app's `connectors` table only
seeds a handful of types and getting this exactly right isn't load-bearing
for the feature.

Plus an **"Other / not listed"** sentinel (not a real catalog row): selecting
it reveals manual entry fields — make, model, battery capacity (kWh), and a
CCS2/Type2 choice — reusing the Profile screen's existing free-text vehicle
form, extended with a required capacity field.

## Data model changes

- `vehicles.battery_capacity_kwh NUMERIC(6,2) NOT NULL DEFAULT 40` — new
  column. Populated from the catalog entry (or manual entry for "Other")
  whenever a vehicle is saved going forward. Existing rows (added via the
  old free-text flow, dev/test data only) default to 40 — a safe fallback,
  not a real vehicle's capacity.
- `charging_sessions.battery_capacity_kwh NUMERIC(6,2) NOT NULL DEFAULT 40`
  — new column. Snapshotted from the selected vehicle's capacity at
  `POST /start` time (or defaults to 40 if no vehicle is attached),
  mirroring exactly how `start_battery_pct` is already randomly assigned
  once and stored rather than re-derived on every read. A session's
  battery math stays fixed for its whole lifetime even if the underlying
  vehicle record is later edited or deleted.

## Auto Stop calculation change — flagged as requested

`computeBatteryPct(startBatteryPct, energyKwh)` gains a third parameter:
`computeBatteryPct(startBatteryPct, energyKwh, capacityKwh = BATTERY_CAPACITY_KWH)`.
Every call site — `formatSession` (start/stop/history), `GET /active`'s
live battery-pct calc and its auto-stop-trigger energy-to-target
calculation, and `PATCH /auto-stop` — switches from the global constant to
`row.battery_capacity_kwh` (the session's snapshotted value).

This is a real behavior change, not just plumbing: previously every
session assumed a uniform 40 kWh pack. Going forward, a session tied to a
Bajaj Chetak (3 kWh) will show battery percentage climb roughly 13x faster
per kWh delivered than one tied to a BYD Seal (82.5 kWh), and Auto Stop
will trigger — and bill — at a correspondingly different point for each.
Sessions with no vehicle attached keep today's 40 kWh default, so nothing
changes for that case.

## Backend API changes

- `POST /api/vehicles` — gains optional `batteryCapacityKwh` in the
  request body (defaults to 40 if omitted, so the route stays permissive,
  but the new UI always supplies a real value).
- `GET /api/vehicles` — `formatVehicle` gains `batteryCapacityKwh`.
- `POST /api/sessions/start` — when `vehicleId` is provided, looks up that
  vehicle's `battery_capacity_kwh` and stores it on the new session
  column; when omitted, stores the default 40.
- `formatSession` — gains `batteryCapacityKwh` in its output.
- The existing (dormant) `checkVehicleConnectorCompatible` check becomes
  live for the first time: once Charge Now actually sends a `vehicleId`,
  starting a session with a connector-incompatible vehicle now correctly
  returns 409, where previously this was a permanent no-op.

## Frontend changes

**Vehicle catalog & model**
- `frontend/lib/data/vehicle_catalog.dart` — new file, the 25 verified
  entries + the "Other" sentinel.
- `Vehicle` model gains `batteryCapacityKwh: double`.
- `ApiService.addVehicle(...)` gains a `batteryCapacityKwh` param.
  `ApiService.startSession(...)` already accepts `vehicleId` (from earlier
  groundwork) — it just needs to actually be called with a real value now.

**Profile screen** (`profile_screen.dart`)
- "Add vehicle" sheet is restructured: opens a scrollable curated list
  (`GlassPanel`/`ListTile` rows, matching the app's existing visual
  language) showing make/model + capacity + connector type per row. Last
  row is "Other / not listed."
- Picking a catalog entry saves it directly — no further form.
- Picking "Other" reveals the existing free-text form (make/model/
  connector-type chips), now with an added required capacity (kWh) field.
- Saved-vehicle list tiles gain a capacity readout (e.g. "CCS2 • 40.2
  kWh") alongside the existing connector-type display.

**Charge Now flow** (`station_detail_screen.dart`)
- `_startChargingNow` first resolves the user's saved vehicles filtered to
  those compatible with the connector's type.
  - Zero compatible vehicles: show a prompt routing into the Profile
    add-vehicle flow; re-check on return.
  - One or more: the existing Auto Stop bottom sheet gains a "Vehicle"
    section above the slider — pre-selected to the default/only vehicle,
    tappable to change if there's more than one.
- The resolved `vehicleId` is passed through to
  `SessionProvider.startCharging(...)` → `ApiService.startSession(...)`
  (both already accept it — this is the first time it's populated).

**Active session / history screens** — no required changes; the battery
ring already reads `batteryPct`, which now correctly reflects the
session's vehicle-specific capacity server-side.

## Testing

- Backend: extend `batterySimulation.test.js` for `computeBatteryPct`'s
  new third parameter (default behavior + an explicit capacity). Extend
  session-start tests/verification to confirm a vehicle's capacity is
  correctly snapshotted onto the session, and that omitting a vehicle
  still defaults to 40.
- Backend: curl verification — start a session with a low-capacity
  vehicle (e.g. a 3 kWh Bajaj Chetak) and confirm `batteryPct` climbs much
  faster per kWh than a session with no vehicle attached, and that Auto
  Stop fires/bills correctly against that smaller pack.
- Frontend: `flutter analyze` after each change; manual walkthrough —
  add a vehicle via the curated list, add one via "Other," confirm the
  Charge Now sheet filters by connector type, pre-selects sensibly, and
  correctly blocks/excludes incompatible vehicles.
