-- Persisted current battery level per vehicle. Previously the app only
-- tracked total capacity (battery_capacity_kwh) — the live percentage
-- shown during a session was computed from a randomly-assigned starting
-- point each time and never saved back to the vehicle. This column is the
-- single source of truth going forward: charging sessions and battery
-- swaps both update it on completion, and every screen that shows a
-- vehicle's battery level reads from here.
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS battery_level_pct SMALLINT NOT NULL DEFAULT 50;
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS swap_capable BOOLEAN NOT NULL DEFAULT FALSE;

DO $$
BEGIN
  ALTER TABLE vehicles
    ADD CONSTRAINT vehicles_battery_level_pct_valid
    CHECK (battery_level_pct >= 0 AND battery_level_pct <= 100);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
