-- EcoCharge database schema (PostgreSQL)

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users, identified by phone number (OTP auth)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone VARCHAR(20) UNIQUE NOT NULL,
    name VARCHAR(120),
    email VARCHAR(150),
    wallet_balance NUMERIC(10,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Short-lived OTP codes for phone login
CREATE TABLE IF NOT EXISTS otp_codes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone VARCHAR(20) NOT NULL,
    code VARCHAR(6) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- User's saved vehicles
CREATE TABLE IF NOT EXISTS vehicles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    make VARCHAR(60) NOT NULL,
    model VARCHAR(60) NOT NULL,
    connector_type VARCHAR(30) NOT NULL, -- CCS2, CHAdeMO, Type2, GBT
    reg_number VARCHAR(20),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    battery_capacity_kwh NUMERIC(6,2) NOT NULL DEFAULT 40,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS battery_capacity_kwh NUMERIC(6,2) NOT NULL DEFAULT 40;

-- Charging stations (network locations)
CREATE TABLE IF NOT EXISTS stations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    address VARCHAR(255),
    city VARCHAR(100),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    rating NUMERIC(2,1) DEFAULT 4.5,
    is_open_24h BOOLEAN NOT NULL DEFAULT TRUE,
    amenities TEXT[] DEFAULT '{}', -- e.g. {"Restroom","Cafe","WiFi"}
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Individual chargers/connectors at a station
CREATE TABLE IF NOT EXISTS connectors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    station_id UUID NOT NULL REFERENCES stations(id) ON DELETE CASCADE,
    connector_type VARCHAR(30) NOT NULL,
    power_kw NUMERIC(6,2) NOT NULL,
    price_per_kwh NUMERIC(6,2) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'available' -- available, occupied, offline
);

-- Slot bookings
CREATE TABLE IF NOT EXISTS bookings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    station_id UUID NOT NULL REFERENCES stations(id),
    connector_id UUID NOT NULL REFERENCES connectors(id),
    vehicle_id UUID REFERENCES vehicles(id),
    slot_start TIMESTAMPTZ NOT NULL,
    slot_end TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'confirmed', -- confirmed, cancelled, completed, no_show
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Charging sessions (live / historical)
CREATE TABLE IF NOT EXISTS charging_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    booking_id UUID REFERENCES bookings(id),
    station_id UUID NOT NULL REFERENCES stations(id),
    connector_id UUID NOT NULL REFERENCES connectors(id),
    vehicle_id UUID REFERENCES vehicles(id),
    status VARCHAR(20) NOT NULL DEFAULT 'active', -- active, completed, stopped, error
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    stopped_at TIMESTAMPTZ,
    energy_kwh NUMERIC(8,3) NOT NULL DEFAULT 0,
    cost NUMERIC(10,2) NOT NULL DEFAULT 0,
    start_battery_pct SMALLINT NOT NULL DEFAULT 20,
    auto_stop_pct SMALLINT,
    battery_capacity_kwh NUMERIC(6,2) NOT NULL DEFAULT 40
);

-- Idempotent for databases that already had charging_sessions before these
-- columns existed (ADD COLUMN IF NOT EXISTS is a safe no-op on fresh installs
-- where CREATE TABLE just created them).
ALTER TABLE charging_sessions ADD COLUMN IF NOT EXISTS start_battery_pct SMALLINT NOT NULL DEFAULT 20;
ALTER TABLE charging_sessions ADD COLUMN IF NOT EXISTS auto_stop_pct SMALLINT;
ALTER TABLE charging_sessions ADD COLUMN IF NOT EXISTS battery_capacity_kwh NUMERIC(6,2) NOT NULL DEFAULT 40;

-- Wallet transactions (top-ups, charges, refunds)
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL, -- topup, charge_debit, refund
    amount NUMERIC(10,2) NOT NULL,
    reference VARCHAR(120),
    session_id UUID REFERENCES charging_sessions(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stations_lat_lng ON stations(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_connectors_station ON connectors(station_id);
CREATE INDEX IF NOT EXISTS idx_bookings_user ON bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON charging_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_user ON wallet_transactions(user_id);
