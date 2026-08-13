# Battery level + remote Auto Stop — design

Status: approved
Date: 2026-08-13

## Context

EcoCharge simulates charging sessions server-side (no real charger/vehicle
integration): `energyKwh` and `cost` are computed on read from elapsed time,
not stored incrementally. This feature adds a simulated battery percentage on
top of that same model, plus a user-settable "Auto Stop" target percentage
that automatically ends the session once reached.

This is one of three sub-projects agreed with the user, to be done in order:
1. **This spec** — battery level + Auto Stop
2. Frutiger Aero visual redesign (separate spec, its own screen-by-screen
   approval process)
3. Deployment to a public host + standalone release APK (already designed
   separately; deploy last, once 1 and 2 are done)

New UI added here reuses the app's existing `GlassPanel` / `EnergyOrbButton`
components so it looks consistent with the app today. It is expected to be
reskinned along with every other screen during the Frutiger Aero redesign
pass (sub-project 2) — not restyled twice.

## Data model

Add two columns to `charging_sessions`:

- `start_battery_pct SMALLINT NOT NULL` — randomly assigned in the range
  15–55 when the session starts (dummy realism; not user-controlled).
- `auto_stop_pct SMALLINT` — nullable. `NULL` means "charge to 100%".
  Valid values: 10, 20, 30, ... 100 (steps of 10), set by the user.

Battery percentage is **computed on read**, mirroring how `energyKwh`/`cost`
already work — not stored/ticked incrementally:

```
batteryPct = min(100, startBatteryPct + (energyKwh / 40) * 100)
```

(`40` kWh is the existing full-charge assumption already hardcoded in the
current frontend progress ring — reused here rather than introducing a new
constant, and centralized in one backend constant so both the computation
and the docs agree on it.)

## Auto-stop mechanics

There is no background scheduler in this app. The active-session screen
already polls `GET /api/sessions/active` every 5 seconds while open. Auto
Stop is enforced **at poll time**: if `auto_stop_pct` is set and the computed
`batteryPct` has reached/exceeded it, the handler immediately runs the same
finalize-session transaction used by manual stop (deduct wallet, mark
`completed`, free the connector, insert a wallet transaction), then returns
that one response with the session in `completed` status and an
`autoStopped: true` flag.

The existing finalize logic (currently inline in `POST /api/sessions/:id/stop`)
will be extracted into a shared helper function used by both the manual-stop
route and this auto-stop path, so there is one tested code path for ending a
session, not two.

**Known limitation (accepted):** if the active-session screen isn't open and
polling, the auto-stop won't fire until it's reopened and polls again. A
true "fires while app is closed" version would need a server-side
scheduler/cron — explicitly out of scope; user confirmed poll-triggered
timing is acceptable, consistent with how the rest of the simulation
already works.

## Backend API changes

- `POST /api/sessions/start` — accepts optional `autoStopPct` (integer,
  10–100 step 10, or omitted/null for "charge to 100%"). Validates range.
  Assigns a random `start_battery_pct` (15–55) on insert.
- `GET /api/sessions/active` — response gains `batteryPct`, `startBatteryPct`,
  `autoStopPct`. Performs the auto-stop check described above before
  responding; if triggered, response reflects the now-`completed` session
  plus `autoStopped: true`.
- `POST /api/sessions/:id/stop` — unchanged behavior, refactored to share
  the extracted finalize helper. Response also includes final `batteryPct`.
- New: `PATCH /api/sessions/:id/auto-stop` `{ autoStopPct }` — lets the user
  change the target while a session is active ("remote control"). Validates
  ownership, active status, and range; updates the column; returns the
  updated session view (including current computed `batteryPct`).

## Frontend changes

**Starting a session** (`station_detail_screen.dart`): "Charge now" currently
starts immediately. It will instead open a bottom sheet (same visual pattern
as the existing wallet top-up / add-vehicle sheets: `GlassPanel`-style sheet,
`EnergyOrbButton` to confirm) with a slider for Auto Stop target — 10 steps
of 10%, range 10–100%, default 100%. Confirming starts the session with that
target.

**Active session screen** (`active_session_screen.dart`): the big circular
progress ring currently shows `energyKwh / 40` (a hardcoded guess baked
directly into the widget). It will instead show `batteryPct` directly
(0–100%), which is both more meaningful and removes that hardcoded number
from the UI layer (the `40` becomes a single backend constant instead of a
duplicated assumption in two places). Below it, a compact slider (10 steps
of 10%, matching the start-sheet control) shows/adjusts the live Auto Stop
target; releasing a drag commits the change via `PATCH .../auto-stop`.

**Model/provider changes:**
- `ChargingSession` model gains `batteryPct`, `startBatteryPct`, `autoStopPct`.
- `ApiService.startSession` gains optional `autoStopPct` param; new
  `ApiService.setAutoStop(sessionId, autoStopPct)` method.
- `SessionProvider.refreshActiveSession()` must distinguish "no active
  session" (`session: null`) from "session just auto-stopped"
  (`session.status == 'completed' && autoStopped == true` on that one
  response) — on the latter, it stops polling, clears `activeSession`, and
  exposes enough state for the screen to react.

**Reacting to auto-stop:** when `SessionProvider` detects the auto-stopped
transition, `ActiveSessionScreen` automatically navigates back to home and
shows a distinct message — "🔋 Auto-stopped at X% — charged to your target!"
— mirroring the existing manual-stop success flow rather than silently
vanishing.

## Testing

- Backend: `curl` through the full lifecycle — start with a low `autoStopPct`
  (e.g. 10%), poll `/active` repeatedly until the simulated `batteryPct`
  crosses it, confirm the response flips to `completed` + `autoStopped: true`,
  wallet balance decreases correctly, connector returns to `available`.
- Backend: `PATCH .../auto-stop` mid-session, confirm the new target takes
  effect on the next poll.
- Frontend: manually walk through start-sheet → active screen → auto-stop
  trigger → home-screen return message, on the installed app.
