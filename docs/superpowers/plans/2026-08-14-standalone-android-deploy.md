# Standalone Android Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make EcoCharge run as a fully standalone app on a physical Android phone — permanently hosted backend, no dependency on a laptop over USB or wifi.

**Architecture:** Deploy the existing Express backend to Render (free tier) backed by a free Neon Postgres database; fix a hardcoded LAN IP in the Flutter client so release builds point at that deployed URL by default; switch OTP delivery from console-only to being returned in the API response (personal single-user use, no SMS provider needed); build and sign a release APK for direct install. Bundled in: a stations-list load-delay fix and swapping demo seed data from Bhopal to Hyderabad.

**Tech Stack:** Node.js/Express/PostgreSQL backend (`pg`, already using `dotenv`), Flutter/Dart frontend (`http`, `geolocator`, `provider`), Render + Neon for hosting.

**Spec:** `docs/superpowers/specs/2026-08-14-standalone-android-deploy-design.md`

## Global Constraints

- Personal use only — no Play Store, no multi-user concerns. OTP-in-response is acceptable specifically because of this.
- Local development flow (`npm run dev` against local Postgres, `flutter run` against `10.0.2.2`/localhost) must keep working unchanged — all new behavior is opt-in via env vars, not a replacement of existing dev defaults where one already worked correctly.
- No new test frameworks/infra — this repo verifies backend route behavior via manual curl (see existing specs), not integration tests against a live DB. Follow that pattern; don't introduce supertest-based route tests.

---

### Task 1: SSL-aware database pool

**Files:**
- Modify: `backend/db/pool.js`
- Modify: `backend/.env.example`

**Interfaces:**
- Produces: `pool` (unchanged export, `{ pool }` from `backend/db/pool.js`) — behavior only, no signature change. Reads a new env var `DB_SSL` (`'true'` | unset).

- [ ] **Step 1: Update `backend/db/pool.js` to make SSL opt-in via env var**

Replace the full file contents:

```js
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

module.exports = { pool };
```

- [ ] **Step 2: Document the new env var in `.env.example`**

Add this line to `backend/.env.example`, after `DATABASE_URL=...`:

```
DB_SSL=false
```

Resulting `DATABASE_URL`/`DB_SSL` block should read:

```
DATABASE_URL=postgres://ecocharge_user:ecocharge_pass@localhost:5432/ecocharge
DB_SSL=false
```

- [ ] **Step 3: Verify nothing broke**

Run: `cd backend && npm test`
Expected: all existing suites still pass (`pool.js` isn't imported by any test — they mock a plain `{ query, connect }` object — so this is a no-op check, but confirms no accidental syntax error).

- [ ] **Step 4: Commit**

```bash
git add backend/db/pool.js backend/.env.example
git commit -m "feat: make backend db pool SSL opt-in via DB_SSL env var"
```

---

### Task 2: Decouple OTP-in-response from NODE_ENV

**Files:**
- Modify: `backend/routes/auth.js:17`
- Modify: `backend/routes/auth.js:46-48` (comment)
- Modify: `backend/.env.example`

**Interfaces:**
- Produces: `POST /api/auth/request-otp` response gains `devOtp` (string, the code) whenever `EXPOSE_OTP_IN_RESPONSE=true`, regardless of `NODE_ENV`. Response shape otherwise unchanged: `{ message: string, devOtp?: string }`.

- [ ] **Step 1: Replace the `NODE_ENV`-based gate with an explicit env var**

In `backend/routes/auth.js`, change line 17 from:

```js
const isDevOtpAllowed = process.env.NODE_ENV === 'development' && process.env.SMS_PROVIDER === 'console';
```

to:

```js
const isDevOtpAllowed = process.env.EXPOSE_OTP_IN_RESPONSE === 'true';
```

- [ ] **Step 2: Update the comment above the `devOtp` field (lines 46-48)**

Change:

```js
    // Only included when NODE_ENV=development AND no real SMS provider is configured,
    // so a misconfigured staging/prod deploy can never leak the code.
    devOtp: isDevOtpAllowed ? code : undefined,
```

to:

```js
    // Only included when EXPOSE_OTP_IN_RESPONSE=true is explicitly set, independent
    // of NODE_ENV, so a deployed instance can run NODE_ENV=production (correct
    // logging/perf behavior) while still opting into returning the code — this app
    // is personal/single-user, so there's no real security concern in doing so.
    devOtp: isDevOtpAllowed ? code : undefined,
```

- [ ] **Step 3: Add the new env var to `.env.example`**

Add after `SMS_PROVIDER=console`:

```
EXPOSE_OTP_IN_RESPONSE=true
```

- [ ] **Step 4: Verify locally with curl**

Ensure `backend/.env` has `EXPOSE_OTP_IN_RESPONSE=true` (copy from the updated `.env.example` or add manually), then:

Run: `cd backend && npm run dev`
In another terminal: `curl -X POST http://localhost:4000/api/auth/request-otp -H "Content-Type: application/json" -d '{"phone":"+919876543210"}'`
Expected: JSON response includes a `devOtp` field with a 6-digit code, e.g. `{"message":"OTP sent successfully","devOtp":"482913"}`.

Then set `EXPOSE_OTP_IN_RESPONSE=false` in `.env`, restart `npm run dev`, repeat the curl.
Expected: response has no `devOtp` field (or it's `null`/absent), e.g. `{"message":"OTP sent successfully"}`.

Restore `.env` to `EXPOSE_OTP_IN_RESPONSE=true` afterward (needed for later end-to-end testing).

- [ ] **Step 5: Commit**

```bash
git add backend/routes/auth.js backend/.env.example
git commit -m "feat: gate devOtp response field on EXPOSE_OTP_IN_RESPONSE instead of NODE_ENV"
```

---

### Task 3: Hyderabad demo seed data

**Files:**
- Modify: `backend/db/seed.sql`

**Interfaces:** None (data-only change; `stations`/`connectors` schema unchanged).

- [ ] **Step 1: Replace the Bhopal stations with Hyderabad stations**

Replace the full contents of `backend/db/seed.sql`:

```sql
-- Demo seed data centered around Hyderabad, Telangana for local testing.
-- Feel free to replace with real station data per city.

INSERT INTO stations (name, address, city, latitude, longitude, rating, is_open_24h, amenities)
VALUES
 ('Banjara Hills Green Hub', 'Road No. 12, Banjara Hills', 'Hyderabad', 17.4156, 78.4347, 4.7, TRUE, ARRAY['Cafe','Restroom','WiFi']),
 ('Hitech City Fast Charge', 'Near Cyber Towers, Hitech City', 'Hyderabad', 17.4435, 78.3772, 4.5, TRUE, ARRAY['Mall','Restroom']),
 ('Gachibowli Charge Point', 'DLF Cyber City, Gachibowli', 'Hyderabad', 17.4401, 78.3489, 4.3, TRUE, ARRAY['Cafe']),
 ('Jubilee Hills Station', 'Road No. 36, Jubilee Hills', 'Hyderabad', 17.4325, 78.4071, 4.2, FALSE, ARRAY['Restroom']),
 ('Secunderabad Rail Charge', 'Near Secunderabad Railway Station', 'Hyderabad', 17.4399, 78.5019, 4.6, TRUE, ARRAY['WiFi','Restroom','Cafe'])
ON CONFLICT DO NOTHING;

-- Attach a couple of connectors to each station
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 60, 18.50, 'available' FROM stations WHERE name = 'Banjara Hills Green Hub';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 14.00, 'available' FROM stations WHERE name = 'Banjara Hills Green Hub';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 50, 19.00, 'occupied' FROM stations WHERE name = 'Hitech City Fast Charge';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CHAdeMO', 50, 19.00, 'available' FROM stations WHERE name = 'Hitech City Fast Charge';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 13.50, 'available' FROM stations WHERE name = 'Gachibowli Charge Point';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 30, 16.00, 'offline' FROM stations WHERE name = 'Jubilee Hills Station';

INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'CCS2', 120, 21.00, 'available' FROM stations WHERE name = 'Secunderabad Rail Charge';
INSERT INTO connectors (station_id, connector_type, power_kw, price_per_kwh, status)
SELECT id, 'Type2', 22, 14.50, 'available' FROM stations WHERE name = 'Secunderabad Rail Charge';
```

- [ ] **Step 2: Re-run migration locally and verify**

Run: `cd backend && npm run migrate`
Expected: `Applying schema...` / `Seeding demo data...` / `Done.` with no errors (schema uses `CREATE TABLE IF NOT EXISTS` and seed uses `ON CONFLICT DO NOTHING`, so re-running is safe even with old Bhopal rows already present — check the result explicitly in the next step).

Run: `psql "$DATABASE_URL" -c "SELECT name, city FROM stations ORDER BY name;"` (or open the table via any Postgres client)
Expected: 5 Hyderabad-named stations. If old Bhopal rows are still present from earlier local testing, delete them manually: `psql "$DATABASE_URL" -c "DELETE FROM stations WHERE city = 'Bhopal';"` (`connectors.station_id` has `ON DELETE CASCADE` per `backend/db/schema.sql:58`, so their connectors are removed automatically. `bookings`/`charging_sessions` reference `station_id` *without* cascade, though — if local testing already created a booking or session against a Bhopal station, this delete fails with a foreign-key violation; if that happens, delete those specific booking/session rows first, or just drop and recreate your local dev database from scratch since this is disposable test data).

- [ ] **Step 3: Commit**

```bash
git add backend/db/seed.sql
git commit -m "feat: switch demo seed stations from Bhopal to Hyderabad"
```

---

### Task 4: Deploy backend to Render + Neon

**Files:** None (infrastructure/configuration task — no repo files change beyond what Tasks 1-3 already committed).

**Interfaces:**
- Produces: a live HTTPS backend URL (e.g. `https://ecocharge-api.onrender.com`) that Task 5 hardcodes as the Flutter app's default `API_BASE_URL`.

- [ ] **Step 1: Create the Neon Postgres database**

Go to https://neon.tech, sign up/log in, create a new project (e.g. named `ecocharge`). Copy the connection string it gives you (starts with `postgres://` and includes `?sslmode=require`) — this is your production `DATABASE_URL`.

- [ ] **Step 2: Apply schema + seed to Neon**

Locally, temporarily point `backend/.env` at the Neon database:

```
DATABASE_URL=<paste the Neon connection string here>
DB_SSL=true
```

Run: `cd backend && npm run migrate`
Expected: `Applying schema...` / `Seeding demo data...` / `Done.` with no errors — this creates all tables and the 5 Hyderabad stations on Neon.

Afterward, revert `backend/.env`'s `DATABASE_URL`/`DB_SSL` back to your local Postgres values so local `npm run dev` keeps working against your local DB.

- [ ] **Step 3: Create the Render web service**

Go to https://render.com, sign up/log in, create a new **Web Service** connected to this repo (or a pushed copy of it — Render needs git access). Configure:
- Root directory: `backend`
- Build command: `npm install`
- Start command: `npm start`
- Instance type: Free

- [ ] **Step 4: Set environment variables on Render**

In the Render service's Environment settings, add:

```
DATABASE_URL=<the same Neon connection string from Step 1>
DB_SSL=true
JWT_SECRET=<generate a new long random value — do not reuse your local dev secret>
JWT_EXPIRES_IN=30d
OTP_EXPIRY_MINUTES=5
SMS_PROVIDER=console
EXPOSE_OTP_IN_RESPONSE=true
NODE_ENV=production
```

(`PORT` does not need to be set — Render injects it automatically and `server.js:38` already reads `process.env.PORT`.)

Deploy/redeploy the service so these take effect.

- [ ] **Step 5: Verify the deployed backend end-to-end with curl**

Run (replace with your actual Render URL):

```bash
curl https://<your-render-url>.onrender.com/health
```
Expected: `{"status":"ok","service":"ecocharge-backend"}` (allow up to ~50s on the first request if the free instance was asleep).

```bash
curl -X POST https://<your-render-url>.onrender.com/api/auth/request-otp \
  -H "Content-Type: application/json" \
  -d '{"phone":"+919876543210"}'
```
Expected: `{"message":"OTP sent successfully","devOtp":"<6-digit code>"}` — confirms the deployed instance can reach Neon over SSL and `EXPOSE_OTP_IN_RESPONSE` is wired correctly in production.

- [ ] **Step 6: Record the URL**

Note the exact `https://<your-render-url>.onrender.com` value — Task 5's Step 1 needs it verbatim.

---

### Task 5: Fix frontend base URL to respect `--dart-define` and default to the deployed backend

**Files:**
- Modify: `frontend/lib/services/api_service.dart:9-10`

**Interfaces:**
- Produces: `ApiService.baseUrl` (unchanged type — `static const String`), now sourced from `String.fromEnvironment('API_BASE_URL', ...)` instead of a hardcoded LAN IP.

- [ ] **Step 1: Replace the hardcoded base URL**

In `frontend/lib/services/api_service.dart`, replace lines 9-10:

```dart
  static const _defaultBaseUrl = 'http://192.168.29.1:4000';
  static const baseUrl = 'http://192.168.29.1:4000';
```

with (substitute the actual URL recorded in Task 4 Step 6):

```dart
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://<your-render-url>.onrender.com',
  );
```

(`_defaultBaseUrl` was dead code — never referenced elsewhere in the file — so it's removed rather than kept alongside `baseUrl`.)

- [ ] **Step 2: Verify with flutter analyze**

Run: `cd frontend && flutter analyze lib/services/api_service.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/services/api_service.dart
git commit -m "fix: read API_BASE_URL from dart-define, default to deployed backend"
```

---

### Task 6: Expose the dev OTP from `AuthProvider`

**Files:**
- Modify: `frontend/lib/providers/auth_provider.dart`

**Interfaces:**
- Consumes: `ApiService.requestOtp(String phone) -> Future<Map<String, dynamic>>` (existing, already returns the full decoded response body including `devOtp` when present).
- Produces: `AuthProvider.lastDevOtp` (new field, `String?`) — set after a successful `requestOtp()` call. Consumed by Task 7.

- [ ] **Step 1: Add the field and populate it in `requestOtp`**

In `frontend/lib/providers/auth_provider.dart`, add the field alongside the existing ones (after `bool checkingSession = true;`):

```dart
  String? lastDevOtp;
```

Then change the `requestOtp` method body from:

```dart
  Future<bool> requestOtp(String phone) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await _api.requestOtp(phone);
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
      return false;
    }
  }
```

to:

```dart
  Future<bool> requestOtp(String phone) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final data = await _api.requestOtp(phone);
      lastDevOtp = data['devOtp'] as String?;
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
      return false;
    }
  }
```

- [ ] **Step 2: Verify with flutter analyze**

Run: `cd frontend && flutter analyze lib/providers/auth_provider.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add frontend/lib/providers/auth_provider.dart
git commit -m "feat: capture devOtp from request-otp response in AuthProvider"
```

---

### Task 7: Surface the dev OTP on the verify screen

**Files:**
- Modify: `frontend/lib/screens/auth/phone_entry_screen.dart:27-30`
- Modify: `frontend/lib/screens/auth/otp_verify_screen.dart`

**Interfaces:**
- Consumes: `AuthProvider.lastDevOtp` (`String?`, from Task 6).
- Produces: `OtpVerifyScreen({required String phone, String? devOtp})` — `devOtp` is a new optional constructor param.

- [ ] **Step 1: Pass `lastDevOtp` from `PhoneEntryScreen` into `OtpVerifyScreen`**

In `frontend/lib/screens/auth/phone_entry_screen.dart`, change lines 27-30 from:

```dart
    if (ok) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OtpVerifyScreen(phone: phone)),
      );
```

to:

```dart
    if (ok) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerifyScreen(phone: phone, devOtp: auth.lastDevOtp),
        ),
      );
```

- [ ] **Step 2: Accept and pre-fill the dev OTP in `OtpVerifyScreen`**

In `frontend/lib/screens/auth/otp_verify_screen.dart`, change the widget declaration (lines 12-18) from:

```dart
class OtpVerifyScreen extends StatefulWidget {
  final String phone;
  const OtpVerifyScreen({super.key, required this.phone});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}
```

to:

```dart
class OtpVerifyScreen extends StatefulWidget {
  final String phone;
  final String? devOtp;
  const OtpVerifyScreen({super.key, required this.phone, this.devOtp});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}
```

Change the state class's `_code` field, add a `TextEditingController`, and add an `initState` (replace lines 20-21):

```dart
class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  String _code = '';
  late final TextEditingController _pinController;

  @override
  void initState() {
    super.initState();
    _pinController = TextEditingController(text: widget.devOtp ?? '');
    if (widget.devOtp != null) {
      _code = widget.devOtp!;
    }
  }
```

(`pin_code_fields` 8.0.1's `PinCodeTextField` has no `initialValue` param — pre-filling requires a `TextEditingController`. `autoDisposeControllers` defaults to `true` on the widget, so it disposes `_pinController` itself; don't add a manual `dispose()` override, which would double-dispose it.)

Pass the controller into the pin field. Change the `PinCodeTextField` (lines 67-86) by adding `controller: _pinController,` right after `appContext: context,`:

```dart
                  child: PinCodeTextField(
                    appContext: context,
                    controller: _pinController,
                    length: 6,
```

Then, immediately after the closing `GlassPanel(...)` widget (after line 87's `),`), insert a conditional helper text before the existing `SizedBox(height: 28)`:

```dart
                if (widget.devOtp != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Dev code (no SMS configured): ${widget.devOtp}',
                    style: GoogleFonts.nunitoSans(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
```

So the section reads (condensed): `GlassPanel(...)`, then the new conditional `Text`, then the existing `const SizedBox(height: 28)` before the `EnergyOrbButton`.

Also update the resend handler so a resend refreshes the displayed code — change line 100 from:

```dart
                    onPressed: () => context.read<AuthProvider>().requestOtp(widget.phone),
```

to:

```dart
                    onPressed: () async {
                      final auth = context.read<AuthProvider>();
                      await auth.requestOtp(widget.phone);
                      if (!mounted) return;
                      final newCode = auth.lastDevOtp;
                      if (newCode != null) {
                        setState(() => _code = newCode);
                        _pinController.text = newCode;
                      }
                    },
```

- [ ] **Step 3: Verify with flutter analyze**

Run: `cd frontend && flutter analyze lib/screens/auth/`
Expected: `No issues found!`

- [ ] **Step 4: Manual widget check**

Run: `cd frontend && flutter run -d <device-id>` (any connected device/emulator works for this check — it's independent of the release build), request an OTP, and confirm the OTP entry screen shows the "Dev code: ..." text and the pin field is pre-filled with a valid 6-digit code that verifies successfully when you tap "Verify & continue" without typing anything.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/auth/phone_entry_screen.dart frontend/lib/screens/auth/otp_verify_screen.dart
git commit -m "feat: surface dev OTP code on verify screen instead of expecting SMS"
```

---

### Task 8: Fix stations-list load delay + Hyderabad default map center

**Files:**
- Modify: `frontend/lib/screens/home/home_screen.dart:25` (default center)
- Modify: `frontend/lib/screens/home/home_screen.dart:56-74` (`_loadLocationAndStations`)

**Interfaces:**
- Consumes: `StationProvider.loadNearby(double lat, double lng) -> Future<void>` (existing, unchanged — already safe to call multiple times, fully replaces `stations` each call).
- Consumes: `Geolocator.getLastKnownPosition() -> Future<Position?>` (from the existing `geolocator` package dependency).

- [ ] **Step 1: Change the default fallback center to Hyderabad**

In `frontend/lib/screens/home/home_screen.dart`, change line 25 from:

```dart
  LatLng _center = const LatLng(23.2599, 77.4126); // Default: Bhopal
```

to:

```dart
  LatLng _center = const LatLng(17.3850, 78.4867); // Default: Hyderabad
```

- [ ] **Step 2: Stop blocking the stations fetch on a precise GPS fix**

Replace `_loadLocationAndStations` (lines 56-74):

```dart
  Future<void> _loadLocationAndStations() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        );
        _center = LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {
      // Fall back to default center silently; user can still browse.
    }
    if (!mounted) return;
    context.read<StationProvider>().loadNearby(_center.latitude, _center.longitude);
  }
```

with:

```dart
  Future<void> _loadLocationAndStations() async {
    // Show results immediately using the last-known (or default) position —
    // don't make the user wait on a fresh GPS fix, which can take several
    // seconds on a real device (instant on an emulator, which is why this
    // wasn't noticeable before).
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _center = LatLng(lastKnown.latitude, lastKnown.longitude);
      }
    } catch (_) {
      // Fall back to the default center silently.
    }
    if (!mounted) return;
    context.read<StationProvider>().loadNearby(_center.latitude, _center.longitude);

    // Refresh in the background once a precise fix is available.
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (!mounted) return;
      _center = LatLng(pos.latitude, pos.longitude);
      context.read<StationProvider>().loadNearby(_center.latitude, _center.longitude);
    } catch (_) {
      // Precise fix unavailable; the last-known/default result already loaded above stands.
    }
  }
```

- [ ] **Step 3: Verify with flutter analyze**

Run: `cd frontend && flutter analyze lib/screens/home/home_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Manual check**

Run the app on a device/emulator, open the home screen, and confirm the stations list populates immediately (not blank while waiting), then optionally updates again shortly after with GPS-accurate results if your device's location differs from the last-known position.

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/screens/home/home_screen.dart
git commit -m "fix: don't block stations list on GPS fix; default map center to Hyderabad"
```

---

### Task 9: Release-sign the Android build

**Files:**
- Create: `frontend/android/key.properties` (gitignored — never committed)
- Create: a keystore file, e.g. `frontend/android/app/ecocharge-release.jks` (gitignored — never committed)
- Modify: `frontend/android/app/build.gradle.kts`
- Modify: `.gitignore`

**Interfaces:** None (build configuration only).

- [ ] **Step 1: Generate the signing keystore**

Run (from anywhere; this creates a standalone key file — adjust the `-keystore` path to land inside `frontend/android/app/`):

```bash
keytool -genkey -v -keystore frontend/android/app/ecocharge-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias ecocharge
```

Follow the prompts (name/org/location — any values are fine for personal use) and choose a keystore password and key password. **Write these down** — losing them means you can never publish an update signed the same way (not a concern for a one-off personal install, but worth keeping if you rebuild later).

- [ ] **Step 2: Add signing config files to `.gitignore`**

In `.gitignore`, add under the "Frontend (Flutter)" section:

```
frontend/android/key.properties
frontend/android/app/*.jks
```

- [ ] **Step 3: Create `frontend/android/key.properties`**

```
storePassword=<the keystore password you chose>
keyPassword=<the key password you chose>
keyAlias=ecocharge
storeFile=ecocharge-release.jks
```

- [ ] **Step 4: Wire the signing config into `build.gradle.kts`**

In `frontend/android/app/build.gradle.kts`, add this block right after the `plugins { ... }` block (before `android {`):

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```

Then, inside the `android { ... }` block, add a `signingConfigs` block right before `buildTypes` (after the `defaultConfig { ... }` block closes):

```kotlin
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
```

Finally, change the existing `buildTypes` block from:

```kotlin
    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
```

to:

```kotlin
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
```

- [ ] **Step 5: Build the signed release APK**

Run (substitute your actual deployed URL if it differs from what you already hardcoded as the default in Task 5 — if it matches, `--dart-define` is optional since it's now the default):

```bash
cd frontend && flutter build apk --release --dart-define=API_BASE_URL=https://<your-render-url>.onrender.com
```

Expected: build succeeds, producing `frontend/build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 6: Commit**

```bash
git add .gitignore frontend/android/app/build.gradle.kts
git commit -m "feat: configure Android release signing"
```

(`key.properties` and the `.jks` file are intentionally not committed — they're gitignored secrets local to this machine.)

---

### Task 10: Install on the physical device and verify end to end

**Files:** None (verification only).

- [ ] **Step 1: Install the APK on the phone**

With the phone connected via USB and USB debugging enabled: `adb install frontend/build/app/outputs/flutter-apk/app-release.apk`

(Alternative if you don't want to use USB at all: copy `app-release.apk` to the phone via any file-transfer method, enable "Install unknown apps" for that source in Android settings, and tap the file to install.)

- [ ] **Step 2: Disconnect completely**

Unplug the phone from USB and turn off wifi on the phone (or move it off your home network entirely — e.g. switch to mobile data), so there is no possible path back to your laptop.

- [ ] **Step 3: Full manual walkthrough**

On the phone, with only mobile data (or any wifi not shared with your laptop):
1. Open the EcoCharge app fresh (first launch).
2. Enter a phone number, request OTP — confirm the "Dev code: ..." text appears and pre-fills the entry field; tap "Verify & continue" and confirm login succeeds.
3. On the home screen, confirm the stations list appears quickly (not a long blank/loading wait) and shows the 5 Hyderabad stations.
4. Tap a station, view its detail/connectors.
5. Book a slot; confirm it appears under bookings/history.
6. Start a charging session ("Charge now"), watch the live gauge, then stop it; confirm wallet balance debits correctly.
7. Go to Wallet, top up balance, confirm the transaction appears in history.
8. Fully close the app (swipe away from recents) and reopen it — confirm it goes straight back into the app (session persisted) with no laptop/wifi-to-laptop involved at any point.

Expected: every step works with the phone completely disconnected from the laptop, confirming the app is now fully standalone.
