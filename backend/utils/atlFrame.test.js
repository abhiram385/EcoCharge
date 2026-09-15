const { parseAtlFrame } = require('./atlFrame');

// Real captured bytes from the EL-440 streaming to a raw TCP logger.
const GPRMC_A = '\x20\x01ATL864688053456114,$GPRMC,061906,A,1729.4056,N,07826.4922,E,0.9,236,150926,,,*2C,' +
  '#0000000100000000,6.97#0.00,NC#,00.0,7.40,15,1.6,31,404,49,4bad,4010ATL\x02\x05';

const GPRMC_B = '\x20\x01ATL864688053456114,$GPRMC,062007,A,1729.4108,N,07826.4941,E,0.4,47,150926,,,*11,' +
  '#0000000100000000,6.97#0.00,NC#,00.0,7.42,16,1.6,31,404,49,4bad,4010ATL\x02\x48';

const ATLCAN = 'H,ATLCAN,864688053456114,133642,100926,OBD0.0@18904001:XXXXX@18914001:XXXXX@18924001:XXXXX@' +
  '@@@@@@@@@@@@@@@@@@@@@@@@,$';

const ATLSER = 'ATL864688053456114,200519,060704,ATLSER,,ATLSER,LTA';

function buf(s) {
  return Buffer.from(s, 'latin1');
}

describe('parseAtlFrame', () => {
  it('extracts position from a real $GPRMC frame', () => {
    const p = parseAtlFrame(buf(GPRMC_A));
    expect(p).toMatchObject({ deviceId: '864688053456114', valid: true });
    expect(p.lat).toBeCloseTo(17.490093, 5);
    expect(p.lng).toBeCloseTo(78.441537, 5);
    expect(p.speedKph).toBeCloseTo(1.6668, 3);
    expect(p.headingDeg).toBe(236);
    expect(p.recordedAt.toISOString()).toBe('2026-09-15T06:19:06.000Z');
  });

  it('extracts a second, different fix correctly', () => {
    const p = parseAtlFrame(buf(GPRMC_B));
    expect(p.lat).toBeCloseTo(17.49018, 5);
    expect(p.lng).toBeCloseTo(78.441568, 5);
    expect(p.speedKph).toBeCloseTo(0.7408, 3);
    expect(p.headingDeg).toBe(47);
  });

  it('handles southern/western hemispheres as negative', () => {
    const s = GPRMC_A.replace('1729.4056,N', '1729.4056,S').replace('07826.4922,E', '07826.4922,W');
    const p = parseAtlFrame(buf(s));
    expect(p.lat).toBeLessThan(0);
    expect(p.lng).toBeLessThan(0);
  });

  it('marks a void ("V") fix as not valid, with no coordinates', () => {
    const s = GPRMC_A.replace(',A,', ',V,');
    const p = parseAtlFrame(buf(s));
    expect(p.deviceId).toBe('864688053456114');
    expect(p.valid).toBe(false);
    expect(p.lat).toBeUndefined();
  });

  it('ignores non-position ATLCAN (OBD/diagnostics) frames', () => {
    expect(parseAtlFrame(buf(ATLCAN))).toBeNull();
  });

  it('ignores ATLSER heartbeat frames', () => {
    expect(parseAtlFrame(buf(ATLSER))).toBeNull();
  });

  it('ignores garbage / empty input', () => {
    expect(parseAtlFrame(buf('random noise'))).toBeNull();
    expect(parseAtlFrame(buf(''))).toBeNull();
    expect(parseAtlFrame(Buffer.alloc(0))).toBeNull();
  });
});
