process.env.PAYMOB_SECRET_KEY = 'egy_sk_test_abc'; process.env.PAYMOB_HMAC_SECRET = 'HMACSECRET';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-key';
const repo = require('path').join(__dirname, '../api/');
const { computeHmac, hmacString } = require(repo + '_paymob.js');
const checkout = require(repo + 'paymob-checkout.js');
const webhook = require(repo + 'paymob-webhook.js');
const calls = [];
global.fetch = async (url, opts) => {
  calls.push({ url, auth: opts.headers.Authorization || opts.headers.authorization, body: JSON.parse(opts.body) });
  const ok = (d) => ({ ok: true, status: 200, text: async () => JSON.stringify(d), json: async () => d });
  if (url.endsWith('/rpc/start_online_payment')) return ok({ payment_id: '7d1e0b6a-1111-4222-8333-944445555666', invoice_no: 9,
    amount_cents: 350000, package_name: '12 sessions', member_name: 'Omar', payer_name: 'Omar Ali Hassan', payer_email: 'o@x.com', payer_phone: '0100' });
  if (url.endsWith('/v1/intention/')) return ok({ client_secret: 'egy_csk_test_xyz', intention_order_id: 123456 });
  if (url.endsWith('/rpc/set_payment_provider_order')) return ok(null);
  if (url.endsWith('/rpc/confirm_online_payment')) return ok('paid');
  throw new Error('unexpected ' + url);
};
function mockRes() { const r = { code: 0, out: null }; r.status = (c) => { r.code = c; return r; }; r.json = (o) => { r.out = o; return r; }; r.send = (o) => { r.out = o; return r; }; return r; }
(async () => {
  let res = mockRes();
  await checkout({ method: 'POST', headers: { authorization: 'Bearer USERJWT', host: 'kfk.vercel.app' }, body: { member_id: 'm', package_code: 'adult_12' } }, res);
  console.log('checkout', res.code, res.out.url);
  const intent = calls.find((c) => c.url.endsWith('/v1/intention/'));
  console.log('intent auth', intent.auth, 'amount', intent.body.amount, 'methods', intent.body.payment_methods, 'notify', intent.body.notification_url, 'redirect', intent.body.redirection_url, 'name', intent.body.billing_data.first_name, '|', intent.body.billing_data.last_name);
  console.log('start rpc auth uses user token:', calls[0].auth === 'Bearer USERJWT', ' order saved:', calls.find(c=>c.url.endsWith('set_payment_provider_order')).body);
  const obj = { id: 999, pending: false, amount_cents: 350000, success: true, is_auth: false, is_capture: false, is_standalone_payment: true,
    is_voided: false, is_refunded: false, is_3d_secure: true, integration_id: 5979343, has_parent_transaction: false, error_occured: false,
    created_at: '2026-10-12T15:00:00.000000', currency: 'EGP', owner: 42, order: { id: 123456, merchant_order_id: '7d1e0b6a-1111-4222-8333-944445555666' },
    source_data: { pan: '2346', sub_type: 'MasterCard', type: 'card' } };
  console.log('hmac string', hmacString(obj));
  res = mockRes(); await webhook({ method: 'POST', query: { hmac: 'deadbeef' }, body: { type: 'TRANSACTION', obj } }, res);
  console.log('bad hmac ->', res.code, res.out);
  res = mockRes(); await webhook({ method: 'POST', query: { hmac: computeHmac(obj, 'HMACSECRET') }, body: { type: 'TRANSACTION', obj } }, res);
  const conf = calls.find((c) => c.url.endsWith('confirm_online_payment'));
  console.log('good hmac ->', res.code, res.out, 'confirm args', conf.body, 'auth service', conf.auth === 'Bearer service-key');
  res = mockRes(); await webhook({ method: 'POST', query: { hmac: computeHmac({ ...obj, pending: true }, 'HMACSECRET') }, body: { type: 'TRANSACTION', obj: { ...obj, pending: true } } }, res);
  console.log('pending ->', res.out);
  delete process.env.PAYMOB_SECRET_KEY; res = mockRes();
  await checkout({ method: 'POST', headers: { authorization: 'Bearer X' }, body: {} }, res); console.log('no key ->', res.code, res.out);
})();
