// Parses the SMS the Atlanta EL-440 sends back in response to a
// "GETGPS<password>" command. Two shapes seen from the real device:
//
//   IMEI: 864688053456114
//   CCID: 8991000924358270430F
//   http://maps.google.com/maps?q=17.490170,78.441620
//   DATE: 090926
//   TIME(GMT): 063651
//   SPEED: 0.000000
//
//   IMEI: 864688053456114
//   CCID: 8991000924358270430F
//   GPS INVALID
//   LAST VALID LAT_LONG
//   http://maps.google.com/maps?q=0.000000,0.000000

function parseGetGpsReply(text) {
  if (typeof text !== 'string') return null;

  const imei = text.match(/IMEI:\s*(\d+)/i);
  if (!imei) return null; // not a GETGPS reply

  const deviceId = imei[1];

  const coords = text.match(/maps\?q=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/i);
  const lat = coords ? Number(coords[1]) : null;
  const lng = coords ? Number(coords[2]) : null;

  const invalid = /GPS\s+INVALID/i.test(text) || lat === null || lng === null || (lat === 0 && lng === 0);
  if (invalid) {
    return { deviceId, valid: false };
  }

  let speedKph = null;
  const speed = text.match(/SPEED:\s*([\d.]+)/i);
  if (speed) speedKph = Number(speed[1]);

  let recordedAt = null;
  const date = text.match(/DATE:\s*(\d{2})(\d{2})(\d{2})/i);        // DDMMYY
  const time = text.match(/TIME\(GMT\):\s*(\d{2})(\d{2})(\d{2})/i); // HHMMSS
  if (date && time) {
    const [, dd, mm, yy] = date;
    const [, hh, mi, ss] = time;
    recordedAt = new Date(Date.UTC(2000 + Number(yy), Number(mm) - 1, Number(dd), Number(hh), Number(mi), Number(ss)));
  }

  return { deviceId, valid: true, lat, lng, speedKph, recordedAt };
}

module.exports = { parseGetGpsReply };
