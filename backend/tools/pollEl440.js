/*
 * Polls the real EL-440 by SMS: sends "GETGPS<password>" to the device's SIM
 * every interval via the SMS Gateway for Android API. The device replies with
 * a position SMS to the gateway phone, which forwards it to
 * /api/tracker/sms-hook — so this script only needs to fire the request.
 *
 * The SMS round trip is ~20-40s, so intervals below ~40s just pile up
 * unanswered commands. This is a demo bridge until the GPRS stream works.
 *
 *   node tools/pollEl440.js
 */
require('dotenv').config();

const GATEWAY_URL = process.env.SMS_GATEWAY_URL || 'https://api.sms-gate.app/3rdparty/v1';
const USER = process.env.SMS_GATEWAY_USER;
const PASSWORD = process.env.SMS_GATEWAY_PASSWORD;
const DEVICE_NUMBER = process.env.EL440_DEVICE_NUMBER;
const GETGPS_PASSWORD = process.env.EL440_GETGPS_PASSWORD;
const INTERVAL_MS = Number(process.env.POLL_INTERVAL_MS || 45000);

for (const [name, val] of Object.entries({
  SMS_GATEWAY_USER: USER,
  SMS_GATEWAY_PASSWORD: PASSWORD,
  EL440_DEVICE_NUMBER: DEVICE_NUMBER,
  EL440_GETGPS_PASSWORD: GETGPS_PASSWORD,
})) {
  if (!val) {
    console.error(`${name} is not set — see .env.example`);
    process.exit(1);
  }
}

const auth = 'Basic ' + Buffer.from(`${USER}:${PASSWORD}`).toString('base64');
const command = `GETGPS${GETGPS_PASSWORD}`;

async function poll() {
  try {
    const res = await fetch(`${GATEWAY_URL.replace(/\/$/, '')}/message`, {
      method: 'POST',
      headers: { Authorization: auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ textMessage: { text: command }, phoneNumbers: [DEVICE_NUMBER] }),
    });
    const body = await res.json().catch(() => ({}));
    console.log(`${new Date().toISOString()}  sent ${command} -> ${DEVICE_NUMBER}  [${res.status}]  ${body.id || JSON.stringify(body)}`);
  } catch (err) {
    console.error('poll failed:', err.message);
  }
}

console.log(`Polling EL-440 (${DEVICE_NUMBER}) every ${INTERVAL_MS}ms via ${GATEWAY_URL}. Ctrl+C to stop.`);
poll();
setInterval(poll, INTERVAL_MS);
