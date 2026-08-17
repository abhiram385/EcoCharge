const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');

const router = express.Router();
router.use(requireAuth);

// GET /api/swap/nearby?lat=..&lng=..&radiusKm=15
router.get('/nearby', asyncHandler(async (req, res) => {
  const lat = parseFloat(req.query.lat);
  const lng = parseFloat(req.query.lng);
  const radiusKm = parseFloat(req.query.radiusKm || '15');

  if (Number.isNaN(lat) || Number.isNaN(lng)) {
    return res.status(400).json({ error: 'lat and lng query params are required' });
  }

  const { rows } = await pool.query(
    `SELECT * FROM (
       SELECT sp.*,
         (6371 * acos(
           cos(radians($1)) * cos(radians(sp.latitude)) *
           cos(radians(sp.longitude) - radians($2)) +
           sin(radians($1)) * sin(radians(sp.latitude))
         )) AS distance_km
       FROM swap_points sp
     ) sub
     WHERE distance_km <= $3
     ORDER BY distance_km ASC
     LIMIT 50`,
    [lat, lng, radiusKm]
  );

  res.json({ swapPoints: rows.map(formatSwapPoint) });
}));

// GET /api/swap/:id  (includes pack inventory)
router.get('/:id', asyncHandler(async (req, res) => {
  const { id } = req.params;

  const pointResult = await pool.query('SELECT * FROM swap_points WHERE id = $1', [id]);
  if (pointResult.rows.length === 0) {
    return res.status(404).json({ error: 'Swap point not found' });
  }

  const packsResult = await pool.query(
    'SELECT * FROM swap_packs WHERE swap_point_id = $1 ORDER BY pack_type',
    [id]
  );

  res.json({
    swapPoint: formatSwapPoint(pointResult.rows[0]),
    packs: packsResult.rows.map(formatPack),
  });
}));

// POST /api/swap/:id/redeem { packId, vehicleId? }
// Instant trade: debit wallet, decrement inventory, record the swap. If a
// vehicle is given, its battery level is topped up to full (vehicles table
// tracks a persisted battery level — see routes/vehicles.js).
router.post('/:id/redeem', asyncHandler(async (req, res) => {
  const { packId, vehicleId } = req.body;
  if (!packId) {
    return res.status(400).json({ error: 'packId is required' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const packResult = await client.query(
      'SELECT * FROM swap_packs WHERE id = $1 AND swap_point_id = $2 FOR UPDATE',
      [packId, req.params.id]
    );
    if (packResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Pack not found at this swap point' });
    }
    const pack = packResult.rows[0];
    if (pack.available_count <= 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'No packs currently available at this point' });
    }

    const cost = Number(pack.price_per_swap);
    const balanceResult = await client.query('SELECT wallet_balance FROM users WHERE id = $1 FOR UPDATE', [
      req.user.id,
    ]);
    const balance = Number(balanceResult.rows[0].wallet_balance);
    if (balance < cost) {
      await client.query('ROLLBACK');
      return res.status(402).json({ error: 'Insufficient wallet balance. Please top up.', cost, balance });
    }

    if (vehicleId) {
      const vehicleCheck = await client.query('SELECT id FROM vehicles WHERE id = $1 AND user_id = $2', [
        vehicleId,
        req.user.id,
      ]);
      if (vehicleCheck.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Vehicle not found' });
      }
    }

    await client.query(
      'UPDATE swap_packs SET available_count = available_count - 1 WHERE id = $1',
      [packId]
    );
    await client.query('UPDATE users SET wallet_balance = wallet_balance - $1, updated_at = now() WHERE id = $2', [
      cost,
      req.user.id,
    ]);

    const tx = await client.query(
      `INSERT INTO swap_transactions (user_id, swap_point_id, pack_id, vehicle_id, cost)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [req.user.id, req.params.id, packId, vehicleId || null, cost]
    );

    await client.query(
      `INSERT INTO wallet_transactions (user_id, type, amount, reference)
       VALUES ($1, 'battery_swap', $2, 'battery_swap')`,
      [req.user.id, cost]
    );

    if (vehicleId) {
      await client.query('UPDATE vehicles SET battery_level_pct = 100 WHERE id = $1', [vehicleId]);
    }

    await client.query('COMMIT');
    res.status(201).json({ swap: formatTransaction(tx.rows[0], cost) });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}));

// GET /api/swap/history/me
router.get('/history/me', asyncHandler(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT st.*, sp.name AS swap_point_name, pk.pack_type, pk.capacity_kwh
     FROM swap_transactions st
     JOIN swap_points sp ON sp.id = st.swap_point_id
     JOIN swap_packs pk ON pk.id = st.pack_id
     WHERE st.user_id = $1
     ORDER BY st.created_at DESC LIMIT 50`,
    [req.user.id]
  );
  res.json({
    swaps: rows.map((r) => ({
      id: r.id,
      swapPointName: r.swap_point_name,
      packType: r.pack_type,
      capacityKwh: Number(r.capacity_kwh),
      cost: Number(r.cost),
      createdAt: r.created_at,
    })),
  });
}));

function formatSwapPoint(row) {
  return {
    id: row.id,
    name: row.name,
    address: row.address,
    city: row.city,
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    rating: Number(row.rating),
    isOpen24h: row.is_open_24h,
    amenities: row.amenities || [],
    distanceKm: row.distance_km !== undefined ? Number(row.distance_km).toFixed(1) : undefined,
  };
}

function formatPack(row) {
  return {
    id: row.id,
    swapPointId: row.swap_point_id,
    packType: row.pack_type,
    capacityKwh: Number(row.capacity_kwh),
    pricePerSwap: Number(row.price_per_swap),
    availableCount: row.available_count,
    totalCount: row.total_count,
  };
}

function formatTransaction(row, cost) {
  return {
    id: row.id,
    swapPointId: row.swap_point_id,
    packId: row.pack_id,
    vehicleId: row.vehicle_id,
    cost,
    createdAt: row.created_at,
  };
}

module.exports = router;
