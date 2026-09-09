const { parseGetGpsReply } = require('./el440SmsReply');

const VALID = `IMEI: 864688053456114
CCID: 8991000924358270430F
http://maps.google.com/maps?q=17.490170,78.441620
DATE: 090926
TIME(GMT): 063651
SPEED: 0.000000`;

const INVALID = `IMEI: 864688053456114
CCID: 8991000924358270430F
GPS INVALID
LAST VALID LAT_LONG
http://maps.google.com/maps?q=0.000000,0.000000`;

describe('parseGetGpsReply', () => {
  it('parses a valid GETGPS reply', () => {
    const r = parseGetGpsReply(VALID);
    expect(r).toEqual({
      deviceId: '864688053456114',
      valid: true,
      lat: 17.49017,
      lng: 78.44162,
      speedKph: 0,
      recordedAt: new Date('2026-09-09T06:36:51.000Z'),
    });
  });

  it('builds recordedAt from DDMMYY + HHMMSS GMT', () => {
    const r = parseGetGpsReply(VALID.replace('DATE: 090926', 'DATE: 251215').replace('TIME(GMT): 063651', 'TIME(GMT): 010203'));
    expect(r.recordedAt.toISOString()).toBe('2015-12-25T01:02:03.000Z');
  });

  it('marks a GPS INVALID reply as not valid, with no coordinates', () => {
    const r = parseGetGpsReply(INVALID);
    expect(r.deviceId).toBe('864688053456114');
    expect(r.valid).toBe(false);
    expect(r.lat).toBeUndefined();
  });

  it('treats a 0,0 fix as not valid even without the INVALID marker', () => {
    const r = parseGetGpsReply(VALID.replace('17.490170,78.441620', '0.000000,0.000000'));
    expect(r.valid).toBe(false);
  });

  it('returns null for text that is not a GETGPS reply', () => {
    expect(parseGetGpsReply('random sms')).toBeNull();
    expect(parseGetGpsReply('')).toBeNull();
    expect(parseGetGpsReply(null)).toBeNull();
  });

  it('tolerates extra whitespace and CRLF line endings', () => {
    const r = parseGetGpsReply(VALID.replace(/\n/g, '\r\n') + '\r\n');
    expect(r.valid).toBe(true);
    expect(r.lat).toBe(17.49017);
  });

  it('handles a negative-coordinate fix', () => {
    const r = parseGetGpsReply(VALID.replace('17.490170,78.441620', '-33.865143,151.209900'));
    expect(r.lat).toBe(-33.865143);
    expect(r.lng).toBe(151.2099);
  });
});
