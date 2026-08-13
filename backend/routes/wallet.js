const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');

const router = express.Router();
router.use(requireAuth);

// GET /api/wallet
router.get('/', asyncHandler(async (req, res) => {
  const userResult = await pool.query('SELECT wallet_balance FROM users WHERE id = $1', [req.user.id]);
  const txResult = await pool.query(
    'SELECT * FROM wallet_transactions WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50',
    [req.user.id]
  );
  res.json({
    balance: Number(userResult.rows[0].wallet_balance),
    transactions: txResult.rows.map(formatTx),
  });
}));

// POST /api/wallet/topup { amount, reference }
// NOTE: In production, this should be triggered only after a verified payment
// gateway callback (Razorpay/Stripe/etc.), not directly from the client.
router.post('/topup', asyncHandler(async (req, res) => {
  const amount = Number(req.body.amount);
  if (!amount || amount <= 0) {
    return res.status(400).json({ error: 'amount must be a positive number' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const updated = await client.query(
      'UPDATE users SET wallet_balance = wallet_balance + $1, updated_at = now() WHERE id = $2 RETURNING wallet_balance',
      [amount, req.user.id]
    );
    const tx = await client.query(
      `INSERT INTO wallet_transactions (user_id, type, amount, reference)
       VALUES ($1, 'topup', $2, $3) RETURNING *`,
      [req.user.id, amount, req.body.reference || 'wallet_topup']
    );
    await client.query('COMMIT');
    res.status(201).json({
      balance: Number(updated.rows[0].wallet_balance),
      transaction: formatTx(tx.rows[0]),
    });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}));

function formatTx(row) {
  return {
    id: row.id,
    type: row.type,
    amount: Number(row.amount),
    reference: row.reference,
    sessionId: row.session_id,
    createdAt: row.created_at,
  };
}

module.exports = router;
