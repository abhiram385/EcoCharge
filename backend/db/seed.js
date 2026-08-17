require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { pool } = require('./pool');

async function run() {
  const seed = fs.readFileSync(path.join(__dirname, 'seed.sql'), 'utf8');
  console.log('Seeding demo data...');
  await pool.query(seed);
  console.log('Done.');
  await pool.end();
}

run().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
