const crypto = require('crypto');

const BATTERY_CAPACITY_KWH = 40;
const ALLOWED_AUTO_STOP_PCTS = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];

function randomStartBatteryPct() {
  return crypto.randomInt(15, 56); // 15–55 inclusive (upper bound is exclusive)
}

function computeBatteryPct(startBatteryPct, energyKwh) {
  const pct = Number(startBatteryPct) + (Number(energyKwh) / BATTERY_CAPACITY_KWH) * 100;
  return Math.min(100, pct);
}

function isValidAutoStopPct(value) {
  return ALLOWED_AUTO_STOP_PCTS.includes(value);
}

module.exports = {
  BATTERY_CAPACITY_KWH,
  ALLOWED_AUTO_STOP_PCTS,
  randomStartBatteryPct,
  computeBatteryPct,
  isValidAutoStopPct,
};
