const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');
const { normalizePosition, PositionError } = require('../utils/trackerPosition');
const { parseGetGpsReply } = require('../utils/el440SmsReply');
const { verifyGatewaySignature } = require('../utils/webhookSignature');

const router = express.Router();

async function insertPosition(position) {
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
  return rows[0];
}

// POST /api/tracker/ingest  — called by the position feeder / (later) the
// EL-440 GPRS decoder. Guarded by a shared key rather than a user JWT, since
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

  const row = await insertPosition(position);
  res.status(201).json({ id: row.id, receivedAt: row.received_at });
}));

// POST /api/tracker/sms-hook  — the "SMS Gateway for Android" webhook. When
// the gateway phone receives an SMS it POSTs it here, HMAC-signed. We pull
// EL-440 GETGPS replies out of the message body and store valid fixes.
router.post('/sms-hook', asyncHandler(async (req, res) => {
  const secret = process.env.TRACKER_SMS_HOOK_SECRET;
  if (!secret) {
    return res.status(503).json({ error: 'SMS hook is not configured' });
  }

  const signed = verifyGatewaySignature({
    rawBody: req.rawBody,
    timestamp: req.get('x-timestamp'),
    signature: req.get('x-signature'),
    secret,
  });
  if (!signed) {
    return res.status(401).json({ error: 'Bad or missing webhook signature' });
  }

  const message = req.body?.payload?.message ?? req.body?.message;
  if (typeof message !== 'string') {
    return res.status(400).json({ error: 'No message text in webhook payload' });
  }

  const parsed = parseGetGpsReply(message);
  if (!parsed) return res.json({ ignored: 'not a GETGPS reply' });
  if (!parsed.valid) return res.json({ ignored: 'GPS invalid', deviceId: parsed.deviceId });

  const position = normalizePosition({
    deviceId: parsed.deviceId,
    lat: parsed.lat,
    lng: parsed.lng,
    speedKph: parsed.speedKph,
    recordedAt: parsed.recordedAt,
    raw: { source: 'getgps-sms', message, sender: req.body?.payload?.sender ?? null },
  });

  const row = await insertPosition(position);
  res.status(201).json({ id: row.id, deviceId: position.deviceId });
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
