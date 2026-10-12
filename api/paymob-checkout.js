// POST /api/paymob-checkout  { member_id, package_code }  (header: Authorization: Bearer <login token>)
// Creates a pending card payment (all booking rules checked in the database), then a Paymob
// payment intention, and returns the Paymob checkout page URL.
const { supabaseRpc, siteUrl, PAYMOB_PUBLIC_KEY, PAYMOB_CARD_INTEGRATION_ID, PAYMOB_API } = require('./_paymob');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') { res.status(405).json({ error: 'Method not allowed' }); return; }
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (!token) { res.status(401).json({ error: 'Please log in again' }); return; }
  if (!process.env.PAYMOB_SECRET_KEY) { res.status(503).json({ error: 'Online payment is not available yet' }); return; }

  const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
  const { member_id: memberId, package_code: packageCode } = body;
  if (!memberId || !packageCode) { res.status(400).json({ error: 'Missing member or package' }); return; }

  try {
    // 1. Pending payment, created as the logged-in person (permissions + rules checked)
    const p = await supabaseRpc('start_online_payment', { p_member: memberId, p_package: packageCode }, token);

    // 2. Paymob payment intention
    const [first, ...rest] = String(p.payer_name || 'KFK Client').trim().split(/\s+/);
    const base = siteUrl(req);
    const intention = {
      amount: p.amount_cents,
      currency: 'EGP',
      payment_methods: [PAYMOB_CARD_INTEGRATION_ID],
      items: [{ name: `KFK ${p.package_name}`.slice(0, 50), amount: p.amount_cents,
        description: `${p.package_name} for ${p.member_name} (invoice #${p.invoice_no})`.slice(0, 255), quantity: 1 }],
      billing_data: {
        first_name: first || 'KFK', last_name: rest.join(' ') || 'Client',
        email: p.payer_email || 'no-email@kfk.academy', phone_number: p.payer_phone || 'NA',
        apartment: 'NA', floor: 'NA', street: 'NA', building: 'NA', city: 'Cairo', state: 'Cairo',
        country: 'EG', postal_code: 'NA',
      },
      special_reference: p.payment_id,
      notification_url: `${base}/api/paymob-webhook`,
      redirection_url: `${base}/?kfk_payment=${p.payment_id}`,
    };
    const r = await fetch(`${PAYMOB_API}/v1/intention/`, {
      method: 'POST',
      headers: { Authorization: `Token ${process.env.PAYMOB_SECRET_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(intention),
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok || !data.client_secret) {
      console.error('Paymob intention failed', r.status, JSON.stringify(data).slice(0, 500));
      res.status(502).json({ error: 'Could not start the card payment. Please try again.' });
      return;
    }

    // 3. Remember Paymob's order number so its callback can be matched to this payment
    const orderId = data.intention_order_id || (data.payment_keys && data.payment_keys[0] && data.payment_keys[0].order_id);
    if (orderId) {
      await supabaseRpc('set_payment_provider_order', { p_payment: p.payment_id, p_order: String(orderId) }, token)
        .catch((e) => console.error('Could not save order id', e.message));
    }

    res.status(200).json({
      payment_id: p.payment_id,
      url: `${PAYMOB_API}/unifiedcheckout/?publicKey=${encodeURIComponent(PAYMOB_PUBLIC_KEY)}` +
           `&clientSecret=${encodeURIComponent(data.client_secret)}`,
    });
  } catch (e) {
    res.status(e.status && e.status < 500 ? 400 : 500).json({ error: e.message || 'Payment error' });
  }
};
