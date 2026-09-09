const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');
const { normalizePosition, PositionError } = require('../utils/trackerPosition');

const router = express.Router();

// POST /api/tracker/ingest  — called by the position feeder / (later) the
// EL-440 TCP decoder. Guarded by a shared key rather than a user JWT, since
// the caller is a device pipeline, not a logged-in person.
router.post('/ingest', asyncHandler(async (req, res) => {
  const expected = process.env.TRACKER_INGEST_KEY;
  if (!expected) {
    return res.status(503).json({ error: 'Tracker ingest is not configured' });
  }
  if (req.get('x-ingest-key') !== expected) {
    return res.status(401).json({ error: 'Invalid ingest key' });
  }

  let position;
  try {
    position = normalizePosition(req.body);
  } catch (err) {
    if (err instanceof PositionError) {
      return res.status(400).json({ error: err.message });
    }
    throw err;
  }

  const { rows } = await pool.query(
    `INSERT INTO device_positions (device_id, lat, lng, speed_kph, heading_deg, recorded_at, raw)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING id, received_at`,
    [
      position.deviceId,
      position.lat,
      position.lng,
      position.speedKph,
      position.headingDeg,
      position.recordedAt,
      position.raw ? JSON.stringify(position.raw) : null,
    ]
  );

  res.status(201).json({ id: rows[0].id, receivedAt: rows[0].received_at });
}));

// GET /api/tracker/:deviceId/latest  — most recent fix for a device.
router.get('/:deviceId/latest', requireAuth, asyncHandler(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT device_id, lat, lng, speed_kph, heading_deg, recorded_at, received_at
     FROM device_positions
     WHERE device_id = $1
     ORDER BY recorded_at DESC
     LIMIT 1`,
    [req.params.deviceId]
  );

  if (rows.length === 0) {
    return res.status(404).json({ error: 'No positions for this device yet' });
  }

  res.json({ position: formatPosition(rows[0]) });
}));

function formatPosition(row) {
  return {
    deviceId: row.device_id,
    lat: row.lat,
    lng: row.lng,
    speedKph: row.speed_kph === null ? null : Number(row.speed_kph),
    headingDeg: row.heading_deg === null ? null : Number(row.heading_deg),
    recordedAt: row.recorded_at,
    receivedAt: row.received_at,
  };
}

module.exports = router;
