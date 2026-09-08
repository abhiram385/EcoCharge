# EcoCharge

An EV charging station finder & booking app — find nearby stations, book a
charging slot, start/stop a live charging session, and manage your wallet.

Visual identity is a light, warm "Meadow" theme (cream backgrounds, leaf
green + coral/amber accents) — deliberately different from typical dark,
industrial EV-app styling.

```
ecocharge/
├── backend/     Node.js + Express + PostgreSQL REST API
└── frontend/    Flutter mobile app (iOS + Android)
```

## Features

- **Phone OTP login** — passwordless sign-in via SMS code
- **Explore** — nearby charging stations as a list or interactive map
- **Station details** — connector types, power, live availability, pricing, amenities
- **Book a slot** — pick a date/time and reserve a specific connector
- **Charge now** — start a live session with a real-time energy/cost gauge
- **Wallet** — top up balance, auto-debit on session stop, transaction history
- **History** — past charging sessions and bookings

## Backend setup

```bash
cd backend
cp .env.example .env      # then edit DATABASE_URL, JWT_SECRET, etc.
npm install

# Create the Postgres database first, e.g.:
#   createdb ecocharge
npm run migrate            # applies versioned migrations in backend/db/migrations
npm run db:seed            # optional: demo Bhopal stations (dev convenience, not run in prod)

npm run dev                # http://localhost:4000
```

Health check: `GET http://localhost:4000/health`

### Wiring up real SMS

OTP delivery goes through `utils/sms.js`. By default (`SMS_PROVIDER=console`,
or unset) it logs the code to the console instead of sending SMS, so you can
test without an SMS account — codes are also returned in the API response
when `EXPOSE_OTP_IN_RESPONSE=true`.

To send real texts, use [SMS Gateway for Android](https://sms-gate.app) — no
DLT, no KYC, sends from a phone's own SIM:

1. Install the app on an Android phone that stays powered on with signal
   (Play Store, F-Droid, or the GitHub APK).
2. Enable **Cloud Server**, tap **Online**. The Cloud Server section then shows
   a username and password.
3. Set these in `.env` and deploy config:

   ```bash
   SMS_PROVIDER=smsgateway
   SMS_GATEWAY_USER=<from the app>
   SMS_GATEWAY_PASSWORD=<from the app>
   ```

Numbers are normalized to E.164 (`+91` is added to bare 10-digit numbers). In
cloud mode the message passes through the sms-gate.app relay before the phone
sends it; for a stricter setup run the app in local mode and set
`SMS_GATEWAY_URL=http://<phone-ip>:8080/3rdparty/v1` (backend must reach that
address).

No code changes needed to switch — `request-otp` returns `502` if the SMS
provider fails to send, so a failed delivery isn't reported to the client as
success.

### API summary

| Method | Path                          | Description                       |
|--------|-------------------------------|------------------------------------|
| POST   | /api/auth/request-otp         | Send OTP to a phone number         |
| POST   | /api/auth/verify-otp          | Verify OTP, returns JWT            |
| GET    | /api/stations/nearby          | Stations near lat/lng              |
| GET    | /api/stations/:id             | Station + its connectors           |
| GET    | /api/vehicles                 | List your vehicles                 |
| POST   | /api/vehicles                 | Add a vehicle                      |
| DELETE | /api/vehicles/:id             | Remove a vehicle                   |
| POST   | /api/bookings                 | Book a connector slot              |
| GET    | /api/bookings                 | List your bookings                 |
| POST   | /api/bookings/:id/cancel      | Cancel a booking                   |
| POST   | /api/sessions/start           | Start a live charging session      |
| GET    | /api/sessions/active           | Get your current active session    |
| POST   | /api/sessions/:id/stop         | Stop session & debit wallet        |
| GET    | /api/sessions/history          | Past charging sessions             |
| GET    | /api/wallet                    | Balance + transactions             |
| POST   | /api/wallet/topup              | Add money to wallet                |

All routes except `/api/auth/*` require `Authorization: Bearer <token>`.

## Frontend setup

Requires Flutter 3.x installed.

```bash
cd frontend
flutter create .            # generates platform folders (android/ios/etc.) matching this pubspec
flutter pub get
```

Then:
1. Add a Google Maps API key:
   - Android: replace `YOUR_GOOGLE_MAPS_API_KEY` in `android/app/src/main/AndroidManifest.xml`
   - iOS: add your key in `AppDelegate.swift` per the `google_maps_flutter` docs
2. Add the location usage description from `ios/Runner/Info.plist.snippet.xml`
   into the generated `ios/Runner/Info.plist`.
3. Point the app at your backend:
   ```bash
   flutter run --dart-define=API_BASE_URL=http://localhost:4000
   ```
   (Android emulator defaults to `http://10.0.2.2:4000` automatically if you
   don't pass this flag — see `lib/services/api_service.dart`.)

## Project structure (frontend)

```
lib/
├── main.dart
├── theme/app_theme.dart        # colors, typography, component themes
├── models/                     # Station, Vehicle, Booking, Session, Wallet
├── services/api_service.dart   # single HTTP client for the whole app
├── providers/                  # Provider/ChangeNotifier state
└── screens/
    ├── splash_screen.dart
    ├── auth/                   # phone entry + OTP verify
    ├── home/                   # bottom-nav shell + explore (map/list)
    ├── station/                # station detail + connectors
    ├── booking/                # slot booking flow
    ├── session/                # live charging session screen
    ├── wallet/                 # balance + top-up + transactions
    ├── history/                # past sessions & bookings
    └── profile/                # vehicles + logout
```

## Notes for production

- Move wallet top-ups behind a real payment gateway webhook rather than a
  direct client-triggered credit (flagged in `routes/wallet.js`).
- Swap the demo energy-delivery simulation in `routes/sessions.js` for real
  OCPP/charger-hardware telemetry once you're integrating with real chargers.
- Add refresh-token rotation and rate limiting tuned to your traffic.
- Replace the seeded Bhopal demo stations in `db/seed.sql` with your real network.
