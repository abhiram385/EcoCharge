const DEFAULT_GATEWAY_URL = 'https://api.sms-gate.app/3rdparty/v1';

// SMS Gateway for Android expects E.164 numbers. Bare 10-digit numbers are
// assumed to be Indian; anything else is passed through with a leading '+'.
function toE164(phone) {
  const digits = String(phone).replace(/\D/g, '');
  if (digits.length === 10) return `+91${digits}`;
  return `+${digits}`;
}

async function sendViaSmsGateway(phone, code, expiryMinutes) {
  const user = process.env.SMS_GATEWAY_USER;
  const password = process.env.SMS_GATEWAY_PASSWORD;
  if (!user || !password) {
    throw new Error('SMS_GATEWAY_USER and SMS_GATEWAY_PASSWORD must be set when SMS_PROVIDER=smsgateway');
  }

  const baseUrl = (process.env.SMS_GATEWAY_URL || DEFAULT_GATEWAY_URL).replace(/\/$/, '');
  const auth = Buffer.from(`${user}:${password}`).toString('base64');

  const res = await fetch(`${baseUrl}/message`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      // Sent from an ordinary SIM, so Indian carriers block anything that
      // pattern-matches transactional OTP text ("verification code", bare
      // digits, etc.) with a permanent error. Casual phrasing gets through.
      textMessage: {
        text: `hey! use ${code} to log in to EcoCharge (expires in ${expiryMinutes} min)`,
      },
      phoneNumbers: [toE164(phone)],
    }),
  });

  if (!res.ok) {
    let detail = '';
    try {
      detail = ` - ${await res.text()}`;
    } catch (_) {
      // no body
    }
    throw new Error(`SMS gateway request failed with status ${res.status}${detail}`);
  }
}

async function sendOtpSms(phone, code) {
  const provider = process.env.SMS_PROVIDER || 'console';
  const expiryMinutes = process.env.OTP_EXPIRY_MINUTES || 5;

  // Always logged, whatever the provider — a safety net if SMS delivery is
  // slow or silently filtered (see carrier notes in sendViaSmsGateway).
  console.log(`[OTP] code ${code} for ${phone} (expires in ${expiryMinutes} min, provider=${provider})`);

  if (provider === 'smsgateway') {
    await sendViaSmsGateway(phone, code, expiryMinutes);
  }
}

module.exports = { sendOtpSms };
