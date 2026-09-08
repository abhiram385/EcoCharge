describe('sendOtpSms', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...originalEnv };
    delete process.env.SMS_PROVIDER;
    delete process.env.SMS_GATEWAY_URL;
    delete process.env.SMS_GATEWAY_USER;
    delete process.env.SMS_GATEWAY_PASSWORD;
    delete global.fetch;
  });

  afterAll(() => {
    process.env = originalEnv;
    delete global.fetch;
  });

  function mockOkFetch() {
    const fetchSpy = jest.fn().mockResolvedValue({
      ok: true,
      status: 201,
      json: async () => ({ id: 'msg-1', state: 'Pending' }),
      text: async () => '{"id":"msg-1","state":"Pending"}',
    });
    global.fetch = fetchSpy;
    return fetchSpy;
  }

  it('logs to console and does not call the SMS API when SMS_PROVIDER is unset', async () => {
    const logSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
    const fetchSpy = jest.fn();
    global.fetch = fetchSpy;
    const { sendOtpSms } = require('./sms');

    await sendOtpSms('+919876543210', '123456');

    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('123456'));
    expect(fetchSpy).not.toHaveBeenCalled();
    logSpy.mockRestore();
  });

  it('logs to console and does not call the SMS API when SMS_PROVIDER=console', async () => {
    process.env.SMS_PROVIDER = 'console';
    const logSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
    const fetchSpy = jest.fn();
    global.fetch = fetchSpy;
    const { sendOtpSms } = require('./sms');

    await sendOtpSms('+919876543210', '123456');

    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('123456'));
    expect(fetchSpy).not.toHaveBeenCalled();
    logSpy.mockRestore();
  });

  it('sends via the SMS gateway with Basic auth and an E.164 number', async () => {
    process.env.SMS_PROVIDER = 'smsgateway';
    process.env.SMS_GATEWAY_USER = 'user';
    process.env.SMS_GATEWAY_PASSWORD = 'pass';
    const fetchSpy = mockOkFetch();
    const { sendOtpSms } = require('./sms');

    await sendOtpSms('+91 98765 43210', '123456');

    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const [url, options] = fetchSpy.mock.calls[0];
    expect(url).toBe('https://api.sms-gate.app/3rdparty/v1/message');
    expect(options.method).toBe('POST');
    expect(options.headers.Authorization).toBe(
      'Basic ' + Buffer.from('user:pass').toString('base64')
    );
    const body = JSON.parse(options.body);
    expect(body.phoneNumbers).toEqual(['+919876543210']);
    expect(body.textMessage.text).toContain('123456');
  });

  it('phrases the gateway message conversationally so Indian carriers do not filter it as OTP spam', async () => {
    process.env.SMS_PROVIDER = 'smsgateway';
    process.env.SMS_GATEWAY_USER = 'user';
    process.env.SMS_GATEWAY_PASSWORD = 'pass';
    const fetchSpy = mockOkFetch();
    const { sendOtpSms } = require('./sms');

    await sendOtpSms('+919876543210', '123456');

    const text = JSON.parse(fetchSpy.mock.calls[0][1].body).textMessage.text;
    expect(text).toContain('123456');
    expect(text).not.toMatch(/verification code/i);
    expect(text).not.toMatch(/\bOTP\b/i);
  });

  it('logs the code server-side even when sending via the gateway (demo safety net)', async () => {
    process.env.SMS_PROVIDER = 'smsgateway';
    process.env.SMS_GATEWAY_USER = 'user';
    process.env.SMS_GATEWAY_PASSWORD = 'pass';
    mockOkFetch();
    const logSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
    const { sendOtpSms } = require('./sms');

    await sendOtpSms('+919876543210', '123456');

    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('123456'));
    logSpy.mockRestore();
  });

  it('normalizes a bare 10-digit Indian number to +91 E.164', async () => {
    process.env.SMS_PROVIDER = 'smsgateway';
    process.env.SMS_GATEWAY_USER = 'user';
    process.env.SMS_GATEWAY_PASSWORD = 'pass';
    const fetchSpy = mockOkFetch();
    const { sendOtpSms } = require('./sms');

    await sendOtpSms('7330997330', '123456');

    const body = JSON.parse(fetchSpy.mock.calls[0][1].body);
    expect(body.phoneNumbers).toEqual(['+917330997330']);
  });

  it('uses SMS_GATEWAY_URL when provided', async () => {
    process.env.SMS_PROVIDER = 'smsgateway';
    process.env.SMS_GATEWAY_USER = 'user';
    process.env.SMS_GATEWAY_PASSWORD = 'pass';
    process.env.SMS_GATEWAY_URL = 'http://192.168.1.50:8080/3rdparty/v1';
    const fetchSpy = mockOkFetch();
    const { sendOtpSms } = require('./sms');

    await sendOtpSms('+919876543210', '123456');

    expect(fetchSpy.mock.calls[0][0]).toBe('http://192.168.1.50:8080/3rdparty/v1/message');
  });

  it('throws with the response body when the gateway rejects the request', async () => {
    process.env.SMS_PROVIDER = 'smsgateway';
    process.env.SMS_GATEWAY_USER = 'user';
    process.env.SMS_GATEWAY_PASSWORD = 'pass';
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 401,
      json: async () => ({ message: 'unauthorized' }),
      text: async () => '{"message":"unauthorized"}',
    });
    const { sendOtpSms } = require('./sms');

    await expect(sendOtpSms('+919876543210', '123456')).rejects.toThrow(/401/);
  });

  it('throws a clear error when gateway credentials are missing', async () => {
    process.env.SMS_PROVIDER = 'smsgateway';
    const fetchSpy = jest.fn();
    global.fetch = fetchSpy;
    const { sendOtpSms } = require('./sms');

    await expect(sendOtpSms('+919876543210', '123456')).rejects.toThrow(/SMS_GATEWAY_USER/);
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
