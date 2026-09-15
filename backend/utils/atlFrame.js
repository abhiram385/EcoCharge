// Parses frames from the Atlanta EL-440's raw GPRS/TCP stream ("ATL" mode).
// Reverse-engineered from a live capture — Atlanta never published a spec,
// but the position frame turns out to be a standard NMEA $GPRMC sentence
// wrapped in a thin ASCII envelope, not a binary format:
//
//   <IMEI>,$GPRMC,<hhmmss>,<A|V>,<ddmm.mmmm>,<N|S>,<dddmm.mmmm>,<E|W>,
//     <speedKnots>,<headingDeg>,<ddmmyy>,,,*<checksum>,<...cell/battery info>
//
// Two other frame types share the connection (ATLCAN = OBD/CAN diagnostics,
// ATLSER = a heartbeat) — neither carries a position, so they parse to null.

const GPRMC_RE =
  /ATL(\d{10,17}),\$GPRMC,(\d{6})(?:\.\d+)?,([AV]),(\d{2})(\d{2}\.\d+),([NS]),(\d{3})(\d{2}\.\d+),([EW]),([\d.]*),([\d.]*),(\d{6}),/;

function parseAtlFrame(buffer) {
  if (!buffer || buffer.length === 0) return null;
  const text = buffer.toString('latin1');

  const m = text.match(GPRMC_RE);
  if (!m) return null;

  const [, imei, timeStr, status, latDeg, latMin, ns, lonDeg, lonMin, ew, speedStr, headingStr, dateStr] = m;

  if (status !== 'A') {
    return { deviceId: imei, valid: false };
  }

  let lat = Number(latDeg) + Number(latMin) / 60;
  if (ns === 'S') lat = -lat;
  let lng = Number(lonDeg) + Number(lonMin) / 60;
  if (ew === 'W') lng = -lng;

  const speedKnots = speedStr ? Number(speedStr) : 0;
  const headingDeg = headingStr ? Number(headingStr) : null;

  const dd = dateStr.slice(0, 2);
  const mo = dateStr.slice(2, 4);
  const yy = dateStr.slice(4, 6);
  const hh = timeStr.slice(0, 2);
  const mi = timeStr.slice(2, 4);
  const ss = timeStr.slice(4, 6);
  const recordedAt = new Date(Date.UTC(2000 + Number(yy), Number(mo) - 1, Number(dd), Number(hh), Number(mi), Number(ss)));

  return {
    deviceId: imei,
    valid: true,
    lat,
    lng,
    speedKph: speedKnots * 1.852,
    headingDeg,
    recordedAt,
  };
}

module.exports = { parseAtlFrame };
