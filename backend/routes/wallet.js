const express = require('express');
const { pool } = require('../db/pool');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');
const { createOrder } = require('../utils/razorpayOrders');
const { verifyPaymentSignature } = require('../utils/razorpaySignature');

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

// POST /api/wallet/topup/order { amount } — step 1: open a Razorpay order.
// Nothing is credited here; this only records that a checkout started.
router.post('/topup/order', asyncHandler(async (req, res) => {
  const amount = Number(req.body.amount);
  if (!amount || amount <= 0) {
    return res.status(400).json({ error: 'amount must be a positive number' });
  }

  let order;
  try {
    order = await createOrder({ amountRupees: amount, receipt: `topup_${req.user.id}_${Date.now()}` });
  } catch (err) {
    return res.status(502).json({ error: 'Could not start payment. Please try again.' });
  }

  await pool.query(
    `INSERT INTO payment_orders (user_id, amount, gateway_order_id, status)
     VALUES ($1, $2, $3, 'created')`,
    [req.user.id, amount, order.id]
  );

  res.status(201).json({ orderId: order.id, amount, keyId: process.env.RAZORPAY_KEY_ID });
}));

// POST /api/wallet/topup/verify { orderId, paymentId, signature } — step 2:
// only a valid signature (proving Razorpay actually processed this payment)
// credits the wallet. Idempotent — re-verifying an already-verified order
// just returns the current state instead of crediting twice.
router.post('/topup/verify', asyncHandler(async (req, res) => {
  const { orderId, paymentId, signature } = req.body;
  if (!orderId || !paymentId || !signature) {
    return res.status(400).json({ error: 'orderId, paymentId, and signature are required' });
  }

  const { rows } = await pool.query(
    'SELECT * FROM payment_orders WHERE gateway_order_id = $1 AND user_id = $2',
    [orderId, req.user.id]
  );
  if (rows.length === 0) {
    return res.status(404).json({ error: 'Order not found' });
  }
  const order = rows[0];

  if (order.status === 'verified') {
    const userResult = await pool.query('SELECT wallet_balance FROM users WHERE id = $1', [req.user.id]);
    return res.json({ balance: Number(userResult.rows[0].wallet_balance), alreadyVerified: true });
  }

  const valid = verifyPaymentSignature({ orderId, paymentId, signature, secret: process.env.RAZORPAY_KEY_SECRET });
  if (!valid) {
    await pool.query("UPDATE payment_orders SET status = 'failed' WHERE id = $1", [order.id]);
    return res.status(400).json({ error: 'Payment verification failed' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      "UPDATE payment_orders SET status = 'verified', gateway_payment_id = $1, verified_at = now() WHERE id = $2",
      [paymentId, order.id]
    );
    const updated = await client.query(
      'UPDATE users SET wallet_balance = wallet_balance + $1, updated_at = now() WHERE id = $2 RETURNING wallet_balance',
      [order.amount, req.user.id]
    );
    const tx = await client.query(
      `INSERT INTO wallet_transactions (user_id, type, amount, reference)
       VALUES ($1, 'topup', $2, $3) RETURNING *`,
      [req.user.id, order.amount, paymentId]
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
