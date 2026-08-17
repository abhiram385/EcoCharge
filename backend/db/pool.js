const { Pool } = require('pg');

const useSsl =
  process.env.DATABASE_SSL !== undefined
    ? process.env.DATABASE_SSL === 'true'
    : process.env.NODE_ENV === 'production';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: useSsl ? { rejectUnauthorized: false } : false,
  max: Number(process.env.PGPOOL_MAX || 10),
  idleTimeoutMillis: Number(process.env.PGPOOL_IDLE_TIMEOUT_MS || 30000),
  connectionTimeoutMillis: Number(process.env.PGPOOL_CONN_TIMEOUT_MS || 5000),
});

// Without this, an idle client hitting a dropped connection (network blip,
// DB restart) emits an unhandled 'error' event on the pool, which Node
// treats as an uncaught exception and kills the whole process.
pool.on('error', (err) => {
  console.error('Unexpected error on idle Postgres client:', err.message);
});

module.exports = { pool };
