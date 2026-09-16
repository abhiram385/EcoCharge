const crypto = require('crypto');

// Verifies a Razorpay Checkout payment: HMAC-SHA256 over "orderId|paymentId"
// using the account's key secret, hex-encoded, compared in constant time
// against the signature the Checkout SDK hands back to the client. This is
// the actual security boundary — without it, anything the client sends
// could be forged to credit a wallet with no real payment behind it.
function verifyPaymentSignature({ orderId, paymentId, signature, secret }) {
  if (!orderId || !paymentId || !signature || !secret) return false;

  const expected = crypto.createHmac('sha256', secret).update(`${orderId}|${paymentId}`).digest('hex');

  const a = Buffer.from(String(signature), 'utf8');
  const b = Buffer.from(expected, 'utf8');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

module.exports = { verifyPaymentSignature };
