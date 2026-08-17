-- Data-integrity hardening.
--
-- Every ADD CONSTRAINT is wrapped in a DO block that swallows
-- duplicate_object, since Postgres has no native
-- "ADD CONSTRAINT IF NOT EXISTS" — this keeps the migration safe to baseline
-- against a database that may already have some of these applied.

-- Needed for the exclusion constraint below (GiST index on a UUID equality +
-- a range overlap).
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- Prevent two confirmed bookings from overlapping on the same connector.
-- Closes the check-then-insert race in POST /api/bookings, where the
-- overlap SELECT and the INSERT aren't atomic against a concurrent request.
DO $$
BEGIN
  ALTER TABLE bookings
    ADD CONSTRAINT bookings_no_overlap
    EXCLUDE USING gist (
      connector_id WITH =,
      tstzrange(slot_start, slot_end) WITH &&
    )
    WHERE (status = 'confirmed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- At most one active charging session per connector, and per user. Closes
-- the equivalent race in POST /api/sessions/start.
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_one_active_per_connector
  ON charging_sessions (connector_id) WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_one_active_per_user
  ON charging_sessions (user_id) WHERE status = 'active';

-- Constrain status/type columns to their known-good values at the DB level.
DO $$
BEGIN
  ALTER TABLE connectors
    ADD CONSTRAINT connectors_status_valid
    CHECK (status IN ('available', 'occupied', 'offline'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE bookings
    ADD CONSTRAINT bookings_status_valid
    CHECK (status IN ('confirmed', 'cancelled', 'completed', 'no_show'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE charging_sessions
    ADD CONSTRAINT charging_sessions_status_valid
    CHECK (status IN ('active', 'completed', 'stopped', 'error'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE wallet_transactions
    ADD CONSTRAINT wallet_transactions_type_valid
    CHECK (type IN ('topup', 'charge_debit', 'refund'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Backstop against a negative wallet balance from any future bug or manual
-- UPDATE. The app already guards this correctly in finalizeSession().
DO $$
BEGIN
  ALTER TABLE users
    ADD CONSTRAINT users_wallet_balance_non_negative
    CHECK (wallet_balance >= 0);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- verify-otp filters by phone on every login attempt; there was no index
-- for it.
CREATE INDEX IF NOT EXISTS idx_otp_codes_phone ON otp_codes(phone);
