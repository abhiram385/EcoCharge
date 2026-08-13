const crypto = require('crypto');
const { generateOtp } = require('./otp');

describe('generateOtp', () => {
  it('returns a 6-digit numeric string', () => {
    const code = generateOtp();
    expect(code).toMatch(/^\d{6}$/);
  });

  it('uses a cryptographically secure RNG, not Math.random', () => {
    const spy = jest.spyOn(Math, 'random');
    const randomIntSpy = jest.spyOn(crypto, 'randomInt');
    generateOtp();
    expect(spy).not.toHaveBeenCalled();
    expect(randomIntSpy).toHaveBeenCalled();
    spy.mockRestore();
    randomIntSpy.mockRestore();
  });

  it('produces values across the full 100000-999999 range over many samples', () => {
    const codes = new Set();
    for (let i = 0; i < 200; i++) codes.add(generateOtp());
    expect(codes.size).toBeGreaterThan(150);
    for (const c of codes) {
      const n = Number(c);
      expect(n).toBeGreaterThanOrEqual(100000);
      expect(n).toBeLessThanOrEqual(999999);
    }
  });
});
