# Launch checklist (when Paymob approves and the domain is bought)

1. **Domain** — buy it, then Vercel → Settings → Domains → add it (follow Vercel's DNS steps).
2. **Supabase → Authentication → URL Configuration** — set Site URL and Redirect URLs to the new domain.
3. **Emails** — connect an email service (Resend with the new domain), then Supabase →
   Authentication → Sign In / Providers → Email → turn **Confirm email** back on.
4. **Paymob live** — switch the dashboard to Live; send Claude the live Public Key and live Card
   Integration ID; in Vercel replace `PAYMOB_SECRET_KEY` and `PAYMOB_HMAC_SECRET` with the live ones,
   add `PAYMOB_PUBLIC_KEY` and `PAYMOB_CARD_INTEGRATION_ID`; Redeploy. Tell Paymob the new website domain.
5. **Clean test data** — delete test accounts, bookings and payments (Claude will give the exact SQL).
6. **Real classes** — owner adds the real weekly schedule in Classes.
7. **One small real card payment** to confirm everything, then announce to clients.

Still open: drop-in expiry (currently never expires); optional hourly job (`supabase/cron.sql`).
