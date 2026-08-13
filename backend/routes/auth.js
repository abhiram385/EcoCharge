const express = require('express');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const { pool } = require('../db/pool');
const { generateOtp } = require('../utils/otp');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../middleware/asyncHandler');

const router = express.Router();

const otpRequestLimiter = rateLimit({
  windowMs: 10 * 60 * 1000, // 10 minutes
  max: 5, // 5 OTP requests per phone-ish window per IP
  message: { error: 'Too many OTP requests. Please try again later.' },
});

const isDevOtpAllowed = process.env.NODE_ENV === 'development' && process.env.SMS_PROVIDER === 'console';

function isValidPhone(phone) {
  return typeof phone === 'string' && /^\+?[1-9]\d{7,14}$/.test(phone);
}

// POST /api/auth/request-otp { phone }
router.post('/request-otp', otpRequestLimiter, asyncHandler(async (req, res) => {
  const { phone } = req.body;

  if (!isValidPhone(phone)) {
    return res.status(400).json({ error: 'Enter a valid phone number in international format, e.g. +919876543210' });
  }

  const code = generateOtp();
  const expiresAt = new Date(Date.now() + Number(process.env.OTP_EXPIRY_MINUTES || 5) * 60 * 1000);

  await pool.query(
    'INSERT INTO otp_codes (phone, code, expires_at) VALUES ($1, $2, $3)',
    [phone, code, expiresAt]
  );

  // Plug in a real SMS provider here (Twilio, MSG91, etc.) in production.
  if (process.env.SMS_PROVIDER === 'console' || !process.env.SMS_PROVIDER) {
    console.log(`[OTP] Sending code ${code} to ${phone} (expires in ${process.env.OTP_EXPIRY_MINUTES || 5} min)`);
  }

  res.json({
    message: 'OTP sent successfully',
    // Only included when NODE_ENV=development AND no real SMS provider is configured,
    // so a misconfigured staging/prod deploy can never leak the code.
    devOtp: isDevOtpAllowed ? code : undefined,
  });
}));

// POST /api/auth/verify-otp { phone, code, name? }
router.post('/verify-otp', asyncHandler(async (req, res) => {
  const { phone, code, name } = req.body;

  if (!isValidPhone(phone) || !code) {
    return res.status(400).json({ error: 'Phone and OTP code are required' });
  }

  const { rows } = await pool.query(
    `SELECT * FROM otp_codes
     WHERE phone = $1 AND code = $2 AND consumed = FALSE AND expires_at > now()
     ORDER BY created_at DESC LIMIT 1`,
    [phone, code]
  );

  if (rows.length === 0) {
    return res.status(400).json({ error: 'Invalid or expired OTP' });
  }

  await pool.query('UPDATE otp_codes SET consumed = TRUE WHERE id = $1', [rows[0].id]);

  let userResult = await pool.query('SELECT * FROM users WHERE phone = $1', [phone]);
  let user;

  if (userResult.rows.length === 0) {
    const inserted = await pool.query(
      'INSERT INTO users (phone, name) VALUES ($1, $2) RETURNING *',
      [phone, name || null]
    );
    user = inserted.rows[0];
  } else {
    user = userResult.rows[0];
  }

  const token = jwt.sign({ sub: user.id, phone: user.phone }, process.env.JWT_SECRET, {
    expiresIn: process.env.JWT_EXPIRES_IN || '30d',
  });

  res.json({
    token,
    user: {
      id: user.id,
      phone: user.phone,
      name: user.name,
      email: user.email,
      walletBalance: Number(user.wallet_balance),
    },
  });
}));

// GET /api/auth/me — rehydrate current user (fixes client-side bootstrap gap)
router.get('/me', requireAuth, asyncHandler(async (req, res) => {
  const { rows } = await pool.query('SELECT * FROM users WHERE id = $1', [req.user.id]);

  if (rows.length === 0) {
    return res.status(401).json({ error: 'User no longer exists' });
  }

  const user = rows[0];
  res.json({
    user: {
      id: user.id,
      phone: user.phone,
      name: user.name,
      email: user.email,
      walletBalance: Number(user.wallet_balance),
    },
  });
}));

module.exports = router;
