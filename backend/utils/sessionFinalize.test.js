const { finalizeSession } = require('./sessionFinalize');

function makeClient(balance, { sessionUpdateRows } = {}) {
  const query = jest.fn((sql) => {
    if (sql.startsWith('BEGIN') || sql.startsWith('COMMIT') || sql.startsWith('ROLLBACK')) {
      return Promise.resolve({});
    }
    if (sql.includes('SELECT wallet_balance')) {
      return Promise.resolve({ rows: [{ wallet_balance: balance }] });
    }
    if (sql.includes('UPDATE charging_sessions')) {
      return Promise.resolve({
        rows:
          sessionUpdateRows !== undefined
            ? sessionUpdateRows
            : [{ id: 's1', status: 'completed', energy_kwh: '10.000', cost: '150.00' }],
      });
    }
    return Promise.resolve({ rows: [] });
  });
  return { query, release: jest.fn() };
}

describe('finalizeSession', () => {
  it('rolls back and returns ok:false when balance is insufficient', async () => {
    const client = makeClient(50);
    const pool = { connect: jest.fn().mockResolvedValue(client) };

    const result = await finalizeSession(pool, {
      sessionId: 's1',
      userId: 'u1',
      connectorId: 'c1',
      energyKwh: 10,
      cost: 150,
    });

    expect(result.ok).toBe(false);
    expect(result.error).toMatch(/insufficient/i);
    expect(result.balance).toBe(50);
    expect(client.query).toHaveBeenCalledWith('ROLLBACK');
    expect(client.release).toHaveBeenCalled();
  });

  it('commits and returns the completed session when balance is sufficient', async () => {
    const client = makeClient(500);
    const pool = { connect: jest.fn().mockResolvedValue(client) };

    const result = await finalizeSession(pool, {
      sessionId: 's1',
      userId: 'u1',
      connectorId: 'c1',
      energyKwh: 10,
      cost: 150,
    });

    expect(result.ok).toBe(true);
    expect(result.session.status).toBe('completed');
    expect(client.query).toHaveBeenCalledWith('COMMIT');
    expect(client.release).toHaveBeenCalled();
  });

  it('rolls back without debiting the wallet when the session was already finalized by a concurrent request', async () => {
    const client = makeClient(500, { sessionUpdateRows: [] });
    const pool = { connect: jest.fn().mockResolvedValue(client) };

    const result = await finalizeSession(pool, {
      sessionId: 's1',
      userId: 'u1',
      connectorId: 'c1',
      energyKwh: 10,
      cost: 150,
    });

    expect(result.ok).toBe(false);
    expect(result.alreadyFinalized).toBe(true);
    expect(client.query).toHaveBeenCalledWith('ROLLBACK');
    expect(client.release).toHaveBeenCalled();

    const calls = client.query.mock.calls.map(([sql]) => sql);
    const sessionUpdateIndex = calls.findIndex((sql) => sql.includes('UPDATE charging_sessions'));
    const walletDebitIndex = calls.findIndex((sql) => sql.includes('UPDATE users SET wallet_balance'));
    expect(sessionUpdateIndex).toBeGreaterThanOrEqual(0);
    // No wallet-debit call should occur at all, and certainly not after the
    // empty-rows session UPDATE.
    expect(walletDebitIndex).toBe(-1);
  });

  it('releases the client even when a query throws', async () => {
    const client = makeClient(500);
    client.query.mockImplementationOnce(() => Promise.resolve({})); // BEGIN
    client.query.mockImplementationOnce(() => Promise.reject(new Error('boom'))); // SELECT wallet_balance
    const pool = { connect: jest.fn().mockResolvedValue(client) };

    await expect(
      finalizeSession(pool, { sessionId: 's1', userId: 'u1', connectorId: 'c1', energyKwh: 10, cost: 150 })
    ).rejects.toThrow('boom');
    expect(client.release).toHaveBeenCalled();
  });
});
