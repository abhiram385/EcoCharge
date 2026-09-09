const { normalizePosition, PositionError } = require('./trackerPosition');

describe('normalizePosition', () => {
  const valid = { deviceId: 'EL440-001', lat: 17.385, lng: 78.4867 };

  it('accepts a minimal valid payload and defaults the optional fields', () => {
    const before = Date.now();
    const p = normalizePosition(valid);
    expect(p.deviceId).toBe('EL440-001');
    expect(p.lat).toBe(17.385);
    expect(p.lng).toBe(78.4867);
    expect(p.speedKph).toBeNull();
    expect(p.headingDeg).toBeNull();
    expect(p.recordedAt.getTime()).toBeGreaterThanOrEqual(before);
  });

  it('trims the deviceId and rejects an empty one', () => {
    expect(normalizePosition({ ...valid, deviceId: '  EL440-001  ' }).deviceId).toBe('EL440-001');
    expect(() => normalizePosition({ ...valid, deviceId: '   ' })).toThrow(PositionError);
  });

  it('requires numeric lat and lng', () => {
    expect(() => normalizePosition({ deviceId: 'x', lat: 'abc', lng: 10 })).toThrow(PositionError);
    expect(() => normalizePosition({ deviceId: 'x', lng: 10 })).toThrow(PositionError);
  });

  it('rejects out-of-range coordinates', () => {
    expect(() => normalizePosition({ ...valid, lat: 91 })).toThrow(/lat out of range/);
    expect(() => normalizePosition({ ...valid, lng: -181 })).toThrow(/lng out of range/);
  });

  it('coerces string numbers from a wire decoder', () => {
    const p = normalizePosition({ deviceId: 'x', lat: '17.385', lng: '78.4867', speedKph: '42.5' });
    expect(p.lat).toBe(17.385);
    expect(p.speedKph).toBe(42.5);
  });

  it('clamps negative speed to 0 and wraps heading into [0,360)', () => {
    expect(normalizePosition({ ...valid, speedKph: -5 }).speedKph).toBe(0);
    expect(normalizePosition({ ...valid, headingDeg: 370 }).headingDeg).toBe(10);
    expect(normalizePosition({ ...valid, headingDeg: -90 }).headingDeg).toBe(270);
  });

  it('parses recordedAt from ISO, epoch seconds, and epoch milliseconds', () => {
    const iso = normalizePosition({ ...valid, recordedAt: '2026-09-09T10:00:00.000Z' });
    expect(iso.recordedAt.toISOString()).toBe('2026-09-09T10:00:00.000Z');

    const secs = normalizePosition({ ...valid, recordedAt: 1757412000 });
    const ms = normalizePosition({ ...valid, recordedAt: 1757412000000 });
    expect(secs.recordedAt.getTime()).toBe(ms.recordedAt.getTime());
  });

  it('falls back to now for an unparseable recordedAt instead of throwing', () => {
    const before = Date.now();
    const p = normalizePosition({ ...valid, recordedAt: 'not-a-date' });
    expect(p.recordedAt.getTime()).toBeGreaterThanOrEqual(before);
  });

  it('rejects a non-object payload', () => {
    expect(() => normalizePosition(null)).toThrow(PositionError);
    expect(() => normalizePosition('nope')).toThrow(PositionError);
  });
});
