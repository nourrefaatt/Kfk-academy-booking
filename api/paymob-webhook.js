// POST /api/paymob-webhook?hmac=...   Paymob's "transaction processed" callback.
// The HMAC signature proves the message really comes from Paymob. Only then the payment is
// confirmed in the database (with the private service key) and the sessions are added.
const { supabaseRpc, validHmac } = require('./_paymob');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { res.status(200).send('ok'); return; }
  const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
  if (body.type && body.type !== 'TRANSACTION') { res.status(200).json({ ignored: body.type }); return; }
  const obj = body.obj || {};

  if (!validHmac(obj, req.query && req.query.hmac, process.env.PAYMOB_HMAC_SECRET)) {
    console.error('Paymob webhook: bad HMAC for transaction', obj.id);
    res.status(401).json({ error: 'Invalid signature' });
    return;
  }
  if (obj.pending === true) { res.status(200).json({ status: 'pending' }); return; }

  const ref = obj.order && obj.order.merchant_order_id;
  try {
    const result = await supabaseRpc('confirm_online_payment', {
      p_payment: ref && UUID.test(String(ref)) ? String(ref) : null,
      p_order: obj.order && obj.order.id != null ? String(obj.order.id) : null,
      p_txn: obj.id != null ? String(obj.id) : null,
      p_amount_cents: Number(obj.amount_cents),
      p_success: obj.success === true && obj.is_voided !== true && obj.is_refunded !== true,
      p_test: String(process.env.PAYMOB_SECRET_KEY || '').includes('_test_'),
    }, null, true);
    res.status(200).json({ status: result });
  } catch (e) {
    console.error('Paymob webhook: database error', e.message);
    res.status(500).json({ error: 'Could not record payment' });   // Paymob retries later
  }
};
