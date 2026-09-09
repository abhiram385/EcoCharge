const crypto = require('crypto');
const { verifyGatewaySignature } = require('./webhookSignature');

const SECRET = 'test-signing-key';

function sign(rawBody, timestamp, secret = SECRET) {
  return crypto
    .createHmac('sha256', secret)
    .update(Buffer.concat([Buffer.from(rawBody), Buffer.from(String(timestamp))]))
    .digest('hex');
}

describe('verifyGatewaySignature', () => {
  const body = JSON.stringify({ event: 'sms:received', payload: { message: 'hi' } });
  const ts = '1757400000';

  it('accepts a correctly signed payload', () => {
    expect(verifyGatewaySignature({ rawBody: body, timestamp: ts, signature: sign(body, ts), secret: SECRET })).toBe(true);
  });

  it('accepts a Buffer raw body', () => {
    expect(
      verifyGatewaySignature({ rawBody: Buffer.from(body), timestamp: ts, signature: sign(body, ts), secret: SECRET })
    ).toBe(true);
  });

  it('rejects a tampered body', () => {
    expect(verifyGatewaySignature({ rawBody: body + ' ', timestamp: ts, signature: sign(body, ts), secret: SECRET })).toBe(false);
  });

  it('rejects a tampered timestamp', () => {
    expect(verifyGatewaySignature({ rawBody: body, timestamp: '1757400001', signature: sign(body, ts), secret: SECRET })).toBe(false);
  });

  it('rejects the wrong secret', () => {
    expect(verifyGatewaySignature({ rawBody: body, timestamp: ts, signature: sign(body, ts, 'other'), secret: SECRET })).toBe(false);
  });

  it('rejects missing pieces without throwing', () => {
    expect(verifyGatewaySignature({ rawBody: body, timestamp: ts, signature: undefined, secret: SECRET })).toBe(false);
    expect(verifyGatewaySignature({ rawBody: body, timestamp: undefined, signature: 'x', secret: SECRET })).toBe(false);
    expect(verifyGatewaySignature({ rawBody: body, timestamp: ts, signature: 'x', secret: undefined })).toBe(false);
  });

  it('rejects a garbage signature of the wrong length', () => {
    expect(verifyGatewaySignature({ rawBody: body, timestamp: ts, signature: 'deadbeef', secret: SECRET })).toBe(false);
  });
});
