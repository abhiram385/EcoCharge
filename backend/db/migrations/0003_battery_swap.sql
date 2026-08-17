-- Battery swap marketplace: fake seeded swap points where a user can
-- instantly trade a depleted pack for a charged one, mirroring the
-- stations/connectors shape but with per-pack-type inventory counts
-- instead of a single always-tracked connector status.

CREATE TABLE IF NOT EXISTS swap_points (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    address VARCHAR(255),
    city VARCHAR(100),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    rating NUMERIC(2,1) DEFAULT 4.5,
    is_open_24h BOOLEAN NOT NULL DEFAULT TRUE,
    amenities TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One row per pack type stocked at a swap point (e.g. this point might
-- stock both Type2-class scooter packs and a bigger capacity).
CREATE TABLE IF NOT EXISTS swap_packs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    swap_point_id UUID NOT NULL REFERENCES swap_points(id) ON DELETE CASCADE,
    pack_type VARCHAR(30) NOT NULL, -- matches vehicles.connector_type for swap-capable vehicles
    capacity_kwh NUMERIC(6,2) NOT NULL,
    price_per_swap NUMERIC(6,2) NOT NULL,
    available_count SMALLINT NOT NULL DEFAULT 0,
    total_count SMALLINT NOT NULL DEFAULT 0
);

-- A completed swap (instant — there's no "active" state like a charging
-- session, the pack trade happens on the spot).
CREATE TABLE IF NOT EXISTS swap_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    swap_point_id UUID NOT NULL REFERENCES swap_points(id),
    pack_id UUID NOT NULL REFERENCES swap_packs(id),
    vehicle_id UUID REFERENCES vehicles(id),
    cost NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Wallet transactions need a 'battery_swap' type alongside the existing
-- topup/charge_debit/refund set.
ALTER TABLE wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_type_valid;
ALTER TABLE wallet_transactions ADD CONSTRAINT wallet_transactions_type_valid
  CHECK (type IN ('topup', 'charge_debit', 'refund', 'battery_swap'));

CREATE INDEX IF NOT EXISTS idx_swap_points_lat_lng ON swap_points(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_swap_packs_point ON swap_packs(swap_point_id);
CREATE INDEX IF NOT EXISTS idx_swap_transactions_user ON swap_transactions(user_id);

-- Prevent selling a pack that isn't in stock, and stop available_count
-- from ever exceeding what the point actually has.
DO $$
BEGIN
  ALTER TABLE swap_packs
    ADD CONSTRAINT swap_packs_available_count_valid
    CHECK (available_count >= 0 AND available_count <= total_count);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
