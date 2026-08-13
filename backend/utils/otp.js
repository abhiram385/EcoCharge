const crypto = require('crypto');

function generateOtp() {
  return String(crypto.randomInt(100000, 1000000));
}

module.exports = { generateOtp };
