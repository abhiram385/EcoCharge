# Vehicle Selection + Capacity-Aware Auto Stop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire vehicle selection into the "Charge now" flow via a hardcoded 25-vehicle catalog, and switch the battery-percentage math from a flat 40kWh assumption to each session's actual selected-vehicle capacity — plus three small pre-existing bugs found during device testing (button overflow, History tab staleness, wallet top-up silently faking success on failure).

**Architecture:** The `vehicles` table and `POST /api/sessions/start`'s `vehicleId` parameter already exist and already wire end-to-end (including a dormant connector-compatibility check) — nothing in this app currently ever populates `vehicleId` from the UI. This plan adds a `battery_capacity_kwh` column to both `vehicles` and `charging_sessions` (the latter snapshotted once at session start, mirroring the existing `start_battery_pct` pattern — never re-derived on read), threads that value through every battery-percentage calculation in place of the `BATTERY_CAPACITY_KWH` constant, and builds the missing UI: a curated vehicle picker (Profile screen) and a vehicle-selection step folded into the existing Auto Stop bottom sheet (Charge Now flow).

**Tech Stack:** Node/Express/pg (backend), Flutter/Dart with `provider` (frontend), Jest (backend unit tests).

## Global Constraints

- Vehicle catalog is hardcoded client-side only, no external API — 25 entries (21 cars, 4 two-wheelers), exact make/model/capacity/connector-type list in `docs/superpowers/specs/2026-08-13-vehicle-selection-design.md`.
- `battery_capacity_kwh` defaults to `BATTERY_CAPACITY_KWH` (40, from `backend/utils/batterySimulation.js`) on both the `vehicles` and `charging_sessions` columns — this preserves current behavior for any session with no vehicle attached, and for legacy vehicle rows added via the old free-text flow.
- `computeBatteryPct`'s new third parameter (`capacityKwh`) defaults to `BATTERY_CAPACITY_KWH`, so any caller that doesn't pass it keeps today's behavior — all real call sites are updated in Task 4 to pass the session's actual stored capacity.
- Two-wheeler connector type is modeled as `Type2` in the catalog (not fully accurate to real-world proprietary EV-scooter plugs, but accepted — the app's `connectors` table doesn't model that distinction and it isn't load-bearing for this feature).
- The "Other / not listed" manual-entry vehicle form collects exactly: make, model, battery capacity (kWh), and a CCS2/Type2 connector-type choice. No registration-number field (intentionally dropped from the old free-text flow's field set — not part of this feature's requirements).
- Spec: `docs/superpowers/specs/2026-08-13-vehicle-selection-design.md`

---

### Task 1: Database schema — vehicle & session capacity columns

**Files:**
- Modify: `backend/db/schema.sql`

**Interfaces:**
- Produces: `vehicles.battery_capacity_kwh` (NUMERIC(6,2) NOT NULL DEFAULT 40), `charging_sessions.battery_capacity_kwh` (NUMERIC(6,2) NOT NULL DEFAULT 40) — consumed by all later backend tasks.

- [ ] **Step 1: Add `battery_capacity_kwh` to the `vehicles` table**

In `backend/db/schema.sql`, find:

```sql
-- User's saved vehicles
CREATE TABLE IF NOT EXISTS vehicles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    make VARCHAR(60) NOT NULL,
    model VARCHAR(60) NOT NULL,
    connector_type VARCHAR(30) NOT NULL, -- CCS2, CHAdeMO, Type2, GBT
    reg_number VARCHAR(20),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Replace with:

```sql
-- User's saved vehicles
CREATE TABLE IF NOT EXISTS vehicles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    make VARCHAR(60) NOT NULL,
    model VARCHAR(60) NOT NULL,
    connector_type VARCHAR(30) NOT NULL, -- CCS2, CHAdeMO, Type2, GBT
    reg_number VARCHAR(20),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    battery_capacity_kwh NUMERIC(6,2) NOT NULL DEFAULT 40,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS battery_capacity_kwh NUMERIC(6,2) NOT NULL DEFAULT 40;
```

- [ ] **Step 2: Add `battery_capacity_kwh` to the `charging_sessions` table**

Find:

```sql
    start_battery_pct SMALLINT NOT NULL DEFAULT 20,
    auto_stop_pct SMALLINT
);

-- Idempotent for databases that already had charging_sessions before this
-- column existed (ADD COLUMN IF NOT EXISTS is a safe no-op on fresh installs
-- where CREATE TABLE just created them).
ALTER TABLE charging_sessions ADD COLUMN IF NOT EXISTS start_battery_pct SMALLINT NOT NULL DEFAULT 20;
ALTER TABLE charging_sessions ADD COLUMN IF NOT EXISTS auto_stop_pct SMALLINT;
```

Replace with:

```sql
    start_battery_pct SMALLINT NOT NULL DEFAULT 20,
    auto_stop_pct SMALLINT,
    battery_capacity_kwh NUMERIC(6,2) NOT NULL DEFAULT 40
);

-- Idempotent for databases that already had charging_sessions before these
-- columns existed (ADD COLUMN IF NOT EXISTS is a safe no-op on fresh installs
-- where CREATE TABLE just created them).
ALTER TABLE charging_sessions ADD COLUMN IF NOT EXISTS start_battery_pct SMALLINT NOT NULL DEFAULT 20;
ALTER TABLE charging_sessions ADD COLUMN IF NOT EXISTS auto_stop_pct SMALLINT;
ALTER TABLE charging_sessions ADD COLUMN IF NOT EXISTS battery_capacity_kwh NUMERIC(6,2) NOT NULL DEFAULT 40;
```

- [ ] **Step 3: Apply the schema change to the existing database — WITHOUT re-running the seed**

Run (from `backend/`):
```bash
node -e "require('dotenv').config(); const { pool } = require('./db/pool'); const fs = require('fs'); pool.query(fs.readFileSync('./db/schema.sql', 'utf8')).then(() => { console.log('schema applied'); return pool.end(); }).catch((e) => { console.error(e); process.exit(1); });"
```

Expected output: `schema applied`

- [ ] **Step 4: Verify the columns exist**

Run (from `backend/`):
```bash
node -e "require('dotenv').config(); const { pool } = require('./db/pool'); pool.query(\"SELECT table_name, column_name FROM information_schema.columns WHERE table_name IN ('vehicles','charging_sessions') AND column_name = 'battery_capacity_kwh'\").then(r => { console.log(r.rows); return pool.end(); });"
```

Expected output: two rows, one for `vehicles` and one for `charging_sessions`.

- [ ] **Step 5: Commit**

```bash
git add backend/db/schema.sql
git commit -m "Add battery_capacity_kwh to vehicles and charging_sessions schema"
```

---

### Task 2: `computeBatteryPct` capacity parameter + tests

**Files:**
- Modify: `backend/utils/batterySimulation.js`
- Modify: `backend/utils/batterySimulation.test.js`

**Interfaces:**
- Produces: `computeBatteryPct(startBatteryPct: number, energyKwh: number, capacityKwh?: number = BATTERY_CAPACITY_KWH): number` — consumed by Task 4 (backend routes).

- [ ] **Step 1: Write the failing tests**

In `backend/utils/batterySimulation.test.js`, find:

```js
describe('computeBatteryPct', () => {
  it('adds energy delivered as a percentage of capacity to the starting level', () => {
    // 20 kWh into a 40kWh battery = +50 percentage points
    expect(computeBatteryPct(20, 20)).toBe(70);
  });

  it('caps at 100 even if energy exceeds capacity', () => {
    expect(computeBatteryPct(50, 100)).toBe(100);
  });

  it('handles zero energy delivered', () => {
    expect(computeBatteryPct(35, 0)).toBe(35);
  });
});
```

Replace with:

```js
describe('computeBatteryPct', () => {
  it('adds energy delivered as a percentage of capacity to the starting level', () => {
    // 20 kWh into a 40kWh battery = +50 percentage points
    expect(computeBatteryPct(20, 20)).toBe(70);
  });

  it('caps at 100 even if energy exceeds capacity', () => {
    expect(computeBatteryPct(50, 100)).toBe(100);
  });

  it('handles zero energy delivered', () => {
    expect(computeBatteryPct(35, 0)).toBe(35);
  });

  it('uses a custom capacity when provided', () => {
    // 2 kWh into a 4kWh battery = +50 percentage points
    expect(computeBatteryPct(20, 2, 4)).toBe(70);
  });

  it('defaults to the global BATTERY_CAPACITY_KWH when no capacity is given', () => {
    expect(computeBatteryPct(20, 20)).toBe(computeBatteryPct(20, 20, 40));
  });

  it('caps at 100 with a custom capacity too', () => {
    expect(computeBatteryPct(50, 10, 4)).toBe(100);
  });
});
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run (from `backend/`): `npx jest utils/batterySimulation.test.js`
Expected: FAIL on the three new tests (the custom-capacity argument is currently ignored, so `computeBatteryPct(20, 2, 4)` returns `25`, not `70`).

- [ ] **Step 3: Update the implementation**

In `backend/utils/batterySimulation.js`, find:

```js
function computeBatteryPct(startBatteryPct, energyKwh) {
  const pct = Number(startBatteryPct) + (Number(energyKwh) / BATTERY_CAPACITY_KWH) * 100;
  return Math.min(100, pct);
}
```

Replace with:

```js
function computeBatteryPct(startBatteryPct, energyKwh, capacityKwh = BATTERY_CAPACITY_KWH) {
  const pct = Number(startBatteryPct) + (Number(energyKwh) / Number(capacityKwh)) * 100;
  return Math.min(100, pct);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run (from `backend/`): `npx jest utils/batterySimulation.test.js`
Expected: PASS (9 tests: the 6 pre-existing plus the 3 new ones).

- [ ] **Step 5: Commit**

```bash
git add backend/utils/batterySimulation.js backend/utils/batterySimulation.test.js
git commit -m "Add optional capacity parameter to computeBatteryPct"
```

---

### Task 3: Backend vehicles route — accept and return `batteryCapacityKwh`

**Files:**
- Modify: `backend/routes/vehicles.js`

**Interfaces:**
- Consumes: `BATTERY_CAPACITY_KWH` from `../utils/batterySimulation` (Task 2's file, constant already existed)
- Produces: `POST /api/vehicles` accepts optional `batteryCapacityKwh` in the body (validated, defaults to 40); `formatVehicle(row)` now includes `batteryCapacityKwh` — consumed by Task 6 (frontend `Vehicle` model) and Task 4 (sessions route capacity lookup reads the raw column, not this formatter).

- [ ] **Step 1: Import `BATTERY_CAPACITY_KWH`**

In `backend/routes/vehicles.js`, find:

```js
const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');
```

Replace with:

```js
const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');
const { BATTERY_CAPACITY_KWH } = require('../utils/batterySimulation');
```

- [ ] **Step 2: Validate and store `batteryCapacityKwh` on create**

Find:

```js
// POST /api/vehicles { make, model, connectorType, regNumber, isDefault }
router.post('/', asyncHandler(async (req, res) => {
  const { make, model, connectorType, regNumber, isDefault } = req.body;

  if (!make || !model || !connectorType) {
    return res.status(400).json({ error: 'make, model, and connectorType are required' });
  }

  if (isDefault) {
    await pool.query('UPDATE vehicles SET is_default = FALSE WHERE user_id = $1', [req.user.id]);
  }

  const { rows } = await pool.query(
    `INSERT INTO vehicles (user_id, make, model, connector_type, reg_number, is_default)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
    [req.user.id, make, model, connectorType, regNumber || null, !!isDefault]
  );

  res.status(201).json({ vehicle: formatVehicle(rows[0]) });
}));
```

Replace with:

```js
// POST /api/vehicles { make, model, connectorType, regNumber, isDefault, batteryCapacityKwh }
router.post('/', asyncHandler(async (req, res) => {
  const { make, model, connectorType, regNumber, isDefault, batteryCapacityKwh } = req.body;

  if (!make || !model || !connectorType) {
    return res.status(400).json({ error: 'make, model, and connectorType are required' });
  }

  let normalizedCapacity = BATTERY_CAPACITY_KWH;
  if (batteryCapacityKwh !== undefined && batteryCapacityKwh !== null) {
    normalizedCapacity = Number(batteryCapacityKwh);
    if (!Number.isFinite(normalizedCapacity) || normalizedCapacity <= 0) {
      return res.status(400).json({ error: 'batteryCapacityKwh must be a positive number' });
    }
  }

  if (isDefault) {
    await pool.query('UPDATE vehicles SET is_default = FALSE WHERE user_id = $1', [req.user.id]);
  }

  const { rows } = await pool.query(
    `INSERT INTO vehicles (user_id, make, model, connector_type, reg_number, is_default, battery_capacity_kwh)
     VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
    [req.user.id, make, model, connectorType, regNumber || null, !!isDefault, normalizedCapacity]
  );

  res.status(201).json({ vehicle: formatVehicle(rows[0]) });
}));
```

- [ ] **Step 3: Include `batteryCapacityKwh` in `formatVehicle`**

Find:

```js
function formatVehicle(row) {
  return {
    id: row.id,
    make: row.make,
    model: row.model,
    connectorType: row.connector_type,
    regNumber: row.reg_number,
    isDefault: row.is_default,
  };
}
```

Replace with:

```js
function formatVehicle(row) {
  return {
    id: row.id,
    make: row.make,
    model: row.model,
    connectorType: row.connector_type,
    regNumber: row.reg_number,
    isDefault: row.is_default,
    batteryCapacityKwh: Number(row.battery_capacity_kwh),
  };
}
```

- [ ] **Step 4: Verify with the running backend**

Start the backend (from `backend/`): `node server.js`. Get a valid JWT via the OTP flow (`POST /api/auth/request-otp` then `/verify-otp`), then:

```bash
TOKEN="<paste a valid JWT here>"
curl -s -X POST http://localhost:4000/api/vehicles \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"make":"Bajaj","model":"Chetak","connectorType":"Type2","batteryCapacityKwh":3}'
```

Expected: `201` with `vehicle.batteryCapacityKwh: 3`.

Then verify the default and the validation:
```bash
curl -s -X POST http://localhost:4000/api/vehicles \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"make":"Test","model":"NoCapacity","connectorType":"CCS2"}'
```
Expected: `201` with `vehicle.batteryCapacityKwh: 40`.

```bash
curl -s -X POST http://localhost:4000/api/vehicles \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"make":"Test","model":"BadCapacity","connectorType":"CCS2","batteryCapacityKwh":-5}'
```
Expected: `400` with `"batteryCapacityKwh must be a positive number"`.

```bash
curl -s http://localhost:4000/api/vehicles -H "Authorization: Bearer $TOKEN"
```
Expected: every vehicle in the list includes a numeric `batteryCapacityKwh`.

- [ ] **Step 5: Commit**

```bash
git add backend/routes/vehicles.js
git commit -m "Accept and return batteryCapacityKwh on vehicles"
```

---

### Task 4: Backend sessions route — snapshot vehicle capacity, use it everywhere

**Files:**
- Modify: `backend/routes/sessions.js`

**Interfaces:**
- Consumes: `computeBatteryPct` (3-arg form, Task 2), `BATTERY_CAPACITY_KWH` (already imported in this file)
- Produces: every session response (`formatSession`, `GET /active`, `PATCH /auto-stop`) now includes `batteryCapacityKwh`, and `batteryPct` is computed against the session's actual stored capacity — consumed by frontend Task 9 (Charge Now flow) indirectly (no new Dart fields required per the spec, but the numbers now reflect real vehicle capacity).

- [ ] **Step 1: Resolve and store the session's capacity at start**

In `backend/routes/sessions.js`, find:

```js
  const compat = await checkVehicleConnectorCompatible(pool, {
    vehicleId: vehicleId || null,
    userId: req.user.id,
    connectorType: connector.rows[0].connector_type,
  });
  if (!compat.ok) {
    return res.status(compat.error === 'Vehicle not found' ? 404 : 409).json({ error: compat.error });
  }

  const existingActive = await pool.query(
```

Replace with:

```js
  const compat = await checkVehicleConnectorCompatible(pool, {
    vehicleId: vehicleId || null,
    userId: req.user.id,
    connectorType: connector.rows[0].connector_type,
  });
  if (!compat.ok) {
    return res.status(compat.error === 'Vehicle not found' ? 404 : 409).json({ error: compat.error });
  }

  // Snapshot the vehicle's actual battery capacity onto the session at
  // start time, mirroring how start_battery_pct is randomly assigned once
  // and stored rather than re-derived on every read — a session's battery
  // math stays fixed for its whole lifetime even if the vehicle record is
  // later edited or deleted. Sessions with no vehicle attached keep the
  // flat BATTERY_CAPACITY_KWH default.
  let sessionCapacityKwh = BATTERY_CAPACITY_KWH;
  if (vehicleId) {
    // The compat check above already confirmed this vehicle exists and
    // belongs to this user, so a row is guaranteed here.
    const vehicleRow = await pool.query('SELECT battery_capacity_kwh FROM vehicles WHERE id = $1 AND user_id = $2', [
      vehicleId,
      req.user.id,
    ]);
    sessionCapacityKwh = Number(vehicleRow.rows[0].battery_capacity_kwh);
  }

  const existingActive = await pool.query(
```

- [ ] **Step 2: Include `battery_capacity_kwh` in the session INSERT**

Find:

```js
    const session = await client.query(
      `INSERT INTO charging_sessions
         (user_id, booking_id, station_id, connector_id, vehicle_id, status, start_battery_pct, auto_stop_pct)
       VALUES ($1, $2, $3, $4, $5, 'active', $6, $7) RETURNING *`,
      [req.user.id, bookingId || null, stationId, connectorId, vehicleId || null, randomStartBatteryPct(), normalizedAutoStopPct]
    );
```

Replace with:

```js
    const session = await client.query(
      `INSERT INTO charging_sessions
         (user_id, booking_id, station_id, connector_id, vehicle_id, status, start_battery_pct, auto_stop_pct, battery_capacity_kwh)
       VALUES ($1, $2, $3, $4, $5, 'active', $6, $7, $8) RETURNING *`,
      [
        req.user.id,
        bookingId || null,
        stationId,
        connectorId,
        vehicleId || null,
        randomStartBatteryPct(),
        normalizedAutoStopPct,
        sessionCapacityKwh,
      ]
    );
```

- [ ] **Step 3: Use the session's capacity in `formatSession`**

Find:

```js
function formatSession(row, connector) {
  return {
    id: row.id,
    stationId: row.station_id,
    stationName: row.station_name,
    connectorId: row.connector_id,
    status: row.status,
    startedAt: row.started_at,
    stoppedAt: row.stopped_at,
    energyKwh: Number(row.energy_kwh),
    cost: Number(row.cost),
    powerKw: connector ? Number(connector.power_kw) : undefined,
    pricePerKwh: connector ? Number(connector.price_per_kwh) : undefined,
    batteryPct: Number(computeBatteryPct(row.start_battery_pct, row.energy_kwh).toFixed(1)),
    startBatteryPct: row.start_battery_pct,
    autoStopPct: row.auto_stop_pct,
  };
}
```

Replace with:

```js
function formatSession(row, connector) {
  return {
    id: row.id,
    stationId: row.station_id,
    stationName: row.station_name,
    connectorId: row.connector_id,
    status: row.status,
    startedAt: row.started_at,
    stoppedAt: row.stopped_at,
    energyKwh: Number(row.energy_kwh),
    cost: Number(row.cost),
    powerKw: connector ? Number(connector.power_kw) : undefined,
    pricePerKwh: connector ? Number(connector.price_per_kwh) : undefined,
    batteryPct: Number(computeBatteryPct(row.start_battery_pct, row.energy_kwh, row.battery_capacity_kwh).toFixed(1)),
    startBatteryPct: row.start_battery_pct,
    autoStopPct: row.auto_stop_pct,
    batteryCapacityKwh: Number(row.battery_capacity_kwh),
  };
}
```

- [ ] **Step 4: Use the session's capacity in `GET /active`'s live calc and auto-stop trigger**

Find:

```js
  const row = rows[0];
  // Simulate live energy delivered based on elapsed time * connector power.
  const elapsedHours = (Date.now() - new Date(row.started_at).getTime()) / 3600000;
  const energyKwh = Math.min(elapsedHours * Number(row.power_kw), 100); // cap for demo
  const cost = energyKwh * Number(row.price_per_kwh);
  const batteryPct = computeBatteryPct(row.start_battery_pct, energyKwh);

  // auto_stop_pct of null means "charge to 100%" — treat it the same as an
  // explicit target of 100 so every session eventually completes.
  const targetPct = row.auto_stop_pct ?? 100;
  let autoStopBlocked = null;
  if (batteryPct >= targetPct) {
    // Bill only the energy needed to reach the target, not full elapsed
    // wall-clock energy — polls can arrive long after the target was
    // crossed (e.g. app backgrounded for hours), and billing elapsed
    // energy in that case would overcharge the user well past their
    // requested stop point.
    const energyToTarget = Math.max(0, (targetPct - Number(row.start_battery_pct)) / 100) * BATTERY_CAPACITY_KWH;
```

Replace with:

```js
  const row = rows[0];
  // Simulate live energy delivered based on elapsed time * connector power.
  const elapsedHours = (Date.now() - new Date(row.started_at).getTime()) / 3600000;
  const energyKwh = Math.min(elapsedHours * Number(row.power_kw), 100); // cap for demo
  const cost = energyKwh * Number(row.price_per_kwh);
  const batteryPct = computeBatteryPct(row.start_battery_pct, energyKwh, row.battery_capacity_kwh);

  // auto_stop_pct of null means "charge to 100%" — treat it the same as an
  // explicit target of 100 so every session eventually completes.
  const targetPct = row.auto_stop_pct ?? 100;
  let autoStopBlocked = null;
  if (batteryPct >= targetPct) {
    // Bill only the energy needed to reach the target, not full elapsed
    // wall-clock energy — polls can arrive long after the target was
    // crossed (e.g. app backgrounded for hours), and billing elapsed
    // energy in that case would overcharge the user well past their
    // requested stop point.
    const energyToTarget = Math.max(0, (targetPct - Number(row.start_battery_pct)) / 100) * Number(row.battery_capacity_kwh);
```

- [ ] **Step 5: Include `batteryCapacityKwh` in the still-active response shape**

Find:

```js
  res.json({
    session: {
      id: row.id,
      stationId: row.station_id,
      stationName: row.station_name,
      connectorId: row.connector_id,
      status: row.status,
      startedAt: row.started_at,
      powerKw: Number(row.power_kw),
      pricePerKwh: Number(row.price_per_kwh),
      energyKwh: Number(energyKwh.toFixed(2)),
      cost: Number(cost.toFixed(2)),
      batteryPct: Number(batteryPct.toFixed(1)),
      startBatteryPct: row.start_battery_pct,
      autoStopPct: row.auto_stop_pct,
      ...(autoStopBlocked
        ? {
            autoStopBlocked: true,
            blockedReason: autoStopBlocked.blockedReason,
            requiredCost: autoStopBlocked.requiredCost,
            walletBalance: autoStopBlocked.walletBalance,
          }
        : {}),
    },
  });
}));
```

Replace with:

```js
  res.json({
    session: {
      id: row.id,
      stationId: row.station_id,
      stationName: row.station_name,
      connectorId: row.connector_id,
      status: row.status,
      startedAt: row.started_at,
      powerKw: Number(row.power_kw),
      pricePerKwh: Number(row.price_per_kwh),
      energyKwh: Number(energyKwh.toFixed(2)),
      cost: Number(cost.toFixed(2)),
      batteryPct: Number(batteryPct.toFixed(1)),
      startBatteryPct: row.start_battery_pct,
      autoStopPct: row.auto_stop_pct,
      batteryCapacityKwh: Number(row.battery_capacity_kwh),
      ...(autoStopBlocked
        ? {
            autoStopBlocked: true,
            blockedReason: autoStopBlocked.blockedReason,
            requiredCost: autoStopBlocked.requiredCost,
            walletBalance: autoStopBlocked.walletBalance,
          }
        : {}),
    },
  });
}));
```

- [ ] **Step 6: Use the session's capacity in `PATCH /auto-stop`**

Find:

```js
  res.json({
    session: {
      id: row.id,
      stationId: row.station_id,
      stationName: connector.station_name,
      connectorId: row.connector_id,
      status: row.status,
      startedAt: row.started_at,
      powerKw: Number(connector.power_kw),
      pricePerKwh: Number(connector.price_per_kwh),
      energyKwh: Number(energyKwh.toFixed(2)),
      cost: Number(cost.toFixed(2)),
      batteryPct: Number(computeBatteryPct(row.start_battery_pct, energyKwh).toFixed(1)),
      startBatteryPct: row.start_battery_pct,
      autoStopPct: row.auto_stop_pct,
    },
  });
}));

// GET /api/sessions/history
```

Replace with:

```js
  res.json({
    session: {
      id: row.id,
      stationId: row.station_id,
      stationName: connector.station_name,
      connectorId: row.connector_id,
      status: row.status,
      startedAt: row.started_at,
      powerKw: Number(connector.power_kw),
      pricePerKwh: Number(connector.price_per_kwh),
      energyKwh: Number(energyKwh.toFixed(2)),
      cost: Number(cost.toFixed(2)),
      batteryPct: Number(computeBatteryPct(row.start_battery_pct, energyKwh, row.battery_capacity_kwh).toFixed(1)),
      startBatteryPct: row.start_battery_pct,
      autoStopPct: row.auto_stop_pct,
      batteryCapacityKwh: Number(row.battery_capacity_kwh),
    },
  });
}));

// GET /api/sessions/history
```

- [ ] **Step 7: Verify with the running backend**

Restart the backend if needed (from `backend/`): `node server.js`. Add a low-capacity vehicle and start a session with it on a matching connector — use the seeded `Type2` connector at "Arera Colony Green Hub" (22 kW, ₹14.00/kWh, per `backend/db/seed.sql`):

```bash
TOKEN="<paste a valid JWT here>"
curl -s -X POST http://localhost:4000/api/vehicles \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"make":"Ola","model":"S1 Pro","connectorType":"Type2","batteryCapacityKwh":4}'
```

Copy the returned `vehicle.id`, find the Arera Colony station/connector IDs (query the DB directly the same way earlier tasks did, filtering for `connector_type = 'Type2'`), then:

```bash
curl -s -X POST http://localhost:4000/api/sessions/start \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"stationId":"<arera colony station id>","connectorId":"<its Type2 connector id>","vehicleId":"<vehicle id>","autoStopPct":50}'
```

Expected: `201` with `session.batteryCapacityKwh: 4`.

Then poll:
```bash
curl -s http://localhost:4000/api/sessions/active -H "Authorization: Bearer $TOKEN"
```

Expected: `batteryPct` climbs much faster per kWh than the old 40kWh assumption would predict — e.g. if `energyKwh` shows `0.05`, `batteryPct` should be roughly `startBatteryPct + (0.05/4)*100` (~1.25 points), not `startBatteryPct + (0.05/40)*100` (~0.125 points). Also confirm a mismatched-connector attempt still 409s: try starting a session with this same `vehicleId` (Type2) against a CCS2 connector — expect `409` with the existing "not compatible with your vehicle" message (this check already existed; this is the first time it's actually reachable in this codebase's test history).

- [ ] **Step 8: Commit**

```bash
git add backend/routes/sessions.js
git commit -m "Snapshot vehicle battery capacity onto sessions and use it in all battery-percentage math"
```

---

### Task 5: Frontend — hardcoded vehicle catalog

**Files:**
- Create: `frontend/lib/data/vehicle_catalog.dart`

**Interfaces:**
- Produces: `VehicleCatalogEntry` class (`make`, `model`, `capacityKwh`, `connectorType`, `displayName` getter), `kVehicleCatalog: List<VehicleCatalogEntry>` (25 entries) — consumed by Task 7 (Profile add-vehicle sheet).

- [ ] **Step 1: Create the catalog file**

Create `frontend/lib/data/vehicle_catalog.dart`:

```dart
/// Static, hardcoded catalog of common India-market EVs, used by the
/// vehicle-selection UI (Profile "Add vehicle" and the Charge Now flow).
/// No external API — capacities were verified against public specs as of
/// August 2026 and are the base/current India-market trim where a model
/// has multiple battery options.
class VehicleCatalogEntry {
  final String make;
  final String model;
  final double capacityKwh;
  final String connectorType;

  const VehicleCatalogEntry({
    required this.make,
    required this.model,
    required this.capacityKwh,
    required this.connectorType,
  });

  String get displayName => '$make $model';
}

const List<VehicleCatalogEntry> kVehicleCatalog = [
  // Cars
  VehicleCatalogEntry(make: 'Tata', model: 'Tiago EV', capacityKwh: 24, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Tata', model: 'Punch EV', capacityKwh: 35, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Tata', model: 'Nexon EV', capacityKwh: 40.2, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Tata', model: 'Curvv EV', capacityKwh: 55, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Mahindra', model: 'XUV400', capacityKwh: 39.4, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Mahindra', model: 'BE 6', capacityKwh: 79, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Mahindra', model: 'XEV 9e', capacityKwh: 79, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'MG', model: 'Comet EV', capacityKwh: 17.3, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'MG', model: 'ZS EV', capacityKwh: 50.3, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'MG', model: 'Windsor EV', capacityKwh: 52.9, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Hyundai', model: 'Kona Electric', capacityKwh: 39.2, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Hyundai', model: 'Ioniq 5', capacityKwh: 72.6, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Hyundai', model: 'Creta Electric', capacityKwh: 51.4, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'BYD', model: 'Atto 3', capacityKwh: 60.5, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'BYD', model: 'Seal', capacityKwh: 82.5, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'BYD', model: 'eMax 7', capacityKwh: 71.8, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Citroen', model: 'eC3', capacityKwh: 29.2, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Maruti Suzuki', model: 'e Vitara', capacityKwh: 61, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Kia', model: 'EV6', capacityKwh: 77.4, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Kia', model: 'Syros EV', capacityKwh: 51.4, connectorType: 'CCS2'),
  VehicleCatalogEntry(make: 'Volvo', model: 'EX30', capacityKwh: 69, connectorType: 'CCS2'),
  // Two-wheelers
  VehicleCatalogEntry(make: 'Ola', model: 'S1 Pro', capacityKwh: 4, connectorType: 'Type2'),
  VehicleCatalogEntry(make: 'Ather', model: '450X', capacityKwh: 3.7, connectorType: 'Type2'),
  VehicleCatalogEntry(make: 'TVS', model: 'iQube', capacityKwh: 3.04, connectorType: 'Type2'),
  VehicleCatalogEntry(make: 'Bajaj', model: 'Chetak', capacityKwh: 3, connectorType: 'Type2'),
];
```

- [ ] **Step 2: Verify the app still compiles**

Run (from `frontend/`): `flutter analyze`
Expected: no new errors (this is a standalone data file with no dependents yet).

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/data/vehicle_catalog.dart
git commit -m "Add hardcoded vehicle catalog with verified battery capacities"
```

---

### Task 6: Frontend — `Vehicle` model and `ApiService.addVehicle` capacity threading

**Files:**
- Modify: `frontend/lib/models/models.dart`
- Modify: `frontend/lib/services/api_service.dart`

**Interfaces:**
- Produces: `Vehicle.batteryCapacityKwh: double` (required); `ApiService.addVehicle(..., batteryCapacityKwh: required double, ...)` — consumed by Task 7 (Profile screen) and Task 9 (Charge Now flow, reads `Vehicle.batteryCapacityKwh` for display).

- [ ] **Step 1: Extend the `Vehicle` model**

In `frontend/lib/models/models.dart`, find:

```dart
class Vehicle {
  final String id;
  final String make;
  final String model;
  final String connectorType;
  final String? regNumber;
  final bool isDefault;

  Vehicle({
    required this.id,
    required this.make,
    required this.model,
    required this.connectorType,
    this.regNumber,
    required this.isDefault,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'],
      make: json['make'],
      model: json['model'],
      connectorType: json['connectorType'],
      regNumber: json['regNumber'],
      isDefault: json['isDefault'] ?? false,
    );
  }

  String get displayName => '$make $model';
}
```

Replace with:

```dart
class Vehicle {
  final String id;
  final String make;
  final String model;
  final String connectorType;
  final String? regNumber;
  final bool isDefault;
  final double batteryCapacityKwh;

  Vehicle({
    required this.id,
    required this.make,
    required this.model,
    required this.connectorType,
    this.regNumber,
    required this.isDefault,
    required this.batteryCapacityKwh,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'],
      make: json['make'],
      model: json['model'],
      connectorType: json['connectorType'],
      regNumber: json['regNumber'],
      isDefault: json['isDefault'] ?? false,
      batteryCapacityKwh: (json['batteryCapacityKwh'] as num).toDouble(),
    );
  }

  String get displayName => '$make $model';
}
```

- [ ] **Step 2: Extend `ApiService.addVehicle`**

In `frontend/lib/services/api_service.dart`, find:

```dart
  Future<Map<String, dynamic>> addVehicle({
    required String make,
    required String model,
    required String connectorType,
    String? regNumber,
    bool isDefault = false,
  }) async {
    final res = await http.post(
      _uri('/api/vehicles'),
      headers: await _headers(),
      body: jsonEncode({
        'make': make,
        'model': model,
        'connectorType': connectorType,
        'regNumber': regNumber,
        'isDefault': isDefault,
      }),
    );
    return await _handle(res);
  }
```

Replace with:

```dart
  Future<Map<String, dynamic>> addVehicle({
    required String make,
    required String model,
    required String connectorType,
    required double batteryCapacityKwh,
    String? regNumber,
    bool isDefault = false,
  }) async {
    final res = await http.post(
      _uri('/api/vehicles'),
      headers: await _headers(),
      body: jsonEncode({
        'make': make,
        'model': model,
        'connectorType': connectorType,
        'batteryCapacityKwh': batteryCapacityKwh,
        'regNumber': regNumber,
        'isDefault': isDefault,
      }),
    );
    return await _handle(res);
  }
```

- [ ] **Step 3: Verify the app still compiles**

Run (from `frontend/`): `flutter analyze`
Expected: a NEW error will appear at `frontend/lib/screens/profile/profile_screen.dart`'s existing `_api.addVehicle(...)` call site, because it doesn't yet pass the new required `batteryCapacityKwh` parameter — this is expected and gets fixed in Task 7, which replaces that entire call site. Confirm there are no *other* new errors, and that `models.dart`/`api_service.dart` themselves have no errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/models/models.dart frontend/lib/services/api_service.dart
git commit -m "Add batteryCapacityKwh to Vehicle model and ApiService.addVehicle"
```

---

### Task 7: Frontend — Profile screen curated vehicle picker

**Files:**
- Modify: `frontend/lib/screens/profile/profile_screen.dart`

**Interfaces:**
- Consumes: `kVehicleCatalog`, `VehicleCatalogEntry` (Task 5); `ApiService.addVehicle(..., batteryCapacityKwh: required double, ...)` (Task 6)
- Produces: none consumed by later tasks (this is the terminal UI for adding vehicles).

- [ ] **Step 1: Add the catalog import**

In `frontend/lib/screens/profile/profile_screen.dart`, find:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../auth/phone_entry_screen.dart';
```

Replace with:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../data/vehicle_catalog.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../auth/phone_entry_screen.dart';
```

- [ ] **Step 2: Replace the free-text `_addVehicleSheet` method**

Find the entire existing method (from `Future<void> _addVehicleSheet() async {` through its closing `}` right before `Future<void> _logout() async {`):

```dart
  Future<void> _addVehicleSheet() async {
    final makeCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    String connectorType = 'CCS2';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            final canSave = makeCtrl.text.trim().isNotEmpty && modelCtrl.text.trim().isNotEmpty;
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.chromeMist,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add a vehicle', style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: makeCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: const InputDecoration(hintText: 'Make (e.g. Tata) *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: const InputDecoration(hintText: 'Model (e.g. Nexon EV) *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: regCtrl, decoration: const InputDecoration(hintText: 'Registration number (optional)')),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: ['CCS2', 'CHAdeMO', 'Type2', 'GBT'].map((type) {
                      final sel = connectorType == type;
                      return ChoiceChip(
                        label: Text(type),
                        selected: sel,
                        onSelected: (_) => setSheetState(() => connectorType = type),
                        selectedColor: AppColors.skyBlue,
                        labelStyle: GoogleFonts.nunitoSans(color: sel ? Colors.white : AppColors.deepAzure, fontWeight: FontWeight.w700),
                        backgroundColor: Colors.white,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text('* Make and model are required', style: GoogleFonts.nunitoSans(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 12),
                  EnergyOrbButton(
                    label: 'Save vehicle',
                    icon: Icons.directions_car_filled_rounded,
                    green: true,
                    width: double.infinity,
                    onPressed: !canSave
                        ? null
                        : () async {
                            final make = makeCtrl.text.trim();
                            final model = modelCtrl.text.trim();
                            final regNumber = regCtrl.text.trim();
                            Navigator.pop(ctx);
                            try {
                              await _api.addVehicle(
                                make: make,
                                model: model,
                                connectorType: connectorType,
                                regNumber: regNumber.isEmpty ? null : regNumber,
                              );
                              _load();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Could not save vehicle: $e')),
                              );
                            }
                          },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
```

Replace with:

```dart
  Future<void> _addVehicleSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => const _AddVehicleSheetContent(),
    );
    if (added == true) _load();
  }
```

- [ ] **Step 3: Add the capacity readout to saved-vehicle list tiles**

Find:

```dart
                        title: Text(v.displayName, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                        subtitle: Text('${v.connectorType}${v.regNumber != null ? ' • ${v.regNumber}' : ''}'),
```

Replace with:

```dart
                        title: Text(v.displayName, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${v.connectorType} • ${v.batteryCapacityKwh.toStringAsFixed(1)} kWh${v.regNumber != null ? ' • ${v.regNumber}' : ''}',
                        ),
```

- [ ] **Step 4: Add the new `_AddVehicleSheetContent` widget**

`_AddVehicleSheetContent` is a new top-level widget — it must go outside the `_ProfileScreenState` class. At the very end of `frontend/lib/screens/profile/profile_screen.dart` (after the closing `}` of `_ProfileScreenState`, which is the last thing in the file), append:

```dart

class _AddVehicleSheetContent extends StatefulWidget {
  const _AddVehicleSheetContent();

  @override
  State<_AddVehicleSheetContent> createState() => _AddVehicleSheetContentState();
}

class _AddVehicleSheetContentState extends State<_AddVehicleSheetContent> {
  final _api = ApiService();
  bool _showManualForm = false;
  bool _saving = false;

  final _makeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  String _manualConnectorType = 'CCS2';

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCatalogEntry(VehicleCatalogEntry entry) async {
    setState(() => _saving = true);
    try {
      await _api.addVehicle(
        make: entry.make,
        model: entry.model,
        connectorType: entry.connectorType,
        batteryCapacityKwh: entry.capacityKwh,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save vehicle: $e')),
      );
    }
  }

  Future<void> _saveManualEntry() async {
    final make = _makeCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    final capacity = double.tryParse(_capacityCtrl.text.trim());
    if (make.isEmpty || model.isEmpty || capacity == null || capacity <= 0) return;

    setState(() => _saving = true);
    try {
      await _api.addVehicle(
        make: make,
        model: model,
        connectorType: _manualConnectorType,
        batteryCapacityKwh: capacity,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save vehicle: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.chromeMist,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: _showManualForm ? _manualForm() : _catalogList(),
      ),
    );
  }

  Widget _catalogList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add a vehicle', style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
        const SizedBox(height: 4),
        Text(
          'Pick your EV so we can size Auto Stop correctly.',
          style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: kVehicleCatalog.length + 1,
            itemBuilder: (context, i) {
              if (i == kVehicleCatalog.length) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    radius: 16,
                    child: ListTile(
                      leading: const Icon(Icons.edit_note_rounded, color: AppColors.skyBlue),
                      title: Text('Other / not listed', style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                      onTap: _saving ? null : () => setState(() => _showManualForm = true),
                    ),
                  ),
                );
              }
              final entry = kVehicleCatalog[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassPanel(
                  padding: EdgeInsets.zero,
                  radius: 16,
                  child: ListTile(
                    leading: const Icon(Icons.directions_car_filled_rounded, color: AppColors.skyBlue),
                    title: Text(entry.displayName, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                    subtitle: Text('${entry.connectorType} • ${entry.capacityKwh.toStringAsFixed(1)} kWh'),
                    onTap: _saving ? null : () => _saveCatalogEntry(entry),
                  ),
                ),
              );
            },
          ),
        ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(child: CircularProgressIndicator(color: AppColors.skyBlue)),
          ),
      ],
    );
  }

  Widget _manualForm() {
    return StatefulBuilder(
      builder: (ctx, setSheetState) {
        final canSave = _makeCtrl.text.trim().isNotEmpty &&
            _modelCtrl.text.trim().isNotEmpty &&
            (double.tryParse(_capacityCtrl.text.trim()) ?? 0) > 0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: AppColors.deepAzure),
                  onPressed: () => setState(() => _showManualForm = false),
                ),
                Text('Add your vehicle', style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _makeCtrl,
              onChanged: (_) => setSheetState(() {}),
              decoration: const InputDecoration(hintText: 'Make (e.g. Tata) *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelCtrl,
              onChanged: (_) => setSheetState(() {}),
              decoration: const InputDecoration(hintText: 'Model (e.g. Nexon EV) *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacityCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setSheetState(() {}),
              decoration: const InputDecoration(hintText: 'Battery capacity in kWh (e.g. 40) *'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: ['CCS2', 'Type2'].map((type) {
                final sel = _manualConnectorType == type;
                return ChoiceChip(
                  label: Text(type),
                  selected: sel,
                  onSelected: (_) => setSheetState(() => _manualConnectorType = type),
                  selectedColor: AppColors.skyBlue,
                  labelStyle: GoogleFonts.nunitoSans(color: sel ? Colors.white : AppColors.deepAzure, fontWeight: FontWeight.w700),
                  backgroundColor: Colors.white,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text('* Make, model, and capacity are required', style: GoogleFonts.nunitoSans(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            EnergyOrbButton(
              label: 'Save vehicle',
              icon: Icons.directions_car_filled_rounded,
              green: true,
              width: double.infinity,
              loading: _saving,
              onPressed: !canSave || _saving ? null : _saveManualEntry,
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 5: Verify the app compiles**

Run (from `frontend/`): `flutter analyze`
Expected: no new errors (this resolves the expected error flagged at the end of Task 6, since the old `addVehicle` call site no longer exists).

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/screens/profile/profile_screen.dart
git commit -m "Replace free-text Add Vehicle sheet with curated catalog picker + Other fallback"
```

---

### Task 8: Frontend — fix overflow on the connector card's "Charge now" button

**Files:**
- Modify: `frontend/lib/widgets/aero/energy_orb_button.dart`

**Interfaces:**
- None (isolated shared-widget fix; no signature changes).

- [ ] **Step 1: Make the label text shrink instead of overflow**

In `frontend/lib/widgets/aero/energy_orb_button.dart`, find:

```dart
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.icon != null) ...[
                                  Icon(widget.icon, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  widget.label,
                                  style: GoogleFonts.baloo2(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    shadows: const [Shadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1))],
                                  ),
                                ),
                              ],
                            ),
```

Replace with:

```dart
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.icon != null) ...[
                                  Icon(widget.icon, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: Text(
                                    widget.label,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: GoogleFonts.baloo2(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      shadows: const [Shadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1))],
                                    ),
                                  ),
                                ),
                              ],
                            ),
```

- [ ] **Step 2: Verify the app compiles**

Run (from `frontend/`): `flutter analyze`
Expected: no new errors. (Visual confirmation that the overflow banner is gone happens during Task 10's device walkthrough.)

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/widgets/aero/energy_orb_button.dart
git commit -m "Fix EnergyOrbButton overflow when squeezed into a tight width"
```

---

### Task 9: Frontend — vehicle selection in the Charge Now flow

**Files:**
- Modify: `frontend/lib/screens/station/station_detail_screen.dart`

**Interfaces:**
- Consumes: `Vehicle` (Task 6), `ApiService.getVehicles()` (pre-existing), `ProfileScreen` (pre-existing widget), `SessionProvider.startCharging(..., vehicleId: String?, ...)` (pre-existing param, now actually populated)

- [ ] **Step 1: Add the new imports**

In `frontend/lib/screens/station/station_detail_screen.dart`, find:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/station.dart';
import '../../providers/station_provider.dart';
import '../../providers/session_provider.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../booking/booking_screen.dart';
import '../session/active_session_screen.dart';
```

Replace with:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../models/station.dart';
import '../../providers/station_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/aero/aero_background.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../booking/booking_screen.dart';
import '../profile/profile_screen.dart';
import '../session/active_session_screen.dart';
```

- [ ] **Step 2: Resolve a compatible vehicle before showing the charge sheet**

Find:

```dart
  Future<void> _startChargingNow(BuildContext context, Station station, Connector connector) async {
    final autoStopPct = await _showAutoStopSheet(context);
    if (autoStopPct == null || !context.mounted) return; // user cancelled the sheet

    final sessionProvider = context.read<SessionProvider>();
    final ok = await sessionProvider.startCharging(
      stationId: station.id,
      connectorId: connector.id,
      autoStopPct: autoStopPct == 100 ? null : autoStopPct,
    );
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ActiveSessionScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sessionProvider.error ?? 'Could not start charging')),
      );
    }
  }
```

Replace with:

```dart
  Future<void> _startChargingNow(BuildContext context, Station station, Connector connector) async {
    final api = ApiService();
    final rawVehicles = await api.getVehicles();
    final vehicles = rawVehicles.map((v) => Vehicle.fromJson(v)).toList();
    final compatible = vehicles.where((v) => v.connectorType == connector.connectorType).toList();

    if (!context.mounted) return;

    if (compatible.isEmpty) {
      final wantsToAdd = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add a compatible vehicle'),
          content: Text('You need a saved ${connector.connectorType} vehicle before charging here.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add vehicle')),
          ],
        ),
      );
      if (wantsToAdd != true || !context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
      if (!context.mounted) return;
      return _startChargingNow(context, station, connector);
    }

    final result = await _showChargeSheet(context, compatible);
    if (result == null || !context.mounted) return; // user cancelled the sheet

    final sessionProvider = context.read<SessionProvider>();
    final ok = await sessionProvider.startCharging(
      stationId: station.id,
      connectorId: connector.id,
      vehicleId: result.vehicleId,
      autoStopPct: result.autoStopPct == 100 ? null : result.autoStopPct,
    );
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ActiveSessionScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sessionProvider.error ?? 'Could not start charging')),
      );
    }
  }
```

- [ ] **Step 3: Replace `_showAutoStopSheet` with the combined vehicle + Auto Stop sheet**

Find the entire existing method:

```dart
  /// Shows a bottom sheet to pick the Auto Stop battery target (10 steps of
  /// 10%, default 100 = charge to full). Returns the chosen percentage, or
  /// null if the user dismissed the sheet without confirming.
  Future<int?> _showAutoStopSheet(BuildContext context) async {
    int selected = 100;
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.chromeMist,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Auto Stop charging at',
                  style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
              const SizedBox(height: 4),
              Text('Charging stops automatically once the battery reaches this level.',
                  style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5)),
              const SizedBox(height: 12),
              GlassPanel(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                radius: 20,
                child: Column(
                  children: [
                    Text('$selected%',
                        style: GoogleFonts.baloo2(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.skyBlue)),
                    Slider(
                      value: selected.toDouble(),
                      min: 10,
                      max: 100,
                      divisions: 9, // 10 steps of 10%: 10,20,...,100
                      activeColor: AppColors.skyBlue,
                      label: '$selected%',
                      onChanged: (v) => setSheetState(() => selected = v.round()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              EnergyOrbButton(
                label: 'Start charging',
                icon: Icons.bolt_rounded,
                width: double.infinity,
                onPressed: () => Navigator.pop(ctx, selected),
              ),
            ],
          ),
        ),
      ),
    );
  }
```

Replace with:

```dart
  /// Shows a combined bottom sheet: pick which saved vehicle is charging
  /// (pre-selected if only one is compatible), then the Auto Stop battery
  /// target (10 steps of 10%, range 10–100%, default 100 = charge to
  /// full). Returns the chosen vehicle ID + percentage, or null if the
  /// user dismissed the sheet without confirming.
  Future<({String vehicleId, int autoStopPct})?> _showChargeSheet(
    BuildContext context,
    List<Vehicle> compatibleVehicles,
  ) async {
    Vehicle selectedVehicle = compatibleVehicles.firstWhere(
      (v) => v.isDefault,
      orElse: () => compatibleVehicles.first,
    );
    int selectedPct = 100;
    return showModalBottomSheet<({String vehicleId, int autoStopPct})>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.chromeMist,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vehicle', style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
              const SizedBox(height: 10),
              if (compatibleVehicles.length == 1)
                GlassPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  radius: 16,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.directions_car_filled_rounded, color: AppColors.skyBlue),
                    title: Text(selectedVehicle.displayName, style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700)),
                    subtitle: Text('${selectedVehicle.batteryCapacityKwh.toStringAsFixed(1)} kWh'),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: compatibleVehicles.map((v) {
                    final sel = v.id == selectedVehicle.id;
                    return ChoiceChip(
                      label: Text(v.displayName),
                      selected: sel,
                      onSelected: (_) => setSheetState(() => selectedVehicle = v),
                      selectedColor: AppColors.skyBlue,
                      labelStyle: GoogleFonts.nunitoSans(color: sel ? Colors.white : AppColors.deepAzure, fontWeight: FontWeight.w700),
                      backgroundColor: Colors.white,
                    );
                  }).toList(),
                ),
              const SizedBox(height: 20),
              Text('Auto Stop charging at',
                  style: GoogleFonts.baloo2(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.deepAzure)),
              const SizedBox(height: 4),
              Text('Charging stops automatically once the battery reaches this level.',
                  style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5)),
              const SizedBox(height: 12),
              GlassPanel(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                radius: 20,
                child: Column(
                  children: [
                    Text('$selectedPct%',
                        style: GoogleFonts.baloo2(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.skyBlue)),
                    Slider(
                      value: selectedPct.toDouble(),
                      min: 10,
                      max: 100,
                      divisions: 9, // 10 steps of 10%: 10,20,...,100
                      activeColor: AppColors.skyBlue,
                      label: '$selectedPct%',
                      onChanged: (v) => setSheetState(() => selectedPct = v.round()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              EnergyOrbButton(
                label: 'Start charging',
                icon: Icons.bolt_rounded,
                width: double.infinity,
                onPressed: () => Navigator.pop(ctx, (vehicleId: selectedVehicle.id, autoStopPct: selectedPct)),
              ),
            ],
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 4: Verify the app compiles**

Run (from `frontend/`): `flutter analyze`
Expected: no new errors in `station_detail_screen.dart`.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/station/station_detail_screen.dart
git commit -m "Wire vehicle selection into the Charge Now flow, filtered by connector compatibility"
```

---

### Task 10: Frontend — History tab refreshes when switched to

**Files:**
- Modify: `frontend/lib/screens/home/home_shell.dart`
- Modify: `frontend/lib/screens/history/history_screen.dart`

**Interfaces:**
- Produces: `HistoryScreen({Key? key, bool isActive = true})` — consumed by `HomeShell`.

- [ ] **Step 1: Make `HomeShell` recompute `HistoryScreen`'s `isActive` flag each build**

In `frontend/lib/screens/home/home_shell.dart`, find:

```dart
class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final _screens = const [
    HomeScreen(),
    HistoryScreen(),
    WalletScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
```

Replace with:

```dart
class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      HistoryScreen(isActive: _index == 1),
      const WalletScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
```

- [ ] **Step 2: Add the `isActive` param and reload-on-visible to `HistoryScreen`**

In `frontend/lib/screens/history/history_screen.dart`, find:

```dart
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabController;

  List<ChargingSession> _sessions = [];
  List<Booking> _bookings = [];
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }
```

Replace with:

```dart
class HistoryScreen extends StatefulWidget {
  final bool isActive;
  const HistoryScreen({super.key, this.isActive = true});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabController;

  List<ChargingSession> _sessions = [];
  List<Booking> _bookings = [];
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _load();
    }
  }
```

- [ ] **Step 3: Verify the app compiles**

Run (from `frontend/`): `flutter analyze`
Expected: no new errors in `home_shell.dart` or `history_screen.dart`.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/home/home_shell.dart frontend/lib/screens/history/history_screen.dart
git commit -m "Reload History tab data when switching back to it, not just on first build"
```

---

### Task 11: Frontend — wallet top-up reports real failures

**Files:**
- Modify: `frontend/lib/providers/wallet_provider.dart`

**Interfaces:**
- None (behavior-only change; `topUp`'s signature and the existing `WalletScreen` snackbar logic are unchanged).

- [ ] **Step 1: Remove the optimistic fake-success fallback**

In `frontend/lib/providers/wallet_provider.dart`, find:

```dart
  Future<bool> topUp(double amount) async {
    try {
      final data = await _api.topUpWallet(amount, reference: 'app_topup');
      balance = (data['balance'] as num).toDouble();
      await load();
      return true;
    } catch (e) {
      // The top-up request failed (e.g. backend unreachable). Rather than
      // surface a hard failure to the user mid-flow, apply the top-up
      // optimistically on the client so the experience stays smooth; it
      // will reconcile with the server balance next time load() succeeds.
      balance += amount;
      transactions = [
        WalletTransaction(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          type: 'topup',
          amount: amount,
          reference: 'app_topup',
          createdAt: DateTime.now(),
        ),
        ...transactions,
      ];
      notifyListeners();
      return true;
    }
  }
```

Replace with:

```dart
  Future<bool> topUp(double amount) async {
    try {
      final data = await _api.topUpWallet(amount, reference: 'app_topup');
      balance = (data['balance'] as num).toDouble();
      await load();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }
```

- [ ] **Step 2: Verify the app compiles**

Run (from `frontend/`): `flutter analyze`
Expected: no new errors. Note `WalletTransaction` may now be unused as an import in this file if it's not referenced elsewhere in `wallet_provider.dart` — check the top of the file; if `import '../models/models.dart';` is still needed for other types used in this file (it is — `WalletTransaction` is used in `transactions` field's type and in `WalletTransaction.fromJson` inside `load()`), no import changes are needed.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/providers/wallet_provider.dart
git commit -m "Report real wallet top-up failures instead of faking success"
```

---

### Task 12: End-to-end verification on device

**Files:** none (verification only)

- [ ] **Step 1: Rebuild and relaunch the app**

With the phone connected via USB and `adb reverse tcp:4000 tcp:4000` still active (re-run it if the phone was unplugged), relaunch from Android Studio (Stop, then Run ▶) so the app picks up all the new code.

- [ ] **Step 2: Walk through the full flow manually**

1. Log in (OTP flow).
2. Go to Profile → "Add" a vehicle → confirm the curated 25-entry list appears (scrollable), each row showing capacity + connector type. Pick one (e.g. "Tata Nexon EV").
3. Add a second vehicle via "Other / not listed" → confirm the manual form asks for make, model, capacity (kWh), and a CCS2/Type2 choice, and that saving it works.
4. Confirm both vehicles appear in "My vehicles" with their capacity shown in the subtitle.
5. Go to a station, tap "Charge now" on a connector whose type matches one of your vehicles — confirm the combined sheet shows a "Vehicle" section (pre-selected if you only have one compatible vehicle, or a chip picker if more than one) above the Auto Stop slider.
6. Confirm the connector-card "Charge now" button no longer shows the red/white "OVERFLOWED" debug banner.
7. Start a session with a low-capacity vehicle (e.g. an Ola S1 Pro at 4 kWh, if added) and a low Auto Stop target — on the active session screen, confirm the battery ring climbs noticeably faster than it did before this feature (compare against your memory of testing with no vehicle attached, or against a session with a high-capacity car).
8. Confirm it still auto-stops correctly and the wallet debit matches the smaller pack's math (much cheaper than before, since less energy is needed to move the same percentage).
9. Try tapping "Charge now" on a connector with NO matching saved vehicle (e.g. if you only added CCS2 cars, try a Type2 connector) — confirm the "Add a compatible vehicle" prompt appears and routes to Profile.
10. Go to History tab before starting any new session (or right after app launch) — note whatever it shows. Complete another charging session. Switch to a different tab, then back to History — confirm the new completed session now appears WITHOUT needing to manually pull-to-refresh.
11. Go to Wallet, and (if possible) briefly stop the backend server (`Ctrl+C` in its terminal) before tapping "Add money" → confirm you now see a "Top-up failed" message instead of a fake success, and the balance shown doesn't change. Restart the backend afterward.

- [ ] **Step 3: Report results**

No commit for this task — it's manual verification of everything committed in Tasks 1–11.
