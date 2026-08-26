async function sendOtpSms(phone, code) {
  const provider = process.env.SMS_PROVIDER || 'console';
  const expiryMinutes = process.env.OTP_EXPIRY_MINUTES || 5;

  if (provider === 'twilio') {
    const twilio = require('twilio');
    const client = twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
    await client.messages.create({
      to: phone,
      from: process.env.TWILIO_FROM_NUMBER,
      body: `Your EcoCharge verification code is ${code}. It expires in ${expiryMinutes} minutes.`,
    });
    return;
  }

  console.log(`[OTP] Sending code ${code} to ${phone} (expires in ${expiryMinutes} min)`);
}

module.exports = { sendOtpSms };
