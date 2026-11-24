// POST /api/paymob-webhook?hmac=...   (or hmac in the JSON body)   Paymob's "transaction processed" callback.
// The HMAC signature proves the message really comes from Paymob. Only then the payment is
// confirmed in the database (with the private service key) and the sessions are added.
const { supabaseRpc, validHmac, hmacString } = require('./_paymob');

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { res.status(200).send('ok'); return; }
  const body = parseBody(req.body);
  if (body.type && body.type !== 'TRANSACTION') { res.status(200).json({ ignored: body.type }); return; }
  // Normally { type, obj: {...transaction} }; some senders post the transaction itself.
  const obj = (body.obj && typeof body.obj === 'object') ? body.obj
    : (body.id != null && body.amount_cents != null ? body : {});

  // Paymob normally puts the signature in the link (?hmac=…); some relays (e.g. the Integration Wizard) send it in the body.
  const received = (req.query && req.query.hmac) || body.hmac;
  if (!validHmac(obj, received, process.env.PAYMOB_HMAC_SECRET)) {
    // Diagnostics only (no secrets): where the signature came from and what was signed.
    console.error('Paymob webhook: bad HMAC for transaction', obj.id, {
      from: req.query && req.query.hmac ? 'query' : (body.hmac ? 'body' : 'none'),
      contentType: req.headers && req.headers['content-type'],
      bodyKeys: Object.keys(body).slice(0, 20),
      secretLength: String(process.env.PAYMOB_HMAC_SECRET || '').trim().length,
      signed: hmacString(obj),
    });
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

// Accept a JSON object, a JSON string, a raw buffer, or form-encoded text.
function parseBody(raw) {
  if (raw == null) return {};
  if (Buffer.isBuffer(raw)) raw = raw.toString('utf8');
  if (typeof raw === 'object') return raw;
  const text = String(raw).trim();
  if (!text) return {};
  try { return JSON.parse(text); } catch (_) { /* not JSON */ }
  try {
    const out = {};
    for (const [k, v] of new URLSearchParams(text)) out[k] = v;
    if (typeof out.obj === 'string') { try { out.obj = JSON.parse(out.obj); } catch (_) { /* keep */ } }
    return out;
  } catch (_) { return {}; }
}
