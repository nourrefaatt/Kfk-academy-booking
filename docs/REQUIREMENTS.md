# KFK Academy — Booking System Requirements

Source of truth for what the system must do. Every number, price, date and rule here
was given by the owner (Seif). **Do not invent values.** Anything marked `TBD` must be
confirmed with the owner before it is built in.

- Business name in the app: **KFK Academy** (never "Les Rois")
- Location / address: `TBD` (owner will provide)
- Languages: **English and Arabic** (Arabic right-to-left)
- Branding (from owner's visual identity, files in `assets/brand/`):
  - Colours: white `#FFFFFF`, black `#000000`, red `#BD0000`
  - Fonts: Montserrat, Horizon, Canva Sans
  - Full logo: "KFK" (KF black, K red with black fighter-kick silhouette) +
    "MUAYTHAI & MMA" in red — stacked (`logo-full-stacked.jpeg`) and horizontal
    (`logo-full-horizontal.jpeg`) versions. Use exactly as provided.
  - Icon mark: red K with fighter silhouette, no text — for small/square spaces
    (app icon, favicon). Black fighter on light backgrounds, white fighter on black.
  - Provided as JPEG with white background; transparent PNG/SVG versions `TBD`.
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
| 8 sessions | 3,500 EGP | 2 classes per week |
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
- Each week's classes open for booking **at the start of the week** and can be booked
  **up to the end of the class time**. Exact opening time: `TBD`.
- **Only one class per day.**
- If a class has a capacity and is full, the person joins a **waiting list**.
  What happens when a spot opens (auto-book vs notify): `TBD`.
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
- **Refunds:** the person fills in a refund form; the coach accepts or rejects it with a
  reason.

## 4. Coach portal

- Currently one coach: **Seif**. Must support adding more coaches later.
  Coach accounts are created by the **owner**. Every coach sees **all** classes.
- Per day: number of classes, which classes, classes left today, number of attendees.
- **Attendance list** per class, filled automatically from bookings; coach marks who came.
- **Expiring soon** list: people whose package expires within **4 days**, with a button
  to notify them.
- **Cancel a class**: removed from bookings, sessions refunded to balances, people notified.
  Cancelled classes are listed **per month with dates**.
- **Announcements** to all clients and parents (email + in-portal).
- **Classes:** weekly repeating; coach can edit timings. Fields: name, adults/kids,
  location, day, time, duration, coach, capacity (**optional per class**; no capacity =
  unlimited).
- Add / remove classes. **Lock** a class completely (no one can see or book it).
- Approve cash payments. Accept / reject refund requests.

## 5. Owner dashboard

- The owner is Seif and can also do everything a coach can.
- Owner can **lock all new bookings or payments** at any time for any reason.
- Create coach accounts.
- Financials, split **adults vs kids**:
  - Revenue per month and % change from last month
  - Profit (`TBD`: needs expenses input?)
  - Pending transactions (cash awaiting approval, refund requests)
- Total bookings, active packages, client retention (definition `TBD`)
- Attendance rate, most popular classes, no-show rate
- Total classes cancelled by coach per month

## Notifications (email + in-portal)
- Booking / cancellation confirmations
- Expiry reminder (7 days before)
- Coach cancelled a class
- "Expiring soon" notice sent by coach
- Announcements

## Open questions (`TBD`)
1. Exact time a week's classes open for booking (e.g. Saturday 00:00?).
2. Waiting list: when a spot opens, auto-book the next person (and deduct a session), or
   notify them to book?
3. Client retention: how should it be measured?
4. Profit: should the owner enter expenses, or show revenue only?
5. Refund form: what fields/reasons? Is online money refunded through Paymob, cash by hand?
6. Location address. Logo as transparent PNG or SVG. Horizon font file (licensed for web)
   and whether Canva Sans can be replaced on the web (it is only available inside Canva).
7. Accounts to create: Paymob merchant, Supabase (database + login), Vercel (hosting),
   email sending service.
