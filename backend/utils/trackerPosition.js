// Normalizes an inbound GPS position into the shape stored in device_positions.
// The eventual EL-440 TCP decoder and the PoC feeder both hand their output
// through here, so validation lives in one place.

class PositionError extends Error {}

function toFiniteNumber(value) {
  if (value === null || value === undefined || value === '') return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function parseRecordedAt(value) {
  if (value === null || value === undefined || value === '') return new Date();
  // Accept ISO strings, epoch milliseconds, and epoch seconds.
  let date;
  if (typeof value === 'number' || /^\d+$/.test(String(value))) {
    const num = Number(value);
    date = new Date(num < 1e12 ? num * 1000 : num);
  } else {
    date = new Date(value);
  }
  return Number.isNaN(date.getTime()) ? new Date() : date;
}

function normalizePosition(input) {
  if (!input || typeof input !== 'object') {
    throw new PositionError('position payload must be an object');
  }

  const deviceId = String(input.deviceId ?? '').trim();
  if (!deviceId) throw new PositionError('deviceId is required');
  if (deviceId.length > 64) throw new PositionError('deviceId is too long');

  const lat = toFiniteNumber(input.lat);
  const lng = toFiniteNumber(input.lng);
  if (lat === null || lng === null) {
    throw new PositionError('lat and lng are required numbers');
  }
  if (lat < -90 || lat > 90) throw new PositionError('lat out of range');
  if (lng < -180 || lng > 180) throw new PositionError('lng out of range');

  let speedKph = toFiniteNumber(input.speedKph);
  if (speedKph !== null && speedKph < 0) speedKph = 0;

  let headingDeg = toFiniteNumber(input.headingDeg);
  if (headingDeg !== null) headingDeg = ((headingDeg % 360) + 360) % 360;

  return {
    deviceId,
    lat,
    lng,
    speedKph,
    headingDeg,
    recordedAt: parseRecordedAt(input.recordedAt),
    raw: input.raw ?? null,
  };
}

module.exports = { normalizePosition, PositionError };
