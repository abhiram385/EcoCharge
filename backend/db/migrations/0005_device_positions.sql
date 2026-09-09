-- GPS positions reported by a tracking device (PoC: one Atlanta EL-440).
-- Ingested over HTTP by /api/tracker/ingest — from the throwaway feeder for
-- now, and later from a small TCP listener that decodes the EL-440's ATL
-- protocol once Atlanta provides the spec. The app reads the latest row per
-- device to show a live marker on the map.
CREATE TABLE IF NOT EXISTS device_positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id VARCHAR(64) NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    speed_kph NUMERIC(6,2),
    heading_deg NUMERIC(5,2),
    recorded_at TIMESTAMPTZ NOT NULL,   -- device's own fix time
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    raw JSONB
);

-- "latest position for a device" is the only read path so far.
CREATE INDEX IF NOT EXISTS idx_device_positions_device_recorded
    ON device_positions(device_id, recorded_at DESC);
