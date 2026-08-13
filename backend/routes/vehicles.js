const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');

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
  };
}

module.exports = router;
