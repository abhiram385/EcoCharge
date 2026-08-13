async function checkVehicleConnectorCompatible(pool, { vehicleId, userId, connectorType }) {
  if (!vehicleId) {
    return { ok: true };
  }

  const { rows } = await pool.query('SELECT connector_type FROM vehicles WHERE id = $1 AND user_id = $2', [
    vehicleId,
    userId,
  ]);

  if (rows.length === 0) {
    return { ok: false, error: 'Vehicle not found' };
  }

  if (rows[0].connector_type !== connectorType) {
    return { ok: false, error: `This connector is not compatible with your vehicle (needs ${rows[0].connector_type})` };
  }

  return { ok: true };
}

module.exports = { checkVehicleConnectorCompatible };
