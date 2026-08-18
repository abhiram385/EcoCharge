const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');

const router = express.Router();
router.use(requireAuth);

// Rough, commonly-cited offset figure: charging from the grid instead of
// burning petrol saves about this much CO2 per kWh delivered. Not a precise
// per-vehicle figure — good enough for a "here's roughly what you've saved"
// message, not for anything regulatory.
const CO2_KG_SAVED_PER_KWH = 0.6;
const CO2_KG_PER_TREE_PER_YEAR = 21;

// GET /api/dashboard?lat=&lng=
router.get('/', asyncHandler(async (req, res) => {
  const lat = req.query.lat !== undefined ? parseFloat(req.query.lat) : null;
  const lng = req.query.lng !== undefined ? parseFloat(req.query.lng) : null;

  const userResult = await pool.query('SELECT wallet_balance FROM users WHERE id = $1', [req.user.id]);

  const vehiclesResult = await pool.query(
    'SELECT * FROM vehicles WHERE user_id = $1 ORDER BY is_default DESC, created_at DESC',
    [req.user.id]
  );

  const chargeKwhResult = await pool.query(
    "SELECT COALESCE(SUM(energy_kwh), 0) AS kwh FROM charging_sessions WHERE user_id = $1 AND status = 'completed'",
    [req.user.id]
  );
  const swapKwhResult = await pool.query(
    `SELECT COALESCE(SUM(pk.capacity_kwh), 0) AS kwh
     FROM swap_transactions st JOIN swap_packs pk ON pk.id = st.pack_id
     WHERE st.user_id = $1`,
    [req.user.id]
  );
  const totalKwh = Number(chargeKwhResult.rows[0].kwh) + Number(swapKwhResult.rows[0].kwh);
  const co2SavedKg = totalKwh * CO2_KG_SAVED_PER_KWH;
  const treesEquivalent = co2SavedKg / CO2_KG_PER_TREE_PER_YEAR;

  const suggestedStation = await getSuggestedStation(req.user.id, lat, lng);

  res.json({
    walletBalance: Number(userResult.rows[0].wallet_balance),
    vehicles: vehiclesResult.rows.map(formatVehicle),
    impact: {
      totalKwh: Number(totalKwh.toFixed(2)),
      co2SavedKg: Number(co2SavedKg.toFixed(2)),
      treesEquivalent: Number(treesEquivalent.toFixed(2)),
    },
    suggestedStation,
  });
}));

async function getSuggestedStation(userId, lat, lng) {
  const frequent = await pool.query(
    `SELECT s.*, count(*) AS visit_count
     FROM charging_sessions cs JOIN stations s ON s.id = cs.station_id
     WHERE cs.user_id = $1
     GROUP BY s.id
     ORDER BY visit_count DESC, s.name ASC
     LIMIT 1`,
    [userId]
  );
  if (frequent.rows.length > 0) {
    return { ...formatStation(frequent.rows[0]), reason: 'frequent' };
  }

  if (lat === null || lng === null || Number.isNaN(lat) || Number.isNaN(lng)) {
    return null;
  }

  const nearest = await pool.query(
    `SELECT * FROM (
       SELECT s.*,
         (6371 * acos(
           cos(radians($1)) * cos(radians(s.latitude)) *
           cos(radians(s.longitude) - radians($2)) +
           sin(radians($1)) * sin(radians(s.latitude))
         )) AS distance_km
       FROM stations s
     ) sub
     ORDER BY distance_km ASC
     LIMIT 1`,
    [lat, lng]
  );
  if (nearest.rows.length === 0) return null;
  return { ...formatStation(nearest.rows[0]), reason: 'nearest' };
}

function formatStation(row) {
  return {
    id: row.id,
    name: row.name,
    address: row.address,
    city: row.city,
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    distanceKm: row.distance_km !== undefined ? Number(row.distance_km).toFixed(1) : undefined,
  };
}

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
