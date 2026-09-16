// Thin wrapper around Razorpay's Orders REST API — plain fetch + Basic auth,
// no razorpay npm SDK, matching how the rest of this backend avoids a
// dependency per external service.

async function createOrder({ amountRupees, receipt }) {
  const keyId = process.env.RAZORPAY_KEY_ID;
  const keySecret = process.env.RAZORPAY_KEY_SECRET;
  if (!keyId || !keySecret) {
    throw new Error('RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET must be set');
  }

  const auth = 'Basic ' + Buffer.from(`${keyId}:${keySecret}`).toString('base64');
  const amountPaise = Math.round(amountRupees * 100);

  const res = await fetch('https://api.razorpay.com/v1/orders', {
    method: 'POST',
    headers: {
      Authorization: auth,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ amount: amountPaise, currency: 'INR', receipt }),
  });

  if (!res.ok) {
    let detail = '';
    try {
      detail = ` - ${await res.text()}`;
    } catch (_) {
      // no body
    }
    throw new Error(`Razorpay order creation failed with status ${res.status}${detail}`);
  }

  const body = await res.json();
  return { id: body.id, amount: body.amount, currency: body.currency };
}

module.exports = { createOrder };
