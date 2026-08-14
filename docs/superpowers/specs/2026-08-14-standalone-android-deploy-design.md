# Standalone Android deployment — design

Status: approved
Date: 2026-08-14

## Context

EcoCharge currently only runs via `flutter run` against a backend started
with `npm run dev` on the developer's laptop. `frontend/lib/services/api_service.dart`
hardcodes `baseUrl` to `http://192.168.29.1:4000` (the laptop's LAN IP),
so the app only works when the phone is on the same wifi as a laptop that
has the backend running — it stops working the moment either is off. This
spec makes the app fully standalone on a physical Android device: a
permanently-hosted backend, a proper signed release APK, and no
dependency on USB/wifi-to-laptop ever again.

Scope is personal use only (not Play Store): the phone is the only
client, so a couple of shortcuts that wouldn't be appropriate for a
multi-user production app (see OTP delivery, below) are acceptable here.

Two small, unrelated issues surfaced during this conversation and are
bundled in since they only matter once the app is used on a real device:
a stations-list loading delay, and switching the demo seed data from
Bhopal to Hyderabad.

## Hosting: Render (backend) + Neon (Postgres)

- Backend deploys to Render's free web service tier, connected to this
  repo, giving a permanent `https://<name>.onrender.com` HTTPS URL. No
  server maintenance. Trade-off: the free tier sleeps after ~15 min
  idle; the first request after a gap takes ~30-50s to wake, which is
  fine for personal use.
- Database is a free Neon Postgres instance rather than Render's own
  free Postgres, because Render's free Postgres auto-deletes after 90
  days — Neon's free tier persists indefinitely (it pauses on
  inactivity but auto-resumes on connect).
- `npm run migrate` (already exists — applies `schema.sql` + `seed.sql`)
  runs once against the Neon `DATABASE_URL` to provision the deployed
  database.

## Backend code changes

- `backend/db/pool.js` — Neon requires SSL. Add SSL to the `Pool` config,
  gated by a `DB_SSL=true` env var so local dev (no SSL) is untouched:
  ```js
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
  });
  ```
- `backend/routes/auth.js` — decouple returning the OTP in the API
  response from `NODE_ENV=development`. Today `isDevOtpAllowed` requires
  dev mode, which would force the deployed instance to run as
  `NODE_ENV=development` just to get the OTP back (losing production
  logging behavior in `server.js`). Replace with an explicit
  `EXPOSE_OTP_IN_RESPONSE=true` env var, independent of `NODE_ENV`:
  ```js
  const isDevOtpAllowed = process.env.EXPOSE_OTP_IN_RESPONSE === 'true';
  ```
  Deployed env: `NODE_ENV=production`, `EXPOSE_OTP_IN_RESPONSE=true`,
  `SMS_PROVIDER=console` (unchanged — still just logs server-side too).
- No other backend logic, schema, or route changes.

## Frontend changes

**Base URL fix** — `api_service.dart` currently hardcodes the LAN IP and
silently ignores `--dart-define=API_BASE_URL` despite the README
documenting that flag. Fix it to actually read the define, defaulting to
the deployed Render URL so a plain `flutter build apk --release` (no
flags needed) points at production:
```dart
static const baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://<render-service-name>.onrender.com',
);
```

**OTP entry screen** (`screens/auth/otp_verify_screen.dart`) — since OTP
now arrives in the `request-otp` response body instead of SMS, surface
`devOtp` there (e.g. pre-fill the code field, or show it as helper text)
instead of the user expecting a text message.

## Build & install

1. Generate an Android signing keystore (`keytool -genkey ...`).
2. Wire it into `frontend/android/app/build.gradle.kts` via a
   `key.properties` file (standard Flutter release-signing setup).
3. `flutter build apk --release` → signed standalone APK.
4. Install once via `adb install` (USB) or by copying the APK to the
   phone and enabling "install unknown apps." After this the phone
   never needs the laptop again — the APK only talks to the internet.

Prerequisite outside this spec's scope: a Google Maps API key is still
required for the Explore map screen (per the existing README) — the user
needs to obtain this from Google Cloud Console themselves.

## Bug investigation: stations list slow to load

Not a backend bug. `GET /api/stations/nearby`'s Haversine query runs in
milliseconds over the ~5 seeded rows. The delay is in
`frontend/lib/screens/home/home_screen.dart:56-74`
(`_loadLocationAndStations`): it `await`s
`Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium)`
and only calls `StationProvider.loadNearby(...)` after that resolves. On
an emulator, mock GPS returns instantly; on a real device, getting an
actual GPS fix — even at medium accuracy — can take several seconds
(worse indoors / cold start), and nothing loads on screen until then.

**Fix:** don't block the stations fetch on a precise GPS fix.
- Try `Geolocator.getLastKnownPosition()` first (near-instant, may be
  null on a fresh install) and, if available, kick off `loadNearby`
  immediately with it.
- If no last-known position, kick off `loadNearby` immediately with the
  default fallback center (see below) so the list is never empty-and-
  waiting.
- Concurrently (not blocking the above), fetch `getCurrentPosition()`
  and, once resolved, call `loadNearby` again with the accurate
  coordinates and update `_center`/the map. `StationProvider.loadNearby`
  already fully replaces `stations` on each call, so a second call is a
  safe, simple refresh — no new state needed.

## Hyderabad demo data

- `backend/db/seed.sql` — replace the 5 Bhopal stations with 5 Hyderabad
  equivalents at real landmark coordinates, keeping the same structure
  (name, address, city, lat/lng, rating, 24h flag, amenities) and the
  same per-station connector inserts (types/power/price/status
  unchanged, just re-keyed to the new station names):
  - Banjara Hills Green Hub — Road No. 12, Banjara Hills — 17.4156, 78.4347
  - Hitech City Fast Charge — near Cyber Towers, Hitech City — 17.4435, 78.3772
  - Gachibowli Charge Point — DLF Cyber City, Gachibowli — 17.4401, 78.3489
  - Jubilee Hills Station — Road No. 36, Jubilee Hills — 17.4325, 78.4071
  - Secunderabad Rail Charge — near Secunderabad Railway Station — 17.4399, 78.5019
- `frontend/lib/screens/home/home_screen.dart:25` — default fallback
  `_center` changes from `LatLng(23.2599, 77.4126) // Bhopal` to
  `LatLng(17.3850, 78.4867) // Hyderabad`, so the pre-GPS/no-GPS fallback
  view matches the seeded stations.

## Testing

- Backend: `npm run migrate` against the Neon `DATABASE_URL` locally
  first to confirm schema + new Hyderabad seed apply cleanly; hit
  `GET /health` and `POST /api/auth/request-otp` against the deployed
  Render URL directly (curl) to confirm `EXPOSE_OTP_IN_RESPONSE` and SSL
  DB connectivity both work end to end.
- Frontend: `flutter analyze`. Build the release APK and install on the
  physical device.
- Manual device walkthrough, phone off home wifi (mobile data): OTP
  login using the code returned in-app, stations list appears
  immediately (before/without waiting on GPS) and is Hyderabad-based,
  browse a station, book a slot, start/stop a charging session, wallet
  top-up. Confirm the app still works after fully closing it and
  reopening with no laptop nearby.
