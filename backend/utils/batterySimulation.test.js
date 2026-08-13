const {
  computeBatteryPct,
  randomStartBatteryPct,
  isValidAutoStopPct,
  ALLOWED_AUTO_STOP_PCTS,
} = require('./batterySimulation');

describe('randomStartBatteryPct', () => {
  it('returns an integer between 15 and 55 inclusive', () => {
    for (let i = 0; i < 200; i++) {
      const v = randomStartBatteryPct();
      expect(Number.isInteger(v)).toBe(true);
      expect(v).toBeGreaterThanOrEqual(15);
      expect(v).toBeLessThanOrEqual(55);
    }
  });
});

describe('computeBatteryPct', () => {
  it('adds energy delivered as a percentage of capacity to the starting level', () => {
    // 20 kWh into a 40kWh battery = +50 percentage points
    expect(computeBatteryPct(20, 20)).toBe(70);
  });

  it('caps at 100 even if energy exceeds capacity', () => {
    expect(computeBatteryPct(50, 100)).toBe(100);
  });

  it('handles zero energy delivered', () => {
    expect(computeBatteryPct(35, 0)).toBe(35);
  });
});

describe('isValidAutoStopPct', () => {
  it('accepts multiples of 10 from 10 to 100', () => {
    for (const v of ALLOWED_AUTO_STOP_PCTS) {
      expect(isValidAutoStopPct(v)).toBe(true);
    }
  });

  it('rejects values not in the allowed set', () => {
    expect(isValidAutoStopPct(15)).toBe(false);
    expect(isValidAutoStopPct(0)).toBe(false);
    expect(isValidAutoStopPct(105)).toBe(false);
  });
});
