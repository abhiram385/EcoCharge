require('dotenv').config();
const { pool } = require('./pool');

const EXPECTED_CONSTRAINTS = [
  ['bookings_no_overlap', 'Prevents double-booking the same connector'],
  ['bookings_status_valid', 'Booking status locked to valid values'],
  ['charging_sessions_status_valid', 'Session status locked to valid values'],
  ['connectors_status_valid', 'Connector status locked to valid values'],
  ['wallet_transactions_type_valid', 'Wallet transaction type locked to valid values'],
  ['users_wallet_balance_non_negative', 'Wallet balance can never go negative'],
];

const EXPECTED_INDEXES = [
  ['idx_sessions_one_active_per_connector', 'Blocks two active sessions on one connector'],
  ['idx_sessions_one_active_per_user', 'Blocks a user from having two active sessions'],
  ['idx_otp_codes_phone', 'Speeds up login OTP lookups'],
];

async function run() {
  console.log('=== EcoCharge Database Reliability — Live Verification ===');
  console.log('Target: ' + process.env.DATABASE_URL.replace(/:[^:@]+@/, ':****@'));
  console.log('Checked: ' + new Date().toISOString());
  console.log('');

  const migs = await pool.query('SELECT version, applied_at FROM schema_migrations ORDER BY version');
  console.log('MIGRATIONS APPLIED:');
  migs.rows.forEach((r) => console.log(`  [x] ${r.version}  (${r.applied_at.toISOString()})`));
  console.log('');

  const cons = await pool.query('SELECT conname FROM pg_constraint WHERE conname = ANY($1)', [
    EXPECTED_CONSTRAINTS.map((c) => c[0]),
  ]);
  const foundCons = new Set(cons.rows.map((r) => r.conname));
  console.log('DATA INTEGRITY CONSTRAINTS:');
  EXPECTED_CONSTRAINTS.forEach(([name, desc]) => {
    console.log(`  [${foundCons.has(name) ? 'x' : ' '}] ${desc}`);
  });
  console.log('');

  const idx = await pool.query('SELECT indexname FROM pg_indexes WHERE indexname = ANY($1)', [
    EXPECTED_INDEXES.map((i) => i[0]),
  ]);
  const foundIdx = new Set(idx.rows.map((r) => r.indexname));
  console.log('PERFORMANCE / RACE-CONDITION GUARDS:');
  EXPECTED_INDEXES.forEach(([name, desc]) => {
    console.log(`  [${foundIdx.has(name) ? 'x' : ' '}] ${desc}`);
  });
  console.log('');

  const allOk =
    foundCons.size === EXPECTED_CONSTRAINTS.length &&
    foundIdx.size === EXPECTED_INDEXES.length &&
    migs.rows.length >= 2;
  console.log(allOk ? '=== RESULT: ALL CHECKS PASSED ===' : '=== RESULT: SOME CHECKS MISSING ===');

  await pool.end();
  if (!allOk) process.exit(1);
}

run().catch((err) => {
  console.error('VERIFICATION FAILED:', err.message);
  process.exit(1);
});
