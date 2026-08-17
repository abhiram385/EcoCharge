const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { checkVehicleConnectorCompatible } = require('../utils/vehicleCompat');
const { asyncHandler } = require('../middleware/asyncHandler');

const router = express.Router();
router.use(requireAuth);

// POST /api/bookings { stationId, connectorId, vehicleId, slotStart, slotEnd }
router.post('/', asyncHandler(async (req, res) => {
  const { stationId, connectorId, vehicleId, slotStart, slotEnd } = req.body;

  if (!stationId || !connectorId || !slotStart || !slotEnd) {
    return res.status(400).json({ error: 'stationId, connectorId, slotStart, slotEnd are required' });
  }

  const connector = await pool.query('SELECT * FROM connectors WHERE id = $1 AND station_id = $2', [
    connectorId,
    stationId,
  ]);
  if (connector.rows.length === 0) {
    return res.status(404).json({ error: 'Connector not found at this station' });
  }
  if (connector.rows[0].status === 'offline') {
    return res.status(409).json({ error: 'This connector is currently offline' });
  }

  const compat = await checkVehicleConnectorCompatible(pool, {
    vehicleId: vehicleId || null,
    userId: req.user.id,
    connectorType: connector.rows[0].connector_type,
  });
  if (!compat.ok) {
    return res.status(compat.error === 'Vehicle not found' ? 404 : 409).json({ error: compat.error });
  }

  // Prevent overlapping bookings on the same connector
  const overlap = await pool.query(
    `SELECT id FROM bookings
     WHERE connector_id = $1 AND status = 'confirmed'
       AND slot_start < $3 AND slot_end > $2`,
    [connectorId, slotStart, slotEnd]
  );
  if (overlap.rows.length > 0) {
    return res.status(409).json({ error: 'This slot is already booked. Please choose another time.' });
  }

  // The overlap SELECT above is a fast-path check; the DB-level exclusion
  // constraint (bookings_no_overlap) is what actually closes the race
  // against a concurrent request for the same slot.
  let rows;
  try {
    ({ rows } = await pool.query(
      `INSERT INTO bookings (user_id, station_id, connector_id, vehicle_id, slot_start, slot_end)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [req.user.id, stationId, connectorId, vehicleId || null, slotStart, slotEnd]
    ));
  } catch (err) {
    if (err.code === '23P01') {
      // exclusion_violation
      return res.status(409).json({ error: 'This slot is already booked. Please choose another time.' });
    }
    throw err;
  }

  res.status(201).json({ booking: formatBooking(rows[0]) });
}));

// GET /api/bookings  (current user's bookings, upcoming + past)
router.get('/', asyncHandler(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT b.*, s.name AS station_name, s.address AS station_address
     FROM bookings b JOIN stations s ON s.id = b.station_id
     WHERE b.user_id = $1
     ORDER BY b.slot_start DESC`,
    [req.user.id]
  );
  res.json({ bookings: rows.map(formatBooking) });
}));

// POST /api/bookings/:id/cancel
router.post('/:id/cancel', asyncHandler(async (req, res) => {
  const { rows } = await pool.query(
    `UPDATE bookings SET status = 'cancelled'
     WHERE id = $1 AND user_id = $2 AND status = 'confirmed'
     RETURNING *`,
    [req.params.id, req.user.id]
  );
  if (rows.length === 0) {
    return res.status(404).json({ error: 'Booking not found or cannot be cancelled' });
  }
  res.json({ booking: formatBooking(rows[0]) });
}));

function formatBooking(row) {
  return {
    id: row.id,
    stationId: row.station_id,
    stationName: row.station_name,
    stationAddress: row.station_address,
    connectorId: row.connector_id,
    vehicleId: row.vehicle_id,
    slotStart: row.slot_start,
    slotEnd: row.slot_end,
    status: row.status,
  };
}

module.exports = router;
