describe('sendOtpSms', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...originalEnv };
    delete process.env.SMS_PROVIDER;
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it('logs to console and does not call Twilio when SMS_PROVIDER is unset', async () => {
    const logSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
    const mockCreate = jest.fn();
    jest.doMock('twilio', () => jest.fn(() => ({ messages: { create: mockCreate } })));
    const { sendOtpSms } = require('./sms');

    await sendOtpSms('+919876543210', '123456');

    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('123456'));
    expect(mockCreate).not.toHaveBeenCalled();
    logSpy.mockRestore();
  });

  it('logs to console and does not call Twilio when SMS_PROVIDER=console', async () => {
    process.env.SMS_PROVIDER = 'console';
    const logSpy = jest.spyOn(console, 'log').mockImplementation(() => {});
    const mockCreate = jest.fn();
    jest.doMock('twilio', () => jest.fn(() => ({ messages: { create: mockCreate } })));
    const { sendOtpSms } = require('./sms');

    await sendOtpSms('+919876543210', '123456');

    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('123456'));
    expect(mockCreate).not.toHaveBeenCalled();
    logSpy.mockRestore();
  });

  it('sends via Twilio using account credentials when SMS_PROVIDER=twilio', async () => {
    process.env.SMS_PROVIDER = 'twilio';
    process.env.TWILIO_ACCOUNT_SID = 'ACxxx';
    process.env.TWILIO_AUTH_TOKEN = 'authtoken';
    process.env.TWILIO_FROM_NUMBER = '+15005550006';

    const mockCreate = jest.fn().mockResolvedValue({ sid: 'SM123' });
    const twilioFactory = jest.fn(() => ({ messages: { create: mockCreate } }));
    jest.doMock('twilio', () => twilioFactory);
    const { sendOtpSms } = require('./sms');

    await sendOtpSms('+919876543210', '123456');

    expect(twilioFactory).toHaveBeenCalledWith('ACxxx', 'authtoken');
    expect(mockCreate).toHaveBeenCalledWith(expect.objectContaining({
      to: '+919876543210',
      from: '+15005550006',
      body: expect.stringContaining('123456'),
    }));
  });

  it('propagates the error when the Twilio send fails', async () => {
    process.env.SMS_PROVIDER = 'twilio';
    process.env.TWILIO_ACCOUNT_SID = 'ACxxx';
    process.env.TWILIO_AUTH_TOKEN = 'authtoken';
    process.env.TWILIO_FROM_NUMBER = '+15005550006';

    const mockCreate = jest.fn().mockRejectedValue(new Error('Twilio down'));
    jest.doMock('twilio', () => jest.fn(() => ({ messages: { create: mockCreate } })));
    const { sendOtpSms } = require('./sms');

    await expect(sendOtpSms('+919876543210', '123456')).rejects.toThrow('Twilio down');
  });
});
