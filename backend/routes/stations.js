const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');

const router = express.Router();

// GET /api/stations/nearby?lat=..&lng=..&radiusKm=10
router.get('/nearby', requireAuth, asyncHandler(async (req, res) => {
  const lat = parseFloat(req.query.lat);
  const lng = parseFloat(req.query.lng);
  const radiusKm = parseFloat(req.query.radiusKm || '15');

  if (Number.isNaN(lat) || Number.isNaN(lng)) {
    return res.status(400).json({ error: 'lat and lng query params are required' });
  }

  // Haversine formula distance calculation in SQL. The distance is computed
  // in an inner query so the outer query can filter/order by the alias
  // without needing a GROUP BY (there's no aggregation here).
  const { rows } = await pool.query(
    `SELECT * FROM (
       SELECT s.*,
         (6371 * acos(
           cos(radians($1)) * cos(radians(s.latitude)) *
           cos(radians(s.longitude) - radians($2)) +
           sin(radians($1)) * sin(radians(s.latitude))
         )) AS distance_km
       FROM stations s
     ) sub
     WHERE distance_km <= $3
     ORDER BY distance_km ASC
     LIMIT 50`,
    [lat, lng, radiusKm]
  );

  res.json({ stations: rows.map(formatStation) });
}));

// GET /api/stations/:id  (includes connectors)
router.get('/:id', requireAuth, asyncHandler(async (req, res) => {
  const { id } = req.params;

  const stationResult = await pool.query('SELECT * FROM stations WHERE id = $1', [id]);
  if (stationResult.rows.length === 0) {
    return res.status(404).json({ error: 'Station not found' });
  }

  const connectorsResult = await pool.query(
    'SELECT * FROM connectors WHERE station_id = $1 ORDER BY connector_type',
    [id]
  );

  res.json({
    station: formatStation(stationResult.rows[0]),
    connectors: connectorsResult.rows.map(formatConnector),
  });
}));

function formatStation(row) {
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

function formatConnector(row) {
  return {
    id: row.id,
    stationId: row.station_id,
    connectorType: row.connector_type,
    powerKw: Number(row.power_kw),
    pricePerKwh: Number(row.price_per_kwh),
    status: row.status,
  };
}

module.exports = router;
