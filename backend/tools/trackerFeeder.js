/*
 * PoC position feeder — stands in for the EL-440 until Atlanta hands over
 * the ATL protocol spec and we can build the real TCP decoder.
 *
 * Simulates one device driving a loop around Hyderabad, POSTing a fix to
 * /api/tracker/ingest every few seconds. Same endpoint the real decoder
 * will call, so the app / DB / map path is exactly what ships.
 *
 *   node tools/trackerFeeder.js
 *   API_BASE_URL=https://ecocharge-j8fp.onrender.com node tools/trackerFeeder.js
 */
require('dotenv').config();

const API_BASE_URL = process.env.API_BASE_URL || `http://localhost:${process.env.PORT || 4000}`;
const INGEST_KEY = process.env.TRACKER_INGEST_KEY;
const DEVICE_ID = process.env.DEMO_TRACKER_DEVICE_ID || 'EL440-DEMO';
const INTERVAL_MS = Number(process.env.FEED_INTERVAL_MS || 4000);

if (!INGEST_KEY) {
  console.error('TRACKER_INGEST_KEY is not set — see .env.example');
  process.exit(1);
}

// A rough rectangular loop around central Hyderabad.
const WAYPOINTS = [
  { lat: 17.4239, lng: 78.4483 }, // Banjara Hills
  { lat: 17.4375, lng: 78.4482 }, // Jubilee Hills
  { lat: 17.4416, lng: 78.3804 }, // Gachibowli
  { lat: 17.4065, lng: 78.3772 }, // Financial District
  { lat: 17.3850, lng: 78.4867 }, // City centre
  { lat: 17.4062, lng: 78.4691 }, // Khairatabad
];

let leg = 0;
let t = 0; // 0..1 progress along the current leg

function nextPosition() {
  const from = WAYPOINTS[leg];
  const to = WAYPOINTS[(leg + 1) % WAYPOINTS.length];

  const lat = from.lat + (to.lat - from.lat) * t;
  const lng = from.lng + (to.lng - from.lng) * t;
  const headingDeg = (Math.atan2(to.lng - from.lng, to.lat - from.lat) * 180) / Math.PI;
  const speedKph = 25 + Math.random() * 20;

  t += 0.12;
  if (t >= 1) { t = 0; leg = (leg + 1) % WAYPOINTS.length; }

  return { deviceId: DEVICE_ID, lat, lng, speedKph, headingDeg, recordedAt: new Date().toISOString() };
}

async function tick() {
  const pos = nextPosition();
  try {
    const res = await fetch(`${API_BASE_URL}/api/tracker/ingest`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-ingest-key': INGEST_KEY },
      body: JSON.stringify(pos),
    });
    const body = await res.json().catch(() => ({}));
    console.log(
      `${res.status}  ${pos.lat.toFixed(5)}, ${pos.lng.toFixed(5)}  ${pos.speedKph.toFixed(0)} kph` +
        (res.ok ? `  id=${body.id}` : `  ${JSON.stringify(body)}`)
    );
  } catch (err) {
    console.error('feed failed:', err.message);
  }
}

console.log(`Feeding ${DEVICE_ID} -> ${API_BASE_URL} every ${INTERVAL_MS}ms. Ctrl+C to stop.`);
tick();
setInterval(tick, INTERVAL_MS);
