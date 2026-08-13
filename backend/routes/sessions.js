const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { checkVehicleConnectorCompatible } = require('../utils/vehicleCompat');
const { asyncHandler } = require('../middleware/asyncHandler');

const router = express.Router();
router.use(requireAuth);

// POST /api/sessions/start { stationId, connectorId, vehicleId, bookingId? }
router.post('/start', asyncHandler(async (req, res) => {
  const { stationId, connectorId, vehicleId, bookingId } = req.body;

  if (!stationId || !connectorId) {
    return res.status(400).json({ error: 'stationId and connectorId are required' });
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
      `INSERT INTO charging_sessions (user_id, booking_id, station_id, connector_id, vehicle_id, status)
       VALUES ($1, $2, $3, $4, $5, 'active') RETURNING *`,
      [req.user.id, bookingId || null, stationId, connectorId, vehicleId || null]
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
  };
}

module.exports = router;
