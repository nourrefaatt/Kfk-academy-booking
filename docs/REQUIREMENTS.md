# KFK Academy — Booking System Requirements

Source of truth for what the system must do. Every number, price, date and rule here
was given by the owner (Seif). **Do not invent values.** Anything marked `TBD` must be
confirmed with the owner before it is built in.

- Business name in the app: **KFK Academy** (never "Les Rois")
- Location: **Smash Club Les Rois** — coordinates 30.005711, 31.508550
  (shown to clients as the place of every KFK Academy class)
- Languages: **English and Arabic** (Arabic right-to-left)
- Branding (from owner's visual identity, files in `assets/brand/`):
  - Colours: white `#FFFFFF`, black `#000000`, red `#BD0000`
  - Fonts: Montserrat, Horizon, Canva Sans
  - Full logo: "KFK" (KF black, K red with black fighter-kick silhouette) +
    "MUAYTHAI & MMA" in red — stacked (`logo-full-stacked.jpeg`) and horizontal
    (`logo-full-horizontal.jpeg`) versions. Use exactly as provided.
  - Icon mark: red K with fighter silhouette, no text — for small/square spaces
    (app icon, favicon). Black fighter on light backgrounds, white fighter on black.
  - Originals are JPEG on white. Transparent PNGs made from them (same artwork):
    `logo-full-stacked.png`, `logo-full-horizontal.png` (for light backgrounds),
    `logo-full-stacked-on-dark.png`, `logo-full-horizontal-on-dark.png` (KF in white, for black
    backgrounds), `icon-k-black-fighter.png`, `icon-k-white-fighter.png`.
- Currency: **EGP**
- Time zone: Africa/Cairo
- Out of scope: PT / 1-on-1, private groups, Revolt sessions

---

## 1. Client portal (age 13 and up)

- Books **adult classes only**. Adult classes are only available in this portal.
- Sign in with **email + password**.
- A parent who also trains needs their own client account.
- Profile: name, date of birth, phone, email, emergency contact, injuries / medical notes,
  past martial-arts experience.

### Packages
| Package | Price | Weekly limit |
|---|---|---|
| 12 sessions | 3,500 EGP | 4 classes per week |
| Drop-in (1 session) | 500 EGP | — |

## 2. Parent portal (children under 13)

- Books **kids classes only**, for each child.
- One parent account, **each child managed separately**: balance, expiry date, payments,
  bookings.
- Parent can add children. Child profile: name, date of birth, emergency contact,
  injuries / medical notes, past martial-arts experience.
- Each child pays in a **separate transaction with a separate invoice**.
- When a child turns 13 they move to their own client account.

### Packages
| Package | Price | Weekly limit |
|---|---|---|
| 8 sessions | 2,800 EGP | 2 classes per week |
| Drop-in (1 session) | 500 EGP | — |

## 3. Rules shared by clients and children

### Balance and expiry
- A package expires **30 days after payment**.
- When the balance reaches 0 or the package expires, the balance resets to 0 and no more
  bookings are possible until a recharge.
- **Early recharge is allowed.** Leftover sessions carry over but must be used within
  **7 days of the recharge date**, after which they are removed. Leftover sessions are
  used first. New package sessions last the full 30 days.
- If the coach cancels a class after the package has expired, the session is returned
  and must be used **within 7 days of the expiry date**.
- Expiry reminder **7 days before expiry**, by **email and in-portal**.

### Weekly limit
- Week runs **Saturday to Friday**.
- Drop-ins **cannot** be bought to go over the weekly limit.

### Booking
- Each week's classes open for booking at **Friday midnight** (start of the Saturday–Friday
  week) and can be booked **up to 12 hours after the class ends** (so someone who forgot to
  book can still add the class they attended).
- **Only one class per day.**
- If a class has a capacity and is full, the person joins a **waiting list**.
  When a spot opens, the next person on the list is **booked automatically** (one session
  deducted) and **notified**; they can cancel afterwards under the normal cancel rules.
  People who can no longer take the spot (no balance, weekly limit reached, already booked
  that day) are skipped.
- Booking deducts one session from the balance.
- Portal shows all upcoming (not yet attended) bookings with time and place.

### Cancelling
- Clients/parents can cancel up to **3 hours before** the class. Later than that, the
  session is counted as used.
- **No-show counts** as a used session.
- If the **coach cancels** a class: it disappears from bookings, the session returns to
  the balance as if never booked, and booked people are **notified automatically**.

### Payments
- **Online** (provider: Paymob, account `TBD`) or **cash**.
- Cash payments must be **approved by a coach** before the person can book.
- **No refunds** — stated clearly in a *Rules & guidelines* page in every portal and under the packages.
- Cash payments are labelled **Cash / InstaPay**. When chosen, the box shows *Cash: book at the gym* and
  *InstaPay: account 01006833976*. The 30 days start when the coach **approves** the payment.

## 4. Coach portal

- Currently one coach: **Seif**. Must support adding more coaches later.
  Coach accounts are created by the **owner**. Every coach sees **all** classes.
- Per day: number of classes, which classes, classes left today, number of attendees.
- **Attendance list** per class, filled automatically from bookings; coach marks who came.
- **Expiring soon** list: people whose package expires within **4 days**, with a button
  to notify them.
- **Cancel a class**: removed from bookings, sessions refunded to balances, people notified.
  Cancelled classes are listed **per month with dates**.
- **Announcements** to parent accounts, client accounts, or all accounts (in-portal).
- **Private messages**: the coach picks any client/parent account and writes to it; the account can reply.
- **Classes:** weekly repeating; coach can edit timings. When adding, the coach can pick several days —
  one separate class is created per day, each editable on its own. Fields: name, adults/kids,
  location, day, time, duration, coach, capacity (**optional per class**; no capacity =
  unlimited).
- Add / remove classes. **Lock** a class completely (no one can see or book it).
- Approve cash payments.

## 5. Owner dashboard

- The owner is Seif and can also do everything a coach can.
- Owner can **lock all new bookings or payments** at any time for any reason.
- **Manages all accounts freely** — coaches, clients, parents and children: create, edit
  details, deactivate / delete, and adjust balances, expiry dates and bookings.
- Financials, split **adults vs kids**:
  - Revenue per month and % change from last month (revenue only, no expenses/profit)
  - Pending transactions (cash payments awaiting approval)
- Total bookings, active packages
- Client retention: % of people whose package ended (used up or expired) who recharged
  **within 2 weeks**
- Attendance rate, most popular classes, no-show rate
- Total classes cancelled by coach per month

## Notifications (email + in-portal)
- Booking / cancellation confirmations
- Expiry reminder (7 days before)
- Coach cancelled a class
- "Expiring soon" notice sent by coach
- Announcements

## Open questions (`TBD`)
- When does a **drop-in** expire? (Until answered, drop-ins do not expire.)
- Notifications are in-portal for now; **email** sending needs an email service account.
1. Horizon font file (licensed for web). Canva Sans is only available inside Canva —
   confirm Montserrat as the web replacement.
2. Accounts to create: Paymob merchant, Supabase (database + login), Vercel (hosting),
   email sending service.
