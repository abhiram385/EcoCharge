-- Razorpay-backed wallet top-ups. Kept as its own table rather than adding
-- columns to wallet_transactions so an abandoned/failed checkout never shows
-- up in the user's transaction history — a row here only becomes a
-- wallet_transactions entry once the payment is verified.
CREATE TABLE IF NOT EXISTS payment_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount NUMERIC(10,2) NOT NULL,
    gateway_order_id VARCHAR(64) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'created', -- created, verified, failed
    gateway_payment_id VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    verified_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_payment_orders_user ON payment_orders(user_id);
