/*
 * Production replacement for tools/tcp_capture.py — the real EL-440 GPRS
 * decoder. The device streams to this server (set via #serverchange +
 * WEBSTART on the device), each $GPRMC position frame gets parsed with
 * utils/atlFrame.js and POSTed straight to /api/tracker/ingest. This is the
 * genuinely-live path: no SMS, no polling, a fresh fix every WEBSTART
 * interval (currently 10s).
 *
 * Run on the same public host the device is pointed at:
 *   API_BASE_URL=https://ecocharge-j8fp.onrender.com \
 *   TRACKER_INGEST_KEY=<key> \
 *   node tools/atlTcpServer.js
 */
require('dotenv').config();
const net = require('net');
const { parseAtlFrame } = require('../utils/atlFrame');

const PORT = Number(process.env.ATL_TCP_PORT || 5001);
const API_BASE_URL = process.env.API_BASE_URL || `http://localhost:${process.env.BACKEND_PORT || 4000}`;
const INGEST_KEY = process.env.TRACKER_INGEST_KEY;

if (!INGEST_KEY) {
  console.error('TRACKER_INGEST_KEY is not set — see .env.example');
  process.exit(1);
}

async function ingest(position) {
  try {
    const res = await fetch(`${API_BASE_URL}/api/tracker/ingest`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-ingest-key': INGEST_KEY },
      body: JSON.stringify({
        deviceId: position.deviceId,
        lat: position.lat,
        lng: position.lng,
        speedKph: position.speedKph,
        headingDeg: position.headingDeg,
        recordedAt: position.recordedAt.toISOString(),
        raw: { source: 'atl-gprs-stream' },
      }),
    });
    const status = res.ok ? 'ok' : `HTTP ${res.status}`;
    console.log(
      `[${new Date().toISOString()}] ${position.deviceId}  ${position.lat.toFixed(6)},${position.lng.toFixed(6)}` +
        `  ${position.speedKph.toFixed(1)}kph  -> ingest ${status}`
    );
  } catch (err) {
    console.error('ingest failed:', err.message);
  }
}

const server = net.createServer((socket) => {
  const peer = `${socket.remoteAddress}:${socket.remotePort}`;
  console.log(`connect ${peer}`);

  socket.on('data', (chunk) => {
    const parsed = parseAtlFrame(chunk);
    if (!parsed) return; // ATLCAN / ATLSER / anything else we don't care about
    if (!parsed.valid) {
      console.log(`${peer}  ${parsed.deviceId}  GPS void, skipping`);
      return;
    }
    ingest(parsed);
  });

  socket.on('error', (err) => console.log(`${peer} socket error: ${err.message}`));
  socket.on('close', () => console.log(`disconnect ${peer}`));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`ATL decoder listening on 0.0.0.0:${PORT}, forwarding to ${API_BASE_URL}`);
});
