const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { checkVehicleConnectorCompatible } = require('../utils/vehicleCompat');
const { asyncHandler } = require('../middleware/asyncHandler');
const { computeBatteryPct, randomStartBatteryPct, isValidAutoStopPct } = require('../utils/batterySimulation');
const { finalizeSession } = require('../utils/sessionFinalize');

const router = express.Router();
router.use(requireAuth);

// POST /api/sessions/start { stationId, connectorId, vehicleId, bookingId? }
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

  const connector = await pool.query('SELECT * FROM connectors WHERE id = $1 AND station_id = $2', [
    connectorId,
    stationId,
  ]);
  if (connector.rows.length === 0) {
    return res.status(404).json({ error: 'Connector not found' });
  }
  if (connector.rows[0].status !== 'available') {
    return res.status(409).json({ error: 'Connector is not available right now' });
  }

  const compat = await checkVehicleConnectorCompatible(pool, {
    vehicleId: vehicleId || null,
    userId: req.user.id,
    connectorType: connector.rows[0].connector_type,
  });
  if (!compat.ok) {
    return res.status(compat.error === 'Vehicle not found' ? 404 : 409).json({ error: compat.error });
  }

  const existingActive = await pool.query(
    "SELECT id FROM charging_sessions WHERE user_id = $1 AND status = 'active'",
    [req.user.id]
  );
  if (existingActive.rows.length > 0) {
    return res.status(409).json({ error: 'You already have an active charging session' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const session = await client.query(
      `INSERT INTO charging_sessions
         (user_id, booking_id, station_id, connector_id, vehicle_id, status, start_battery_pct, auto_stop_pct)
       VALUES ($1, $2, $3, $4, $5, 'active', $6, $7) RETURNING *`,
      [req.user.id, bookingId || null, stationId, connectorId, vehicleId || null, randomStartBatteryPct(), normalizedAutoStopPct]
    );
    await client.query("UPDATE connectors SET status = 'occupied' WHERE id = $1", [connectorId]);
    await client.query('COMMIT');
    res.status(201).json({ session: formatSession(session.rows[0], connector.rows[0]) });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}));

// GET /api/sessions/active
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

// GET /api/sessions/history
router.get('/history', asyncHandler(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT cs.*, s.name AS station_name
     FROM charging_sessions cs JOIN stations s ON s.id = cs.station_id
     WHERE cs.user_id = $1 AND cs.status != 'active'
     ORDER BY cs.started_at DESC LIMIT 50`,
    [req.user.id]
  );
  res.json({ sessions: rows.map((r) => formatSession(r)) });
}));

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

module.exports = router;
