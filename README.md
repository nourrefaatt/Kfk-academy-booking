# KFK Academy — Booking System

Online booking for KFK Muay Thai & MMA: client, parent, coach and owner portals, in English and Arabic.
All rules (packages, weekly limits, 3-hour cancel rule, waiting list, expiry, cash approval) are in
[`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) and enforced inside the database.

## How it is built

| Part | What it is |
|---|---|
| `index.html`, `css/`, `js/` | The website (plain HTML/CSS/JS, no build step) |
| `supabase/schema.sql` | Database tables, rules, permissions. Run once in Supabase |
| `supabase/migrations/` | Updates to run after `schema.sql`, in number order (each keeps existing data) |
| `supabase/cron.sql` | Optional hourly job for expiry reminders |
| `tests/db/` | Tests for the booking rules (run on a local Postgres) |
| `assets/brand/` | KFK logos and visual identity |

## Setup (once)

1. **Database** — Supabase → **SQL Editor** → **New query** → paste all of `supabase/schema.sql` → **Run**.
   (Running it again later deletes all app data — only re-run before launch.)
   Then run each file in `supabase/migrations/` in number order, the same way.
2. **Login settings** — Supabase → **Authentication → URL Configuration**: set **Site URL** to the
   Vercel address of the site (e.g. `https://kfk-academy-booking.vercel.app`) and add the same address
   under **Redirect URLs**. This makes confirmation and password-reset emails open the site.
3. **Website** — Vercel → **Add New → Project** → import this repository → **Deploy** (no settings needed).
4. **Owner account** — sign up on the site as a client with the owner's email, then in Supabase →
   SQL Editor run:
   ```sql
   update profiles set role = 'owner' where email = 'OWNER_EMAIL_HERE';
   ```
5. **Coaches** — a coach signs up normally; the owner changes their role to *Coach* in **Accounts**.
6. *(Optional)* Supabase → **Database → Extensions** → enable **pg_cron**, then run `supabase/cron.sql`.

## Payments

- **Card (Paymob)** — `api/paymob-checkout.js` starts a payment (rules checked in the database), the client
  pays on Paymob's page, and `api/paymob-webhook.js` confirms it only if Paymob's HMAC signature is valid.
  Vercel → Settings → Environment Variables (never put these in code or chat):
  `PAYMOB_SECRET_KEY`, `PAYMOB_HMAC_SECRET`, `SUPABASE_SERVICE_ROLE_KEY`.
  Optional: `PAYMOB_PUBLIC_KEY`, `PAYMOB_CARD_INTEGRATION_ID` (defaults are the test values).
  In Paymob, set the transaction callback URL to `https://<site>/api/paymob-webhook`.
  In the site's Settings, turn **off** "Simulated online payments" to use Paymob.
- **Cash / InstaPay** — waits for coach approval; the 30 days start at approval.
