// Shared helpers for the Paymob server functions (runs on Vercel, never in the browser).
// Private settings come from Vercel → Settings → Environment Variables:
//   PAYMOB_SECRET_KEY, PAYMOB_HMAC_SECRET, SUPABASE_SERVICE_ROLE_KEY   (secret — never in code)
//   PAYMOB_PUBLIC_KEY, PAYMOB_CARD_INTEGRATION_ID                     (optional overrides)
const crypto = require('crypto');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://rgwurjqmacbuduxcyiib.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJnd3VyanFtYWNidWR1eGN5aWliIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE3NDg0MzgsImV4cCI6MjEwNzMyNDQzOH0.g2Gc-9976ms4-8aeoYxs5ACJHCE2KC1zLlZnWnNkYKA';
const PAYMOB_PUBLIC_KEY = process.env.PAYMOB_PUBLIC_KEY || 'egy_pk_test_WAb7ZjAtfzKZqwFmeLSwh5SbSw889wdg';
const PAYMOB_CARD_INTEGRATION_ID = Number(process.env.PAYMOB_CARD_INTEGRATION_ID || 5979343);
const PAYMOB_API = process.env.PAYMOB_API || 'https://accept.paymob.com';

// Call a Supabase database function. token = the person's login token, or the service key.
async function supabaseRpc(name, args, token, useServiceKey = false) {
  const key = useServiceKey ? process.env.SUPABASE_SERVICE_ROLE_KEY : SUPABASE_ANON_KEY;
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${token || key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const err = new Error((data && (data.message || data.error)) || `Database error ${res.status}`);
    err.status = res.status;
    throw err;
  }
  return data;
}

// Paymob signs every transaction callback: HMAC-SHA512 of these fields, in this exact order.
const HMAC_FIELDS = ['amount_cents', 'created_at', 'currency', 'error_occured', 'has_parent_transaction', 'id',
  'integration_id', 'is_3d_secure', 'is_auth', 'is_capture', 'is_refunded', 'is_standalone_payment', 'is_voided',
  'order.id', 'owner', 'pending', 'source_data.pan', 'source_data.sub_type', 'source_data.type', 'success'];

function pick(obj, path) {
  return path.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);
}
function hmacString(obj) {
  return HMAC_FIELDS.map((f) => {
    const v = pick(obj, f);
    return v === undefined || v === null ? '' : String(v);
  }).join('');
}
function computeHmac(obj, secret) {
  return crypto.createHmac('sha512', secret).update(hmacString(obj)).digest('hex');
}
function validHmac(obj, received, secret) {
  if (!received || !secret) return false;
  const a = Buffer.from(computeHmac(obj, secret), 'hex');
  const b = Buffer.from(String(received).toLowerCase(), 'hex');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function siteUrl(req) {
  if (process.env.SITE_URL) return process.env.SITE_URL.replace(/\/$/, '');
  const proto = req.headers['x-forwarded-proto'] || 'https';
  return `${proto}://${req.headers['x-forwarded-host'] || req.headers.host}`;
}

module.exports = { supabaseRpc, computeHmac, validHmac, hmacString, siteUrl,
  PAYMOB_PUBLIC_KEY, PAYMOB_CARD_INTEGRATION_ID, PAYMOB_API };
