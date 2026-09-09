const crypto = require('crypto');

// Verifies an "SMS Gateway for Android" webhook signature: HMAC-SHA256 over
// (raw request body + X-Timestamp), hex-encoded, compared in constant time
// against the X-Signature header.
function verifyGatewaySignature({ rawBody, timestamp, signature, secret }) {
  if (!secret || !signature || !timestamp) return false;

  const body = Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(rawBody || '', 'utf8');
  const expected = crypto
    .createHmac('sha256', secret)
    .update(Buffer.concat([body, Buffer.from(String(timestamp), 'utf8')]))
    .digest('hex');

  const a = Buffer.from(String(signature), 'utf8');
  const b = Buffer.from(expected, 'utf8');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

module.exports = { verifyGatewaySignature };
