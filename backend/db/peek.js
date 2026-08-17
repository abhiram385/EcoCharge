require('dotenv').config();
const { pool } = require('./pool');

async function run() {
  console.log('=== EcoCharge — Live Database Snapshot ===');
  console.log('Checked: ' + new Date().toISOString());
  console.log('');

  const counts = await pool.query(`
    SELECT
      (SELECT count(*) FROM users) AS users,
      (SELECT count(*) FROM stations) AS stations,
      (SELECT count(*) FROM bookings) AS bookings,
      (SELECT count(*) FROM charging_sessions) AS sessions,
      (SELECT count(*) FROM wallet_transactions) AS wallet_transactions
  `);
  console.log('ROW COUNTS:', counts.rows[0]);
  console.log('');

  const users = await pool.query('SELECT phone, name, wallet_balance, created_at FROM users ORDER BY created_at DESC LIMIT 5');
  console.log('MOST RECENT USERS:');
  users.rows.forEach((r) =>
    console.log(`  ${r.phone}  name=${r.name ?? '(none)'}  balance=${r.wallet_balance}  ${r.created_at.toISOString()}`)
  );
  console.log('');

  const bookings = await pool.query(
    `SELECT b.id, b.status, b.slot_start, s.name AS station
     FROM bookings b JOIN stations s ON s.id = b.station_id
     ORDER BY b.created_at DESC LIMIT 5`
  );
  console.log('MOST RECENT BOOKINGS:');
  if (bookings.rows.length === 0) console.log('  (none yet)');
  bookings.rows.forEach((r) => console.log(`  ${r.station}  status=${r.status}  slot=${r.slot_start.toISOString()}`));
  console.log('');

  const tx = await pool.query(
    'SELECT type, amount, reference, created_at FROM wallet_transactions ORDER BY created_at DESC LIMIT 5'
  );
  console.log('MOST RECENT WALLET ACTIVITY:');
  if (tx.rows.length === 0) console.log('  (none yet)');
  tx.rows.forEach((r) => console.log(`  ${r.type}  amount=${r.amount}  ref=${r.reference}  ${r.created_at.toISOString()}`));

  await pool.end();
}

run().catch((err) => {
  console.error('PEEK FAILED:', err.message);
  process.exit(1);
});
