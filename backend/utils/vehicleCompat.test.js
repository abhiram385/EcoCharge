const { checkVehicleConnectorCompatible } = require('./vehicleCompat');

describe('checkVehicleConnectorCompatible', () => {
  it('passes when no vehicle is specified', async () => {
    const pool = { query: jest.fn() };
    const result = await checkVehicleConnectorCompatible(pool, {
      vehicleId: null,
      userId: 'u1',
      connectorType: 'CCS2',
    });
    expect(result.ok).toBe(true);
    expect(pool.query).not.toHaveBeenCalled();
  });

  it('fails when the vehicle does not belong to the user', async () => {
    const pool = { query: jest.fn().mockResolvedValue({ rows: [] }) };
    const result = await checkVehicleConnectorCompatible(pool, {
      vehicleId: 'v1',
      userId: 'u1',
      connectorType: 'CCS2',
    });
    expect(result.ok).toBe(false);
    expect(result.error).toMatch(/not found/i);
  });

  it('fails when connector type does not match the vehicle', async () => {
    const pool = {
      query: jest.fn().mockResolvedValue({ rows: [{ connector_type: 'Type2' }] }),
    };
    const result = await checkVehicleConnectorCompatible(pool, {
      vehicleId: 'v1',
      userId: 'u1',
      connectorType: 'CCS2',
    });
    expect(result.ok).toBe(false);
    expect(result.error).toMatch(/not compatible/i);
  });

  it('passes when connector type matches the vehicle', async () => {
    const pool = {
      query: jest.fn().mockResolvedValue({ rows: [{ connector_type: 'CCS2' }] }),
    };
    const result = await checkVehicleConnectorCompatible(pool, {
      vehicleId: 'v1',
      userId: 'u1',
      connectorType: 'CCS2',
    });
    expect(result.ok).toBe(true);
  });
});
