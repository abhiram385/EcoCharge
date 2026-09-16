describe('createOrder', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...originalEnv, RAZORPAY_KEY_ID: 'rzp_test_abc', RAZORPAY_KEY_SECRET: 'sekrit' };
    delete global.fetch;
  });

  afterAll(() => {
    process.env = originalEnv;
    delete global.fetch;
  });

  function mockFetch(status, body) {
    const fetchSpy = jest.fn().mockResolvedValue({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
      text: async () => JSON.stringify(body),
    });
    global.fetch = fetchSpy;
    return fetchSpy;
  }

  it('creates an order with amount converted to paise, INR, and the given receipt', async () => {
    const fetchSpy = mockFetch(200, { id: 'order_abc123', amount: 20000, currency: 'INR' });
    const { createOrder } = require('./razorpayOrders');

    const order = await createOrder({ amountRupees: 200, receipt: 'topup_1' });

    expect(order).toEqual({ id: 'order_abc123', amount: 20000, currency: 'INR' });
    const [url, options] = fetchSpy.mock.calls[0];
    expect(url).toBe('https://api.razorpay.com/v1/orders');
    expect(options.method).toBe('POST');
    expect(options.headers.Authorization).toBe('Basic ' + Buffer.from('rzp_test_abc:sekrit').toString('base64'));
    const body = JSON.parse(options.body);
    expect(body).toEqual({ amount: 20000, currency: 'INR', receipt: 'topup_1' });
  });

  it('rounds fractional rupees to the nearest paisa', async () => {
    const fetchSpy = mockFetch(200, { id: 'order_x', amount: 19999, currency: 'INR' });
    const { createOrder } = require('./razorpayOrders');

    await createOrder({ amountRupees: 199.994, receipt: 'r' });

    expect(JSON.parse(fetchSpy.mock.calls[0][1].body).amount).toBe(19999);
  });

  it('throws when the Razorpay keys are not configured', async () => {
    delete process.env.RAZORPAY_KEY_ID;
    const fetchSpy = jest.fn();
    global.fetch = fetchSpy;
    const { createOrder } = require('./razorpayOrders');

    await expect(createOrder({ amountRupees: 100, receipt: 'r' })).rejects.toThrow(/RAZORPAY_KEY_ID/);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('throws with the response detail when Razorpay rejects the request', async () => {
    mockFetch(401, { error: { description: 'Authentication failed' } });
    const { createOrder } = require('./razorpayOrders');

    await expect(createOrder({ amountRupees: 100, receipt: 'r' })).rejects.toThrow(/401/);
  });
});
