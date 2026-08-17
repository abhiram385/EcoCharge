const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');
const { BATTERY_CAPACITY_KWH } = require('../utils/batterySimulation');

const router = express.Router();
router.use(requireAuth);

// GET /api/vehicles
router.get('/', asyncHandler(async (req, res) => {
  const { rows } = await pool.query(
    'SELECT * FROM vehicles WHERE user_id = $1 ORDER BY is_default DESC, created_at DESC',
    [req.user.id]
  );
  res.json({ vehicles: rows.map(formatVehicle) });
}));

// POST /api/vehicles { make, model, connectorType, regNumber, isDefault, batteryCapacityKwh, swapCapable }
router.post('/', asyncHandler(async (req, res) => {
  const { make, model, connectorType, regNumber, isDefault, batteryCapacityKwh, swapCapable } = req.body;

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
    `INSERT INTO vehicles (user_id, make, model, connector_type, reg_number, is_default, battery_capacity_kwh, swap_capable)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
    [req.user.id, make, model, connectorType, regNumber || null, !!isDefault, normalizedCapacity, !!swapCapable]
  );

  res.status(201).json({ vehicle: formatVehicle(rows[0]) });
}));

// PATCH /api/vehicles/:id { regNumber?, batteryLevelPct? }
router.patch('/:id', asyncHandler(async (req, res) => {
  const { regNumber, batteryLevelPct } = req.body;

  if (batteryLevelPct !== undefined && batteryLevelPct !== null) {
    const pct = Number(batteryLevelPct);
    if (!Number.isFinite(pct) || pct < 0 || pct > 100) {
      return res.status(400).json({ error: 'batteryLevelPct must be between 0 and 100' });
    }
  }

  const { rows } = await pool.query(
    `UPDATE vehicles SET
       reg_number = COALESCE($1, reg_number),
       battery_level_pct = COALESCE($2, battery_level_pct)
     WHERE id = $3 AND user_id = $4 RETURNING *`,
    [regNumber ?? null, batteryLevelPct ?? null, req.params.id, req.user.id]
  );
  if (rows.length === 0) {
    return res.status(404).json({ error: 'Vehicle not found' });
  }
  res.json({ vehicle: formatVehicle(rows[0]) });
}));

// DELETE /api/vehicles/:id
router.delete('/:id', asyncHandler(async (req, res) => {
  const result = await pool.query(
    'DELETE FROM vehicles WHERE id = $1 AND user_id = $2 RETURNING id',
    [req.params.id, req.user.id]
  );
  if (result.rows.length === 0) {
    return res.status(404).json({ error: 'Vehicle not found' });
  }
  res.json({ deleted: true });
}));

function formatVehicle(row) {
  return {
    id: row.id,
    make: row.make,
    model: row.model,
    connectorType: row.connector_type,
    regNumber: row.reg_number,
    isDefault: row.is_default,
    batteryCapacityKwh: Number(row.battery_capacity_kwh),
    batteryLevelPct: row.battery_level_pct,
    swapCapable: row.swap_capable,
  };
}

module.exports = router;
