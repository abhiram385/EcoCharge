async function finalizeSession(pool, { sessionId, userId, connectorId, energyKwh, cost }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const balanceResult = await client.query('SELECT wallet_balance FROM users WHERE id = $1 FOR UPDATE', [
      userId,
    ]);
    const balance = Number(balanceResult.rows[0].wallet_balance);
    if (balance < cost) {
      await client.query('ROLLBACK');
      return { ok: false, error: 'Insufficient wallet balance. Please top up.', cost, balance };
    }

    const updatedSession = await client.query(
      `UPDATE charging_sessions
       SET status = 'completed', stopped_at = now(), energy_kwh = $1, cost = $2
       WHERE id = $3 AND status = 'active' RETURNING *`,
      [energyKwh.toFixed(3), cost, sessionId]
    );

    if (updatedSession.rows.length === 0) {
      // Someone else (a concurrent poll/stop) already finalized this session
      // between our read and this write. Do not debit the wallet again.
      await client.query('ROLLBACK');
      return { ok: false, error: 'Session already finalized', alreadyFinalized: true };
    }

    await client.query('UPDATE users SET wallet_balance = wallet_balance - $1, updated_at = now() WHERE id = $2', [
      cost,
      userId,
    ]);

    await client.query(
      `INSERT INTO wallet_transactions (user_id, type, amount, reference, session_id)
       VALUES ($1, 'charge_debit', $2, 'charging_session', $3)`,
      [userId, cost, sessionId]
    );

    await client.query("UPDATE connectors SET status = 'available' WHERE id = $1", [connectorId]);

    await client.query('COMMIT');
    return { ok: true, session: updatedSession.rows[0] };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { finalizeSession };
