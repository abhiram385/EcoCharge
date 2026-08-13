# Battery Level + Remote Auto Stop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a simulated battery percentage to charging sessions, with a user-settable "Auto Stop" target that automatically ends the session (and charges the wallet) once the battery reaches it.

**Architecture:** Battery percentage is computed on read from `start_battery_pct` (randomly assigned at session start) plus energy delivered so far, mirroring how `energyKwh`/`cost` are already computed live rather than stored incrementally. Auto-stop is enforced at poll time inside `GET /api/sessions/active` (the screen already polls every 5s) by reusing a shared `finalizeSession` helper extracted from the existing manual-stop transaction.

**Tech Stack:** Node/Express/pg (backend), Flutter/Dart with `provider` (frontend), Jest (backend unit tests).

## Global Constraints

- Battery capacity constant: `40` kWh (matches the existing hardcoded assumption already in the frontend's progress ring — being centralized here, not introduced new).
- `start_battery_pct` random range: 15–55 inclusive, via `crypto.randomInt` (not `Math.random`, matching this repo's existing convention in `utils/otp.js`).
- Valid `autoStopPct` values: `10, 20, 30, 40, 50, 60, 70, 80, 90, 100` only, or `null`/omitted (meaning "charge to 100%" — treated identically to an explicit target of 100).
- Auto-stop is poll-triggered only (no background scheduler) — confirmed acceptable by the user.
- New UI must reuse the existing `GlassPanel` / `EnergyOrbButton` components — it will be reskinned together with the rest of the app in a later Frutiger Aero redesign pass, not styled twice.
- Spec: `docs/superpowers/specs/2026-08-13-battery-autostop-design.md`

---

### Task 1: Database schema — add battery columns

**Files:**
- Modify: `backend/db/schema.sql`

**Interfaces:**
- Produces: `charging_sessions.start_battery_pct` (SMALLINT NOT NULL), `charging_sessions.auto_stop_pct` (SMALLINT, nullable) — consumed by all later backend tasks.

- [ ] **Step 1: Add the columns to the `CREATE TABLE` definition (for fresh databases)**

In `backend/db/schema.sql`, find the `charging_sessions` table definition:

```sql
-- Charging sessions (live / historical)
CREATE TABLE IF NOT EXISTS charging_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    booking_id UUID REFERENCES bookings(id),
    station_id UUID NOT NULL REFERENCES stations(id),
    connector_id UUID NOT NULL REFERENCES connectors(id),
    vehicle_id UUID REFERENCES vehicles(id),
    status VARCHAR(20) NOT NULL DEFAULT 'active', -- active, completed, stopped, error
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    stopped_at TIMESTAMPTZ,
    energy_kwh NUMERIC(8,3) NOT NULL DEFAULT 0,
    cost NUMERIC(10,2) NOT NULL DEFAULT 0
);
```

Replace it with:

```sql
-- Charging sessions (live / historical)
CREATE TABLE IF NOT EXISTS charging_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    booking_id UUID REFERENCES bookings(id),
    station_id UUID NOT NULL REFERENCES stations(id),
    connector_id UUID NOT NULL REFERENCES connectors(id),
    vehicle_id UUID REFERENCES vehicles(id),
    status VARCHAR(20) NOT NULL DEFAULT 'active', -- active, completed, stopped, error
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    stopped_at TIMESTAMPTZ,
    energy_kwh NUMERIC(8,3) NOT NULL DEFAULT 0,
    cost NUMERIC(10,2) NOT NULL DEFAULT 0,
    start_battery_pct SMALLINT NOT NULL DEFAULT 20,
    auto_stop_pct SMALLINT
);

-- Idempotent for databases that already had charging_sessions before this
-- column existed (ADD COLUMN IF NOT EXISTS is a safe no-op on fresh installs
-- where CREATE TABLE just created them).
ALTER TABLE charging_sessions ADD COLUMN IF NOT EXISTS start_battery_pct SMALLINT NOT NULL DEFAULT 20;
ALTER TABLE charging_sessions ADD COLUMN IF NOT EXISTS auto_stop_pct SMALLINT;
```

- [ ] **Step 2: Apply the schema change to the existing database — WITHOUT re-running the seed**

The project's `backend/db/migrate.js` runs both `schema.sql` and `seed.sql`. `seed.sql`'s station insert uses `ON CONFLICT DO NOTHING` but `stations.name` has no unique constraint backing it — so re-running the full migrate script would silently duplicate every station and connector row. Apply **only** the schema file:

Run (from `backend/`):
```bash
node -e "require('dotenv').config(); const { pool } = require('./db/pool'); const fs = require('fs'); pool.query(fs.readFileSync('./db/schema.sql', 'utf8')).then(() => { console.log('schema applied'); return pool.end(); }).catch((e) => { console.error(e); process.exit(1); });"
```

Expected output: `schema applied`

- [ ] **Step 3: Verify the columns exist**

Run (from `backend/`):
```bash
node -e "require('dotenv').config(); const { pool } = require('./db/pool'); pool.query(\"SELECT column_name FROM information_schema.columns WHERE table_name='charging_sessions' AND column_name IN ('start_battery_pct','auto_stop_pct')\").then(r => { console.log(r.rows); return pool.end(); });"
```

Expected output: both `start_battery_pct` and `auto_stop_pct` listed.

- [ ] **Step 4: Commit**

```bash
git add backend/db/schema.sql
git commit -m "Add battery columns to charging_sessions schema"
```

---

### Task 2: Battery simulation utility + tests

**Files:**
- Create: `backend/utils/batterySimulation.js`
- Test: `backend/utils/batterySimulation.test.js`

**Interfaces:**
- Produces:
  - `BATTERY_CAPACITY_KWH: number` (40)
  - `ALLOWED_AUTO_STOP_PCTS: number[]` (`[10,20,...,100]`)
  - `randomStartBatteryPct(): number` — integer 15–55 inclusive
  - `computeBatteryPct(startBatteryPct: number, energyKwh: number): number` — capped at 100
  - `isValidAutoStopPct(value: number): boolean`
  - Consumed by: Tasks 4, 5, 6, 7 (backend routes)

- [ ] **Step 1: Write the failing tests**

Create `backend/utils/batterySimulation.test.js`:

```js
const {
  computeBatteryPct,
  randomStartBatteryPct,
  isValidAutoStopPct,
  ALLOWED_AUTO_STOP_PCTS,
} = require('./batterySimulation');

describe('randomStartBatteryPct', () => {
  it('returns an integer between 15 and 55 inclusive', () => {
    for (let i = 0; i < 200; i++) {
      const v = randomStartBatteryPct();
      expect(Number.isInteger(v)).toBe(true);
      expect(v).toBeGreaterThanOrEqual(15);
      expect(v).toBeLessThanOrEqual(55);
    }
  });
});

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

describe('isValidAutoStopPct', () => {
  it('accepts multiples of 10 from 10 to 100', () => {
    for (const v of ALLOWED_AUTO_STOP_PCTS) {
      expect(isValidAutoStopPct(v)).toBe(true);
    }
  });

  it('rejects values not in the allowed set', () => {
    expect(isValidAutoStopPct(15)).toBe(false);
    expect(isValidAutoStopPct(0)).toBe(false);
    expect(isValidAutoStopPct(105)).toBe(false);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `backend/`): `npx jest utils/batterySimulation.test.js`
Expected: FAIL with "Cannot find module './batterySimulation'"

- [ ] **Step 3: Write the implementation**

Create `backend/utils/batterySimulation.js`:

```js
const crypto = require('crypto');

const BATTERY_CAPACITY_KWH = 40;
const ALLOWED_AUTO_STOP_PCTS = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];

function randomStartBatteryPct() {
  return crypto.randomInt(15, 56); // 15–55 inclusive (upper bound is exclusive)
}

function computeBatteryPct(startBatteryPct, energyKwh) {
  const pct = Number(startBatteryPct) + (Number(energyKwh) / BATTERY_CAPACITY_KWH) * 100;
  return Math.min(100, pct);
}

function isValidAutoStopPct(value) {
  return ALLOWED_AUTO_STOP_PCTS.includes(value);
}

module.exports = {
  BATTERY_CAPACITY_KWH,
  ALLOWED_AUTO_STOP_PCTS,
  randomStartBatteryPct,
  computeBatteryPct,
  isValidAutoStopPct,
};
```

- [ ] **Step 4: Run tests to verify they pass**

Run (from `backend/`): `npx jest utils/batterySimulation.test.js`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/utils/batterySimulation.js backend/utils/batterySimulation.test.js
git commit -m "Add battery simulation utility with tests"
```

---

### Task 3: Session finalize helper + tests

**Files:**
- Create: `backend/utils/sessionFinalize.js`
- Test: `backend/utils/sessionFinalize.test.js`

**Interfaces:**
- Consumes: none (takes a `pool`-like object with `.connect()`)
- Produces: `finalizeSession(pool, { sessionId, userId, connectorId, energyKwh, cost }): Promise<{ ok: true, session: object } | { ok: false, error: string, cost: number, balance: number }>` — consumed by Tasks 5 and 6.

This extracts the transaction currently inline in `POST /api/sessions/:id/stop` (deduct wallet, mark session completed, free the connector, insert a wallet transaction) so it can be reused by both the manual-stop route and the auto-stop path.

- [ ] **Step 1: Write the failing tests**

Create `backend/utils/sessionFinalize.test.js`:

```js
const { finalizeSession } = require('./sessionFinalize');

function makeClient(balance) {
  const query = jest.fn((sql) => {
    if (sql.startsWith('BEGIN') || sql.startsWith('COMMIT') || sql.startsWith('ROLLBACK')) {
      return Promise.resolve({});
    }
    if (sql.includes('SELECT wallet_balance')) {
      return Promise.resolve({ rows: [{ wallet_balance: balance }] });
    }
    if (sql.includes('UPDATE charging_sessions')) {
      return Promise.resolve({
        rows: [{ id: 's1', status: 'completed', energy_kwh: '10.000', cost: '150.00' }],
      });
    }
    return Promise.resolve({ rows: [] });
  });
  return { query, release: jest.fn() };
}

describe('finalizeSession', () => {
  it('rolls back and returns ok:false when balance is insufficient', async () => {
    const client = makeClient(50);
    const pool = { connect: jest.fn().mockResolvedValue(client) };

    const result = await finalizeSession(pool, {
      sessionId: 's1',
      userId: 'u1',
      connectorId: 'c1',
      energyKwh: 10,
      cost: 150,
    });

    expect(result.ok).toBe(false);
    expect(result.error).toMatch(/insufficient/i);
    expect(result.balance).toBe(50);
    expect(client.query).toHaveBeenCalledWith('ROLLBACK');
    expect(client.release).toHaveBeenCalled();
  });

  it('commits and returns the completed session when balance is sufficient', async () => {
    const client = makeClient(500);
    const pool = { connect: jest.fn().mockResolvedValue(client) };

    const result = await finalizeSession(pool, {
      sessionId: 's1',
      userId: 'u1',
      connectorId: 'c1',
      energyKwh: 10,
      cost: 150,
    });

    expect(result.ok).toBe(true);
    expect(result.session.status).toBe('completed');
    expect(client.query).toHaveBeenCalledWith('COMMIT');
    expect(client.release).toHaveBeenCalled();
  });

  it('releases the client even when a query throws', async () => {
    const client = makeClient(500);
    client.query.mockImplementationOnce(() => Promise.resolve({})); // BEGIN
    client.query.mockImplementationOnce(() => Promise.reject(new Error('boom'))); // SELECT wallet_balance
    const pool = { connect: jest.fn().mockResolvedValue(client) };

    await expect(
      finalizeSession(pool, { sessionId: 's1', userId: 'u1', connectorId: 'c1', energyKwh: 10, cost: 150 })
    ).rejects.toThrow('boom');
    expect(client.release).toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from `backend/`): `npx jest utils/sessionFinalize.test.js`
Expected: FAIL with "Cannot find module './sessionFinalize'"

- [ ] **Step 3: Write the implementation**

Create `backend/utils/sessionFinalize.js`:

```js
async function finalizeSession(pool, { sessionId, userId, connectorId, energyKwh, cost }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const balanceResult = await client.query('SELECT wallet_balance FROM users WHERE id = $1 FOR UPDATE', [
      userId,
    ]);
    const balance = Number(balanceResult.rows[0].wallet_balance);
    if (balance < cost) {
      await client.query('ROLLBACK');
      return { ok: false, error: 'Insufficient wallet balance. Please top up.', cost, balance };
    }

    const updatedSession = await client.query(
      `UPDATE charging_sessions
       SET status = 'completed', stopped_at = now(), energy_kwh = $1, cost = $2
       WHERE id = $3 RETURNING *`,
      [energyKwh.toFixed(3), cost, sessionId]
    );

    await client.query('UPDATE users SET wallet_balance = wallet_balance - $1, updated_at = now() WHERE id = $2', [
      cost,
      userId,
    ]);

    await client.query(
      `INSERT INTO wallet_transactions (user_id, type, amount, reference, session_id)
       VALUES ($1, 'charge_debit', $2, 'charging_session', $3)`,
      [userId, cost, sessionId]
    );

    await client.query("UPDATE connectors SET status = 'available' WHERE id = $1", [connectorId]);

    await client.query('COMMIT');
    return { ok: true, session: updatedSession.rows[0] };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { finalizeSession };
```

- [ ] **Step 4: Run tests to verify they pass**

Run (from `backend/`): `npx jest utils/sessionFinalize.test.js`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/utils/sessionFinalize.js backend/utils/sessionFinalize.test.js
git commit -m "Extract session finalize transaction into shared helper with tests"
```

---

### Task 4: `formatSession` + `POST /api/sessions/start` — assign battery, validate Auto Stop

**Files:**
- Modify: `backend/routes/sessions.js`

**Interfaces:**
- Consumes: `computeBatteryPct`, `randomStartBatteryPct`, `isValidAutoStopPct` from `../utils/batterySimulation` (Task 2)
- Produces: `formatSession(row, connector?)` now includes `batteryPct`, `startBatteryPct`, `autoStopPct` on every response that uses it (start, stop, history) — consumed by Tasks 6 and frontend Task 9.

- [ ] **Step 1: Import the battery utility**

In `backend/routes/sessions.js`, add to the top of the file (after the existing `require`s):

```js
const { computeBatteryPct, randomStartBatteryPct, isValidAutoStopPct } = require('../utils/batterySimulation');
```

- [ ] **Step 2: Validate and assign battery fields in `POST /start`**

Find:

```js
router.post('/start', asyncHandler(async (req, res) => {
  const { stationId, connectorId, vehicleId, bookingId } = req.body;

  if (!stationId || !connectorId) {
    return res.status(400).json({ error: 'stationId and connectorId are required' });
  }
```

Replace with:

```js
router.post('/start', asyncHandler(async (req, res) => {
  const { stationId, connectorId, vehicleId, bookingId, autoStopPct } = req.body;

  if (!stationId || !connectorId) {
    return res.status(400).json({ error: 'stationId and connectorId are required' });
  }

  let normalizedAutoStopPct = null;
  if (autoStopPct !== undefined && autoStopPct !== null) {
    normalizedAutoStopPct = Number(autoStopPct);
    if (!isValidAutoStopPct(normalizedAutoStopPct)) {
      return res.status(400).json({ error: 'autoStopPct must be one of 10, 20, ..., 100' });
    }
  }
```

- [ ] **Step 3: Include the new columns in the INSERT**

Find:

```js
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const session = await client.query(
      `INSERT INTO charging_sessions (user_id, booking_id, station_id, connector_id, vehicle_id, status)
       VALUES ($1, $2, $3, $4, $5, 'active') RETURNING *`,
      [req.user.id, bookingId || null, stationId, connectorId, vehicleId || null]
    );
```

Replace with:

```js
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const session = await client.query(
      `INSERT INTO charging_sessions
         (user_id, booking_id, station_id, connector_id, vehicle_id, status, start_battery_pct, auto_stop_pct)
       VALUES ($1, $2, $3, $4, $5, 'active', $6, $7) RETURNING *`,
      [req.user.id, bookingId || null, stationId, connectorId, vehicleId || null, randomStartBatteryPct(), normalizedAutoStopPct]
    );
```

- [ ] **Step 4: Extend `formatSession` to include battery fields**

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
    batteryPct: Number(computeBatteryPct(row.start_battery_pct, row.energy_kwh).toFixed(1)),
    startBatteryPct: row.start_battery_pct,
    autoStopPct: row.auto_stop_pct,
  };
}
```

(`GET /history` already calls `formatSession(r)` for every row, so it inherits these three fields automatically — no separate change needed there.)

- [ ] **Step 5: Verify with the running backend**

If the backend isn't already running, start it (from `backend/`): `node server.js`

Get a fresh token (replace phone/code with a real OTP round-trip, or reuse a valid one from the backend log), then:

```bash
TOKEN="<paste a valid JWT here>"
curl -s -X POST http://localhost:4000/api/sessions/start \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"stationId":"<a real station id>","connectorId":"<a real available connector id>","autoStopPct":80}'
```

Expected: `201` with a `session` object containing `batteryPct` (a number between 15 and 55), `startBatteryPct` (same value), `autoStopPct: 80`.

Then try an invalid value:
```bash
curl -s -X POST http://localhost:4000/api/sessions/start \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"stationId":"<id>","connectorId":"<id>","autoStopPct":45}'
```
Expected: `400` with `"autoStopPct must be one of 10, 20, ..., 100"`.

- [ ] **Step 6: Commit**

```bash
git add backend/routes/sessions.js
git commit -m "Assign random start battery and validate Auto Stop target on session start"
```

---

### Task 5: `GET /api/sessions/active` — live battery % and auto-stop trigger

**Files:**
- Modify: `backend/routes/sessions.js`

**Interfaces:**
- Consumes: `finalizeSession` from `../utils/sessionFinalize` (Task 3), `computeBatteryPct` from `../utils/batterySimulation` (Task 2)
- Produces: response shape `{ session: {...} | null, autoStopped?: true }` — consumed by frontend Task 10.

- [ ] **Step 1: Import `finalizeSession`**

In `backend/routes/sessions.js`, add:

```js
const { finalizeSession } = require('../utils/sessionFinalize');
```

- [ ] **Step 2: Compute battery % and trigger auto-stop before responding**

Find:

```js
router.get('/active', asyncHandler(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT cs.*, c.power_kw, c.price_per_kwh, s.name AS station_name
     FROM charging_sessions cs
     JOIN connectors c ON c.id = cs.connector_id
     JOIN stations s ON s.id = cs.station_id
     WHERE cs.user_id = $1 AND cs.status = 'active'
     LIMIT 1`,
    [req.user.id]
  );

  if (rows.length === 0) {
    return res.json({ session: null });
  }

  const row = rows[0];
  // Simulate live energy delivered based on elapsed time * connector power.
  const elapsedHours = (Date.now() - new Date(row.started_at).getTime()) / 3600000;
  const energyKwh = Math.min(elapsedHours * Number(row.power_kw), 100); // cap for demo
  const cost = energyKwh * Number(row.price_per_kwh);

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
    },
  });
}));
```

Replace with:

```js
router.get('/active', asyncHandler(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT cs.*, c.power_kw, c.price_per_kwh, s.name AS station_name
     FROM charging_sessions cs
     JOIN connectors c ON c.id = cs.connector_id
     JOIN stations s ON s.id = cs.station_id
     WHERE cs.user_id = $1 AND cs.status = 'active'
     LIMIT 1`,
    [req.user.id]
  );

  if (rows.length === 0) {
    return res.json({ session: null });
  }

  const row = rows[0];
  // Simulate live energy delivered based on elapsed time * connector power.
  const elapsedHours = (Date.now() - new Date(row.started_at).getTime()) / 3600000;
  const energyKwh = Math.min(elapsedHours * Number(row.power_kw), 100); // cap for demo
  const cost = energyKwh * Number(row.price_per_kwh);
  const batteryPct = computeBatteryPct(row.start_battery_pct, energyKwh);

  // auto_stop_pct of null means "charge to 100%" — treat it the same as an
  // explicit target of 100 so every session eventually completes.
  const targetPct = row.auto_stop_pct ?? 100;
  if (batteryPct >= targetPct) {
    const result = await finalizeSession(pool, {
      sessionId: row.id,
      userId: req.user.id,
      connectorId: row.connector_id,
      energyKwh,
      cost: Number(cost.toFixed(2)),
    });
    if (result.ok) {
      return res.json({ session: formatSession(result.session), autoStopped: true });
    }
    // Insufficient balance to auto-charge: fall through and report the
    // still-active session rather than force-stopping without payment.
  }

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
    },
  });
}));
```

- [ ] **Step 3: Verify with the running backend**

Using the session started in Task 4's verification (with `autoStopPct: 80`), poll immediately:

```bash
curl -s http://localhost:4000/api/sessions/active -H "Authorization: Bearer $TOKEN"
```
Expected: `{"session": {..., "batteryPct": <close to startBatteryPct>, "autoStopPct": 80, "status": "active", ...}}` (no `autoStopped` key yet, since battery just started).

Now test the auto-stop trigger directly: start a **new** session with a low target so it fires immediately given the random 15–55 start range:
```bash
curl -s -X POST http://localhost:4000/api/sessions/start \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"stationId":"<id>","connectorId":"<a different available connector id>","autoStopPct":10}'
curl -s http://localhost:4000/api/sessions/active -H "Authorization: Bearer $TOKEN"
```
Expected: since `startBatteryPct` is always ≥15, the second `curl` response should show `"autoStopped": true` and `"session":{"status":"completed",...}` immediately (battery already exceeds the 10% target from the start).

Then confirm it's really gone from active:
```bash
curl -s http://localhost:4000/api/sessions/active -H "Authorization: Bearer $TOKEN"
```
Expected: `{"session": null}`

- [ ] **Step 4: Commit**

```bash
git add backend/routes/sessions.js
git commit -m "Compute live battery percentage and auto-stop sessions at their target"
```

---

### Task 6: `POST /api/sessions/:id/stop` — reuse the shared finalize helper

**Files:**
- Modify: `backend/routes/sessions.js`

**Interfaces:**
- Consumes: `finalizeSession` from Task 5's import (already added to the file)

- [ ] **Step 1: Replace the inline transaction with the shared helper**

Find:

```js
// POST /api/sessions/:id/stop
router.post('/:id/stop', asyncHandler(async (req, res) => {
  const sessionResult = await pool.query(
    `SELECT cs.*, c.power_kw, c.price_per_kwh
     FROM charging_sessions cs JOIN connectors c ON c.id = cs.connector_id
     WHERE cs.id = $1 AND cs.user_id = $2 AND cs.status = 'active'`,
    [req.params.id, req.user.id]
  );

  if (sessionResult.rows.length === 0) {
    return res.status(404).json({ error: 'Active session not found' });
  }

  const row = sessionResult.rows[0];
  const elapsedHours = (Date.now() - new Date(row.started_at).getTime()) / 3600000;
  const energyKwh = Math.min(elapsedHours * Number(row.power_kw), 100);
  const cost = Number((energyKwh * Number(row.price_per_kwh)).toFixed(2));

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const balanceResult = await client.query('SELECT wallet_balance FROM users WHERE id = $1 FOR UPDATE', [
      req.user.id,
    ]);
    const balance = Number(balanceResult.rows[0].wallet_balance);
    if (balance < cost) {
      await client.query('ROLLBACK');
      return res.status(402).json({ error: 'Insufficient wallet balance. Please top up.', cost, balance });
    }

    const updatedSession = await client.query(
      `UPDATE charging_sessions
       SET status = 'completed', stopped_at = now(), energy_kwh = $1, cost = $2
       WHERE id = $3 RETURNING *`,
      [energyKwh.toFixed(3), cost, row.id]
    );

    await client.query('UPDATE users SET wallet_balance = wallet_balance - $1, updated_at = now() WHERE id = $2', [
      cost,
      req.user.id,
    ]);

    await client.query(
      `INSERT INTO wallet_transactions (user_id, type, amount, reference, session_id)
       VALUES ($1, 'charge_debit', $2, 'charging_session', $3)`,
      [req.user.id, cost, row.id]
    );

    await client.query("UPDATE connectors SET status = 'available' WHERE id = $1", [row.connector_id]);

    await client.query('COMMIT');
    res.json({ session: formatSession(updatedSession.rows[0]) });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}));
```

Replace with:

```js
// POST /api/sessions/:id/stop
router.post('/:id/stop', asyncHandler(async (req, res) => {
  const sessionResult = await pool.query(
    `SELECT cs.*, c.power_kw, c.price_per_kwh
     FROM charging_sessions cs JOIN connectors c ON c.id = cs.connector_id
     WHERE cs.id = $1 AND cs.user_id = $2 AND cs.status = 'active'`,
    [req.params.id, req.user.id]
  );

  if (sessionResult.rows.length === 0) {
    return res.status(404).json({ error: 'Active session not found' });
  }

  const row = sessionResult.rows[0];
  const elapsedHours = (Date.now() - new Date(row.started_at).getTime()) / 3600000;
  const energyKwh = Math.min(elapsedHours * Number(row.power_kw), 100);
  const cost = Number((energyKwh * Number(row.price_per_kwh)).toFixed(2));

  const result = await finalizeSession(pool, {
    sessionId: row.id,
    userId: req.user.id,
    connectorId: row.connector_id,
    energyKwh,
    cost,
  });

  if (!result.ok) {
    return res.status(402).json({ error: result.error, cost: result.cost, balance: result.balance });
  }

  res.json({ session: formatSession(result.session) });
}));
```

- [ ] **Step 2: Verify with the running backend**

Start a fresh session, then stop it manually:
```bash
curl -s -X POST http://localhost:4000/api/sessions/start \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"stationId":"<id>","connectorId":"<id>"}'
```
Copy the returned `session.id`, then:
```bash
curl -s -X POST http://localhost:4000/api/sessions/<session-id>/stop -H "Authorization: Bearer $TOKEN"
```
Expected: `200` with `session.status: "completed"` and a `batteryPct` field present.

- [ ] **Step 3: Commit**

```bash
git add backend/routes/sessions.js
git commit -m "Reuse shared finalizeSession helper in manual stop route"
```

---

### Task 7: `PATCH /api/sessions/:id/auto-stop` — remote control of the target

**Files:**
- Modify: `backend/routes/sessions.js`

**Interfaces:**
- Consumes: `isValidAutoStopPct` from Task 4's import (already added to the file)
- Produces: `PATCH /api/sessions/:id/auto-stop` — consumed by frontend Task 8 (`ApiService.setAutoStop`).

- [ ] **Step 1: Add the new route**

In `backend/routes/sessions.js`, add this route directly after the `POST /:id/stop` route (before `GET /history`):

```js
// PATCH /api/sessions/:id/auto-stop { autoStopPct }
router.patch('/:id/auto-stop', asyncHandler(async (req, res) => {
  const { autoStopPct } = req.body;

  let normalizedAutoStopPct = null;
  if (autoStopPct !== undefined && autoStopPct !== null) {
    normalizedAutoStopPct = Number(autoStopPct);
    if (!isValidAutoStopPct(normalizedAutoStopPct)) {
      return res.status(400).json({ error: 'autoStopPct must be one of 10, 20, ..., 100' });
    }
  }

  const { rows } = await pool.query(
    `UPDATE charging_sessions SET auto_stop_pct = $1
     WHERE id = $2 AND user_id = $3 AND status = 'active'
     RETURNING *`,
    [normalizedAutoStopPct, req.params.id, req.user.id]
  );

  if (rows.length === 0) {
    return res.status(404).json({ error: 'Active session not found' });
  }

  res.json({ session: formatSession(rows[0]) });
}));
```

- [ ] **Step 2: Verify with the running backend**

Start a session, then update its target:
```bash
curl -s -X POST http://localhost:4000/api/sessions/start \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"stationId":"<id>","connectorId":"<id>","autoStopPct":100}'
```
Copy the `session.id`, then:
```bash
curl -s -X PATCH http://localhost:4000/api/sessions/<session-id>/auto-stop \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"autoStopPct":50}'
```
Expected: `200` with `session.autoStopPct: 50`.

Then confirm rejection of an invalid value:
```bash
curl -s -X PATCH http://localhost:4000/api/sessions/<session-id>/auto-stop \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"autoStopPct":33}'
```
Expected: `400`.

- [ ] **Step 3: Commit**

```bash
git add backend/routes/sessions.js
git commit -m "Add endpoint to update Auto Stop target on an active session"
```

---

### Task 8: Frontend — model and API client changes

**Files:**
- Modify: `frontend/lib/models/models.dart`
- Modify: `frontend/lib/services/api_service.dart`

**Interfaces:**
- Produces: `ChargingSession.batteryPct: double`, `.startBatteryPct: int`, `.autoStopPct: int?`; `ApiService.startSession(..., autoStopPct: int?)`; `ApiService.setAutoStop(String sessionId, int? autoStopPct): Future<Map<String, dynamic>>` — consumed by Tasks 9, 10, 11.

- [ ] **Step 1: Extend the `ChargingSession` model**

In `frontend/lib/models/models.dart`, find:

```dart
class ChargingSession {
  final String id;
  final String stationId;
  final String stationName;
  final String connectorId;
  final String status; // active, completed, stopped, error
  final DateTime startedAt;
  final DateTime? stoppedAt;
  final double energyKwh;
  final double cost;
  final double? powerKw;
  final double? pricePerKwh;

  ChargingSession({
    required this.id,
    required this.stationId,
    required this.stationName,
    required this.connectorId,
    required this.status,
    required this.startedAt,
    this.stoppedAt,
    required this.energyKwh,
    required this.cost,
    this.powerKw,
    this.pricePerKwh,
  });

  factory ChargingSession.fromJson(Map<String, dynamic> json) {
    return ChargingSession(
      id: json['id'],
      stationId: json['stationId'],
      stationName: json['stationName'] ?? '',
      connectorId: json['connectorId'],
      status: json['status'],
      startedAt: DateTime.parse(json['startedAt']),
      stoppedAt: json['stoppedAt'] != null ? DateTime.parse(json['stoppedAt']) : null,
      energyKwh: (json['energyKwh'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      powerKw: json['powerKw'] != null ? (json['powerKw'] as num).toDouble() : null,
      pricePerKwh: json['pricePerKwh'] != null ? (json['pricePerKwh'] as num).toDouble() : null,
    );
  }
}
```

Replace with:

```dart
class ChargingSession {
  final String id;
  final String stationId;
  final String stationName;
  final String connectorId;
  final String status; // active, completed, stopped, error
  final DateTime startedAt;
  final DateTime? stoppedAt;
  final double energyKwh;
  final double cost;
  final double? powerKw;
  final double? pricePerKwh;
  final double batteryPct;
  final int startBatteryPct;
  final int? autoStopPct;

  ChargingSession({
    required this.id,
    required this.stationId,
    required this.stationName,
    required this.connectorId,
    required this.status,
    required this.startedAt,
    this.stoppedAt,
    required this.energyKwh,
    required this.cost,
    this.powerKw,
    this.pricePerKwh,
    required this.batteryPct,
    required this.startBatteryPct,
    this.autoStopPct,
  });

  factory ChargingSession.fromJson(Map<String, dynamic> json) {
    return ChargingSession(
      id: json['id'],
      stationId: json['stationId'],
      stationName: json['stationName'] ?? '',
      connectorId: json['connectorId'],
      status: json['status'],
      startedAt: DateTime.parse(json['startedAt']),
      stoppedAt: json['stoppedAt'] != null ? DateTime.parse(json['stoppedAt']) : null,
      energyKwh: (json['energyKwh'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      powerKw: json['powerKw'] != null ? (json['powerKw'] as num).toDouble() : null,
      pricePerKwh: json['pricePerKwh'] != null ? (json['pricePerKwh'] as num).toDouble() : null,
      batteryPct: (json['batteryPct'] as num).toDouble(),
      startBatteryPct: json['startBatteryPct'] as int,
      autoStopPct: json['autoStopPct'] as int?,
    );
  }
}
```

- [ ] **Step 2: Extend `ApiService.startSession` and add `setAutoStop`**

In `frontend/lib/services/api_service.dart`, find:

```dart
  Future<Map<String, dynamic>> startSession({
    required String stationId,
    required String connectorId,
    String? vehicleId,
    String? bookingId,
  }) async {
    final res = await http.post(
      _uri('/api/sessions/start'),
      headers: await _headers(),
      body: jsonEncode({
        'stationId': stationId,
        'connectorId': connectorId,
        'vehicleId': vehicleId,
        'bookingId': bookingId,
      }),
    );
    return await _handle(res);
  }

  Future<Map<String, dynamic>> getActiveSession() async {
    final res = await http.get(_uri('/api/sessions/active'), headers: await _headers());
    return await _handle(res);
  }

  Future<Map<String, dynamic>> stopSession(String sessionId) async {
    final res = await http.post(_uri('/api/sessions/$sessionId/stop'), headers: await _headers());
    return await _handle(res);
  }
```

Replace with:

```dart
  Future<Map<String, dynamic>> startSession({
    required String stationId,
    required String connectorId,
    String? vehicleId,
    String? bookingId,
    int? autoStopPct,
  }) async {
    final res = await http.post(
      _uri('/api/sessions/start'),
      headers: await _headers(),
      body: jsonEncode({
        'stationId': stationId,
        'connectorId': connectorId,
        'vehicleId': vehicleId,
        'bookingId': bookingId,
        'autoStopPct': autoStopPct,
      }),
    );
    return await _handle(res);
  }

  Future<Map<String, dynamic>> getActiveSession() async {
    final res = await http.get(_uri('/api/sessions/active'), headers: await _headers());
    return await _handle(res);
  }

  Future<Map<String, dynamic>> stopSession(String sessionId) async {
    final res = await http.post(_uri('/api/sessions/$sessionId/stop'), headers: await _headers());
    return await _handle(res);
  }

  Future<Map<String, dynamic>> setAutoStop(String sessionId, int? autoStopPct) async {
    final res = await http.patch(
      _uri('/api/sessions/$sessionId/auto-stop'),
      headers: await _headers(),
      body: jsonEncode({'autoStopPct': autoStopPct}),
    );
    return await _handle(res);
  }
```

- [ ] **Step 3: Verify the app still compiles**

Run (from `frontend/`): `flutter analyze`
Expected: no errors referencing `models.dart` or `api_service.dart` (there will still be errors/warnings in files not yet updated to construct `ChargingSession` with the new required fields — those are resolved by later tasks in this plan; confirm no *new* errors appear in the two files just changed).

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/models/models.dart frontend/lib/services/api_service.dart
git commit -m "Add battery/auto-stop fields to ChargingSession model and API client"
```

---

### Task 9: Frontend — `SessionProvider` auto-stop detection and control

**Files:**
- Modify: `frontend/lib/providers/session_provider.dart`

**Interfaces:**
- Consumes: `ApiService.setAutoStop` (Task 8)
- Produces: `SessionProvider.autoStopMessage: String?`, `SessionProvider.clearAutoStopMessage(): void`, `SessionProvider.updateAutoStop(int? autoStopPct): Future<bool>` — consumed by Task 11.

- [ ] **Step 1: Replace the file with the extended provider**

Read the current file first (`frontend/lib/providers/session_provider.dart`) to confirm no other in-flight edits, then replace its full contents with:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class SessionProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  ChargingSession? activeSession;
  bool isLoading = false;
  String? error;
  Timer? _pollTimer;

  // Set for exactly one refresh cycle when a poll discovers the session was
  // auto-stopped (battery reached its target). The active-session screen
  // consumes this once (via a listener) then calls clearAutoStopMessage().
  String? autoStopMessage;

  Future<void> refreshActiveSession() async {
    try {
      final data = await _api.getActiveSession();
      final autoStopped = data['autoStopped'] == true;
      if (autoStopped) {
        final session = data['session'] != null ? ChargingSession.fromJson(data['session']) : null;
        final pct = session?.batteryPct.toStringAsFixed(0) ?? '100';
        autoStopMessage = '🔋 Auto-stopped at $pct% — charged to your target!';
        activeSession = null;
        stopPolling();
      } else {
        activeSession = data['session'] != null ? ChargingSession.fromJson(data['session']) : null;
      }
      notifyListeners();
    } catch (e) {
      error = e.toString();
    }
  }

  void clearAutoStopMessage() {
    autoStopMessage = null;
  }

  void startPolling() {
    _pollTimer?.cancel();
    refreshActiveSession();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => refreshActiveSession());
  }

  void stopPolling() {
    _pollTimer?.cancel();
  }

  Future<bool> startCharging({
    required String stationId,
    required String connectorId,
    String? vehicleId,
    String? bookingId,
    int? autoStopPct,
  }) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final data = await _api.startSession(
        stationId: stationId,
        connectorId: connectorId,
        vehicleId: vehicleId,
        bookingId: bookingId,
        autoStopPct: autoStopPct,
      );
      activeSession = ChargingSession.fromJson(data['session']);
      startPolling();
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> stopCharging() async {
    if (activeSession == null) return false;
    isLoading = true;
    notifyListeners();
    try {
      await _api.stopSession(activeSession!.id);
      activeSession = null;
      stopPolling();
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateAutoStop(int? autoStopPct) async {
    if (activeSession == null) return false;
    try {
      final data = await _api.setAutoStop(activeSession!.id, autoStopPct);
      activeSession = ChargingSession.fromJson(data['session']);
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 2: Verify the app still compiles**

Run (from `frontend/`): `flutter analyze`
Expected: no new errors in `session_provider.dart`.

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/providers/session_provider.dart
git commit -m "Detect auto-stopped sessions in SessionProvider and expose updateAutoStop"
```

---

### Task 10: Frontend — Auto Stop selection sheet when starting a session

**Files:**
- Modify: `frontend/lib/screens/station/station_detail_screen.dart`

**Interfaces:**
- Consumes: `SessionProvider.startCharging(..., autoStopPct: int?)` (Task 9)

- [ ] **Step 1: Add imports for slider state**

In `frontend/lib/screens/station/station_detail_screen.dart`, the file already imports `package:flutter/material.dart` and `../../widgets/aero/glass_panel.dart` — no new imports needed.

- [ ] **Step 2: Insert an Auto Stop sheet before starting the session**

Find:

```dart
  Future<void> _startChargingNow(BuildContext context, Station station, Connector connector) async {
    final sessionProvider = context.read<SessionProvider>();
    final ok = await sessionProvider.startCharging(
      stationId: station.id,
      connectorId: connector.id,
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

- [ ] **Step 3: Verify the app still compiles**

Run (from `frontend/`): `flutter analyze`
Expected: no new errors in `station_detail_screen.dart`.

- [ ] **Step 4: Commit**

```bash
git add frontend/lib/screens/station/station_detail_screen.dart
git commit -m "Add Auto Stop target selection sheet before starting a charging session"
```

---

### Task 11: Frontend — battery ring, live Auto Stop control, and auto-stop reaction

**Files:**
- Modify: `frontend/lib/screens/session/active_session_screen.dart`

**Interfaces:**
- Consumes: `SessionProvider.autoStopMessage`, `.clearAutoStopMessage()`, `.updateAutoStop()` (Task 9); `ChargingSession.batteryPct`, `.autoStopPct` (Task 8)

- [ ] **Step 1: Import the `ChargingSession` model**

The new `_AutoStopControl` widget added in Step 4 below explicitly types a field as `ChargingSession`. The file currently only uses `session.foo` via type inference (through `SessionProvider`) and never names the type directly, so it has no import for `models.dart` yet. Add one.

Find the imports at the top of `frontend/lib/screens/session/active_session_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/session_provider.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../home/home_shell.dart';
```

Replace with:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../widgets/aero/glass_panel.dart';
import '../../widgets/aero/energy_orb_button.dart';
import '../home/home_shell.dart';
```

- [ ] **Step 2: React to auto-stop via a provider listener**

Find:

```dart
class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  @override
  void initState() {
    super.initState();
    context.read<SessionProvider>().startPolling();
  }

  @override
  void dispose() {
    context.read<SessionProvider>().stopPolling();
    super.dispose();
  }
```

Replace with:

```dart
class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<SessionProvider>();
    provider.startPolling();
    provider.addListener(_onProviderChange);
  }

  @override
  void dispose() {
    final provider = context.read<SessionProvider>();
    provider.removeListener(_onProviderChange);
    provider.stopPolling();
    super.dispose();
  }

  void _onProviderChange() {
    final provider = context.read<SessionProvider>();
    if (provider.activeSession == null && provider.autoStopMessage != null) {
      final message = provider.autoStopMessage!;
      provider.clearAutoStopMessage();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
```

- [ ] **Step 3: Show battery % on the progress ring instead of the hardcoded `/40` guess**

Find:

```dart
    final progress = (session.energyKwh / 40).clamp(0.0, 1.0); // visual progress toward ~40kWh full charge
```

Replace with:

```dart
    final progress = (session.batteryPct / 100).clamp(0.0, 1.0);
```

Find:

```dart
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt_rounded, color: Colors.white, size: 32),
                        const SizedBox(height: 6),
                        Text('${session.energyKwh.toStringAsFixed(1)} kWh',
                            style: GoogleFonts.baloo2(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                        Text('delivered', style: GoogleFonts.nunitoSans(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
```

Replace with:

```dart
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.battery_charging_full_rounded, color: Colors.white, size: 32),
                        const SizedBox(height: 6),
                        Text('${session.batteryPct.toStringAsFixed(0)}%',
                            style: GoogleFonts.baloo2(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                        Text('battery', style: GoogleFonts.nunitoSans(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
```

- [ ] **Step 4: Add a live Auto Stop control below the stat cards**

Find:

```dart
                      Row(
                        children: [
                          Expanded(
                            child: _statCard('Power', '${session.powerKw?.toStringAsFixed(0) ?? '-'} kW', Icons.flash_on_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard('Cost so far', '₹${session.cost.toStringAsFixed(0)}', Icons.currency_rupee_rounded),
                          ),
                        ],
                      ),
                      const Spacer(),
```

Replace with:

```dart
                      Row(
                        children: [
                          Expanded(
                            child: _statCard('Power', '${session.powerKw?.toStringAsFixed(0) ?? '-'} kW', Icons.flash_on_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard('Cost so far', '₹${session.cost.toStringAsFixed(0)}', Icons.currency_rupee_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _AutoStopControl(session: session),
                      const Spacer(),
```

- [ ] **Step 5: Add the `_AutoStopControl` widget**

`_AutoStopControl` is a new top-level widget, not a method on `_ActiveSessionScreenState` — it must go outside that class, after its final closing `}`. At the very end of `frontend/lib/screens/session/active_session_screen.dart` (after the closing `}` of the `_statCard` method, which is the last member of `_ActiveSessionScreenState`), append:

```dart

class _AutoStopControl extends StatefulWidget {
  final ChargingSession session;
  const _AutoStopControl({required this.session});

  @override
  State<_AutoStopControl> createState() => _AutoStopControlState();
}

class _AutoStopControlState extends State<_AutoStopControl> {
  late int _selected = widget.session.autoStopPct ?? 100;

  @override
  void didUpdateWidget(covariant _AutoStopControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep in sync if another source (e.g. a fresh poll) changed the target.
    final serverValue = widget.session.autoStopPct ?? 100;
    if (serverValue != _selected) _selected = serverValue;
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_circle_rounded, color: AppColors.skyBlue, size: 20),
              const SizedBox(width: 8),
              Text('Auto Stop at $_selected%',
                  style: GoogleFonts.nunitoSans(fontWeight: FontWeight.w700, color: AppColors.deepAzure)),
            ],
          ),
          Slider(
            value: _selected.toDouble(),
            min: 10,
            max: 100,
            divisions: 9,
            activeColor: AppColors.skyBlue,
            label: '$_selected%',
            onChanged: (v) => setState(() => _selected = v.round()),
            onChangeEnd: (v) {
              final pct = v.round();
              context.read<SessionProvider>().updateAutoStop(pct == 100 ? null : pct);
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Verify the app compiles**

Run (from `frontend/`): `flutter analyze`
Expected: no errors in `active_session_screen.dart`.

- [ ] **Step 7: Commit**

```bash
git add frontend/lib/screens/session/active_session_screen.dart
git commit -m "Show live battery percentage and Auto Stop control on active session screen"
```

---

### Task 12: End-to-end verification on device

**Files:** none (verification only)

- [ ] **Step 1: Rebuild and relaunch the app**

With the phone connected via USB and `adb reverse tcp:4000 tcp:4000` still active (re-run it if the phone was unplugged: `adb reverse tcp:4000 tcp:4000`), relaunch from Android Studio (Stop, then Run ▶) so the app picks up all the new code.

- [ ] **Step 2: Walk through the full flow manually**

1. Log in (OTP flow).
2. Go to a station, tap "Charge now" — confirm the Auto Stop sheet appears with a slider snapping to 10/20/.../100, defaulting to 100%.
3. Pick a low value (e.g. 20%) and start charging.
4. On the active session screen, confirm:
   - The ring shows a battery percentage (not kWh).
   - An "Auto Stop at 20%" slider is visible and draggable.
5. Since the simulated starting battery is always ≥15%, within a few polls (≤5s each) the session should auto-stop — confirm you're returned to the home screen with a "🔋 Auto-stopped at X% — charged to your target!" message, and that your wallet balance decreased accordingly (check the Wallet screen).
6. Start another session, this time leave Auto Stop at 100%, and manually tap "Stop charging" partway through — confirm the manual-stop flow still works exactly as before.
7. Check History → Charging sessions — confirm the completed sessions appear (no code change needed here since `formatSession` is shared, but worth confirming visually).

- [ ] **Step 3: Report results**

No commit for this task — it's manual verification of everything committed in Tasks 1–11.
