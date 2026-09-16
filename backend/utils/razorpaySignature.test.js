const crypto = require('crypto');
const { verifyPaymentSignature } = require('./razorpaySignature');

const SECRET = 'test_key_secret';

function sign(orderId, paymentId, secret = SECRET) {
  return crypto.createHmac('sha256', secret).update(`${orderId}|${paymentId}`).digest('hex');
}

describe('verifyPaymentSignature', () => {
  const orderId = 'order_ABC123';
  const paymentId = 'pay_XYZ789';

  it('accepts a correctly signed payment', () => {
    const signature = sign(orderId, paymentId);
    expect(verifyPaymentSignature({ orderId, paymentId, signature, secret: SECRET })).toBe(true);
  });

  it('rejects a signature for a different order id', () => {
    const signature = sign('order_OTHER', paymentId);
    expect(verifyPaymentSignature({ orderId, paymentId, signature, secret: SECRET })).toBe(false);
  });

  it('rejects a signature for a different payment id', () => {
    const signature = sign(orderId, 'pay_OTHER');
    expect(verifyPaymentSignature({ orderId, paymentId, signature, secret: SECRET })).toBe(false);
  });

  it('rejects the wrong secret', () => {
    const signature = sign(orderId, paymentId, 'wrong_secret');
    expect(verifyPaymentSignature({ orderId, paymentId, signature, secret: SECRET })).toBe(false);
  });

  it('rejects missing pieces without throwing', () => {
    expect(verifyPaymentSignature({ orderId, paymentId, signature: undefined, secret: SECRET })).toBe(false);
    expect(verifyPaymentSignature({ orderId: undefined, paymentId, signature: 'x', secret: SECRET })).toBe(false);
    expect(verifyPaymentSignature({ orderId, paymentId: undefined, signature: 'x', secret: SECRET })).toBe(false);
    expect(verifyPaymentSignature({ orderId, paymentId, signature: 'x', secret: undefined })).toBe(false);
  });

  it('rejects a garbage signature of the wrong length', () => {
    expect(verifyPaymentSignature({ orderId, paymentId, signature: 'deadbeef', secret: SECRET })).toBe(false);
  });
});
