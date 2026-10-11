-- =====================================================================
-- KFK Academy booking system — database schema, rules and permissions
-- Run once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
-- WARNING: running it again DELETES all app data (members, bookings, payments).
-- Only re-run before launch. It never touches Supabase's own login accounts.
-- Every number here comes from docs/REQUIREMENTS.md.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Clean slate for re-runs (app objects only, never auth data)
-- ---------------------------------------------------------------------
drop trigger if exists on_auth_user_created on auth.users;
drop table if exists notifications, waitlist, bookings, sessions, classes,
  lots, payments, members, profiles, packages, settings cascade;
drop type if exists app_role, member_kind, audience, booking_status,
  payment_method, payment_status, session_status cascade;

create type app_role       as enum ('client','parent','coach','owner');
create type member_kind    as enum ('adult','child');
create type audience       as enum ('adults','kids');
create type booking_status as enum ('booked','cancelled','late_cancel','attended',
                                    'no_show','cancelled_by_coach');
create type payment_method as enum ('online','cash');
create type payment_status as enum ('pending','paid','rejected');
create type session_status as enum ('scheduled','cancelled');

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------
create table settings (
  id               int primary key default 1 check (id = 1),
  bookings_locked  boolean not null default false,  -- owner: stop all new bookings
  payments_locked  boolean not null default false,  -- owner: stop all new payments
  online_test_mode boolean not null default true,   -- until Paymob is live
  location_name    text not null default 'Smash Club Les Rois',
  location_lat     numeric default 30.005711,
  location_lng     numeric default 31.508550,
  updated_at       timestamptz not null default now()
);
insert into settings default values;

create table packages (
  code          text primary key,
  audience      audience not null,
  name_en       text not null,
  name_ar       text not null,
  sessions      int  not null check (sessions > 0),
  price_egp     numeric(10,2) not null,
  weekly_limit  int,            -- null = no weekly limit
  validity_days int,            -- null = does not expire
  is_drop_in    boolean not null default false,
  active        boolean not null default true,
  sort          int not null default 0
);
-- From the owner. Drop-in expiry was not given: validity_days is null (TBD).
insert into packages values
 ('adult_12',    'adults', '12 sessions', '١٢ حصة',  12, 3500, 4,    30,   false, true, 1),
 ('adult_dropin','adults', 'Drop-in',     'حصة واحدة', 1,  500, null, null, true,  true, 2),
 ('kids_8',      'kids',   '8 sessions',  '٨ حصص',    8, 2800, 2,    30,   false, true, 1),
 ('kids_dropin', 'kids',   'Drop-in',     'حصة واحدة', 1,  500, null, null, true,  true, 2);

create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       app_role not null default 'client',
  full_name  text not null default '',
  email      text,
  phone      text,
  locale     text not null default 'en' check (locale in ('en','ar')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- A member is a person who trains: an adult client, or a parent's child.
create table members (
  id                uuid primary key default gen_random_uuid(),
  account_id        uuid not null references profiles(id) on delete cascade,
  kind              member_kind not null,
  full_name         text not null,
  date_of_birth     date,
  phone             text,
  emergency_contact text,
  medical_notes     text,
  experience        text,
  active            boolean not null default true,
  created_at        timestamptz not null default now()
);
create index on members(account_id);

create table payments (
  id           uuid primary key default gen_random_uuid(),
  invoice_no   bigint generated always as identity unique,
  member_id    uuid not null references members(id) on delete cascade,
  package_code text not null references packages(code),
  amount_egp   numeric(10,2) not null,
  method       payment_method not null,
  status       payment_status not null default 'pending',
  test_mode    boolean not null default false,
  created_by   uuid references profiles(id),
  decided_by   uuid references profiles(id),
  decided_at   timestamptz,
  note         text,
  created_at   timestamptz not null default now()
);
create index on payments(member_id);

-- A "lot" is a batch of sessions on a member's balance.
create table lots (
  id              uuid primary key default gen_random_uuid(),
  member_id       uuid not null references members(id) on delete cascade,
  payment_id      uuid references payments(id) on delete set null,
  source          text not null default 'package', -- package | dropin | returned | manual
  sessions_total  int not null,
  sessions_left   int not null check (sessions_left >= 0),
  weekly_limit    int,
  is_drop_in      boolean not null default false,
  starts_at       timestamptz not null default now(),
  expires_at      timestamptz,                     -- null = no expiry
  reminder_sent   boolean not null default false,
  depleted_at     timestamptz,
  expired_sessions int not null default 0,
  created_at      timestamptz not null default now()
);
create index on lots(member_id);

create table classes (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  audience     audience not null,
  weekday      int not null check (weekday between 0 and 6), -- 0 = Sunday … 6 = Saturday
  start_time   time not null,
  duration_min int not null check (duration_min > 0),
  capacity     int check (capacity is null or capacity > 0), -- null = unlimited
  coach_id     uuid references profiles(id),
  location     text,
  locked       boolean not null default false,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

create table sessions (
  id            uuid primary key default gen_random_uuid(),
  class_id      uuid not null references classes(id) on delete cascade,
  session_date  date not null,                   -- Cairo date
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  capacity      int,
  status        session_status not null default 'scheduled',
  cancelled_at  timestamptz,
  cancelled_by  uuid references profiles(id),
  cancel_reason text,
  unique (class_id, session_date)
);
create index on sessions(starts_at);

create table bookings (
  id           uuid primary key default gen_random_uuid(),
  session_id   uuid not null references sessions(id) on delete cascade,
  member_id    uuid not null references members(id) on delete cascade,
  lot_id       uuid references lots(id) on delete set null,
  status       booking_status not null default 'booked',
  booked_by    uuid references profiles(id),
  from_waitlist boolean not null default false,
  created_at   timestamptz not null default now(),
  cancelled_at timestamptz
);
create index on bookings(member_id);
create index on bookings(session_id);
create unique index bookings_one_live on bookings(session_id, member_id)
  where status in ('booked','attended','no_show','late_cancel');

create table waitlist (
  id         uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions(id) on delete cascade,
  member_id  uuid not null references members(id) on delete cascade,
  added_by   uuid references profiles(id),
  created_at timestamptz not null default now(),
  unique (session_id, member_id)
);

create table notifications (
  id         uuid primary key default gen_random_uuid(),
  account_id uuid not null references profiles(id) on delete cascade,
  member_id  uuid references members(id) on delete cascade,
  kind       text not null,
  title      text not null,
  body       text not null default '',
  read_at    timestamptz,
  created_at timestamptz not null default now()
);
create index on notifications(account_id, created_at desc);

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------
create or replace function cairo_now() returns timestamp language sql stable as
$$ select (now() at time zone 'Africa/Cairo') $$;

-- Saturday that starts the Saturday→Friday week containing d
create or replace function week_start(d date) returns date language sql immutable as
$$ select d - ((extract(dow from d)::int + 1) % 7) $$;

create or replace function my_role() returns app_role language sql stable
security definer set search_path = public as
$$ select role from profiles where id = auth.uid() $$;

create or replace function is_staff() returns boolean language sql stable
security definer set search_path = public as
$$ select coalesce((select role in ('coach','owner') and active from profiles where id = auth.uid()), false) $$;

create or replace function is_owner() returns boolean language sql stable
security definer set search_path = public as
$$ select coalesce((select role = 'owner' and active from profiles where id = auth.uid()), false) $$;

create or replace function owns_member(m uuid) returns boolean language sql stable
security definer set search_path = public as
$$ select exists(select 1 from members where id = m and account_id = auth.uid()) $$;

create or replace function can_manage_member(m uuid) returns boolean language sql stable
security definer set search_path = public as
$$ select owns_member(m) or is_staff() $$;

create or replace function notify(p_account uuid, p_member uuid, p_kind text, p_title text, p_body text)
returns void language sql security definer set search_path = public as
$$ insert into notifications(account_id, member_id, kind, title, body)
   values (p_account, p_member, p_kind, p_title, coalesce(p_body,'')) $$;

create or replace function notify_member(p_member uuid, p_kind text, p_title text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare v_acc uuid;
begin
  select account_id into v_acc from members where id = p_member;
  if v_acc is not null then perform notify(v_acc, p_member, p_kind, p_title, p_body); end if;
end $$;

-- ---------------------------------------------------------------------
-- New sign-ups: create profile (+ adult member for clients)
-- ---------------------------------------------------------------------
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_role app_role := case when meta->>'role' = 'parent' then 'parent'::app_role else 'client'::app_role end;
  v_dob date := nullif(meta->>'date_of_birth','')::date;
begin
  if v_role = 'client' and v_dob is not null
     and v_dob > (cairo_now()::date - interval '13 years') then
    raise exception 'Client accounts are for ages 13 and up';
  end if;
  insert into profiles(id, role, full_name, email, phone, locale)
  values (new.id, v_role, coalesce(meta->>'full_name',''), new.email, meta->>'phone',
          case when meta->>'locale' = 'ar' then 'ar' else 'en' end);
  if v_role = 'client' then
    insert into members(account_id, kind, full_name, date_of_birth, phone,
                        emergency_contact, medical_notes, experience)
    values (new.id, 'adult', coalesce(meta->>'full_name',''), v_dob, meta->>'phone',
            meta->>'emergency_contact', meta->>'medical_notes', meta->>'experience');
  end if;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------------
-- Sessions: generate the current and next Saturday→Friday weeks
-- ---------------------------------------------------------------------
create or replace function ensure_sessions() returns void
language plpgsql security definer set search_path = public as $$
declare w date := week_start(cairo_now()::date); wk int; c record; d date;
begin
  for wk in 0..1 loop
    for c in select * from classes where active loop
      d := w + wk*7 + ((c.weekday - 6 + 7) % 7);
      insert into sessions(class_id, session_date, starts_at, ends_at, capacity)
      values (c.id, d,
              (d + c.start_time) at time zone 'Africa/Cairo',
              (d + c.start_time + make_interval(mins => c.duration_min)) at time zone 'Africa/Cairo',
              c.capacity)
      on conflict (class_id, session_date) do nothing;
    end loop;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Balance
-- ---------------------------------------------------------------------
create or replace function valid_lots(p_member uuid) returns setof lots
language sql stable security definer set search_path = public as $$
  select * from lots where member_id = p_member
    and (expires_at is null or expires_at > now())
$$;

create or replace function member_weekly_limit(p_member uuid) returns int
language sql stable security definer set search_path = public as $$
  select max(weekly_limit) from valid_lots(p_member) where not is_drop_in and weekly_limit is not null
$$;

create or replace function member_week_count(p_member uuid, p_week date) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from bookings b join sessions s on s.id = b.session_id
  where b.member_id = p_member
    and b.status in ('booked','attended','no_show','late_cancel')
    and week_start(s.session_date) = p_week
$$;

create or replace function member_balance(p_member uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not can_manage_member(p_member) then raise exception 'Not allowed'; end if;
  select jsonb_build_object(
    'sessions_left', coalesce(sum(sessions_left),0),
    'next_expiry', min(expires_at) filter (where sessions_left > 0),
    'weekly_limit', member_weekly_limit(p_member),
    'used_this_week', member_week_count(p_member, week_start(cairo_now()::date)),
    'lots', coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'source', source, 'sessions_left', sessions_left,
        'sessions_total', sessions_total, 'expires_at', expires_at,
        'weekly_limit', weekly_limit, 'is_drop_in', is_drop_in)
        order by expires_at nulls last) filter (where sessions_left > 0), '[]'::jsonb))
  into r from valid_lots(p_member);
  return r;
end $$;

-- Spots taken / waiting per class (counts only, no names) for the booking page
create or replace function session_counts(p_from date, p_to date)
returns table(session_id uuid, booked int, waiting int)
language sql stable security definer set search_path = public as $$
  select s.id,
    (select count(*)::int from bookings b where b.session_id = s.id
       and b.status in ('booked','attended','no_show','late_cancel')),
    (select count(*)::int from waitlist w where w.session_id = s.id)
  from sessions s where s.session_date between p_from and p_to
$$;

-- ---------------------------------------------------------------------
-- Booking (internal, no permission check)
-- ---------------------------------------------------------------------
create or replace function _book(p_member uuid, p_session uuid, p_actor uuid, p_from_waitlist boolean)
returns text language plpgsql security definer set search_path = public as $$
declare
  m members; s sessions; c classes; v_lot lots; v_limit int; v_count int; v_taken int;
begin
  select * into m from members where id = p_member for update;
  if not found or not m.active then raise exception 'Member is not active'; end if;
  select * into s from sessions where id = p_session for update;
  if not found or s.status <> 'scheduled' then raise exception 'This class is not available'; end if;
  select * into c from classes where id = s.class_id;
  if c.locked or not c.active then raise exception 'This class is locked'; end if;
  if (m.kind = 'adult' and c.audience <> 'adults') or (m.kind = 'child' and c.audience <> 'kids') then
    raise exception 'This class is not for this member';
  end if;
  -- Bookable from Friday midnight (start of the week) until the class ends
  if week_start(s.session_date) <> week_start(cairo_now()::date) or now() >= s.ends_at then
    raise exception 'Booking is not open for this class';
  end if;
  if exists(select 1 from bookings where session_id = s.id and member_id = m.id
            and status in ('booked','attended','no_show','late_cancel')) then
    raise exception 'Already booked';
  end if;
  -- Only one class per day
  if exists(select 1 from bookings b join sessions s2 on s2.id = b.session_id
            where b.member_id = m.id and s2.session_date = s.session_date
              and b.status in ('booked','attended','no_show','late_cancel')) then
    raise exception 'Only one class per day';
  end if;
  -- Weekly limit
  v_limit := member_weekly_limit(m.id);
  v_count := member_week_count(m.id, week_start(s.session_date));
  if v_limit is not null and v_count >= v_limit then
    raise exception 'Weekly limit reached (% per week)', v_limit;
  end if;
  -- Capacity
  if s.capacity is not null then
    select count(*) into v_taken from bookings where session_id = s.id
      and status in ('booked','attended','no_show','late_cancel');
    if v_taken >= s.capacity then
      if p_from_waitlist then raise exception 'Class is full'; end if;
      return 'full';
    end if;
  end if;
  -- Use the session that expires first (leftovers first)
  select * into v_lot from lots
   where member_id = m.id and sessions_left > 0 and (expires_at is null or expires_at > now())
   order by expires_at nulls last, created_at limit 1 for update;
  if not found then raise exception 'No sessions left. Please recharge'; end if;
  update lots set sessions_left = sessions_left - 1,
                  depleted_at = case when sessions_left - 1 = 0 then now() end
   where id = v_lot.id;
  insert into bookings(session_id, member_id, lot_id, booked_by, from_waitlist)
  values (s.id, m.id, v_lot.id, p_actor, p_from_waitlist);
  delete from waitlist where session_id = s.id and member_id = m.id;
  return 'booked';
end $$;

-- Public: book, or join the waiting list if full
create or replace function book_session(p_member uuid, p_session uuid) returns text
language plpgsql security definer set search_path = public as $$
declare r text;
begin
  if not can_manage_member(p_member) then raise exception 'Not allowed'; end if;
  if (select bookings_locked from settings) and not is_staff() then
    raise exception 'Bookings are temporarily closed';
  end if;
  perform run_due_jobs();
  r := _book(p_member, p_session, auth.uid(), false);
  if r = 'full' then
    insert into waitlist(session_id, member_id, added_by) values (p_session, p_member, auth.uid())
    on conflict do nothing;
    return 'waitlisted';
  end if;
  return r;
end $$;

create or replace function leave_waitlist(p_member uuid, p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not can_manage_member(p_member) then raise exception 'Not allowed'; end if;
  delete from waitlist where member_id = p_member and session_id = p_session;
end $$;

-- Give a used session back to the balance
create or replace function _refund(p_booking uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b bookings; l lots;
begin
  select * into b from bookings where id = p_booking;
  if b.lot_id is null then return; end if;
  select * into l from lots where id = b.lot_id for update;
  if l.expires_at is null or l.expires_at > now() then
    update lots set sessions_left = sessions_left + 1, depleted_at = null where id = l.id;
  else
    -- Package already expired: returned session must be used within 7 days of the expiry date
    insert into lots(member_id, payment_id, source, sessions_total, sessions_left,
                     weekly_limit, is_drop_in, expires_at, reminder_sent)
    values (l.member_id, l.payment_id, 'returned', 1, 1, l.weekly_limit, l.is_drop_in,
            l.expires_at + interval '7 days', true);
  end if;
end $$;

-- Fill free spots from the waiting list (auto-book + notify)
create or replace function _promote_waitlist(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare w record; s sessions; c classes;
begin
  select * into s from sessions where id = p_session;
  select * into c from classes where id = s.class_id;
  for w in select * from waitlist where session_id = p_session order by created_at loop
    begin
      if _book(w.member_id, p_session, null, true) = 'booked' then
        perform notify_member(w.member_id, 'waitlist_booked',
          'You got a spot: ' || c.name,
          'A spot opened in ' || c.name || ' on ' ||
          to_char(s.starts_at at time zone 'Africa/Cairo','Dy DD Mon HH24:MI') ||
          '. You are booked and one session was used. You can cancel up to 3 hours before.');
      end if;
    exception when others then
      if sqlerrm = 'Class is full' then exit; end if;
      delete from waitlist where id = w.id;   -- cannot take the spot: skip
    end;
  end loop;
end $$;

-- Client/parent cancels. Later than 3 hours before = counted.
create or replace function cancel_booking(p_booking uuid) returns text
language plpgsql security definer set search_path = public as $$
declare b bookings; s sessions; r text;
begin
  select * into b from bookings where id = p_booking for update;
  if not found or not can_manage_member(b.member_id) then raise exception 'Not allowed'; end if;
  if b.status <> 'booked' then raise exception 'This booking cannot be cancelled'; end if;
  select * into s from sessions where id = b.session_id;
  if now() >= s.starts_at then raise exception 'The class has already started'; end if;
  if now() <= s.starts_at - interval '3 hours' then
    update bookings set status = 'cancelled', cancelled_at = now() where id = b.id;
    perform _refund(b.id);
    r := 'cancelled';
  else
    update bookings set status = 'late_cancel', cancelled_at = now() where id = b.id;
    r := 'late_cancel';
  end if;
  perform _promote_waitlist(s.id);
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Payments
-- ---------------------------------------------------------------------
create or replace function _activate_payment(p_payment uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p payments; k packages;
begin
  select * into p from payments where id = p_payment;
  select * into k from packages where code = p.package_code;
  if not k.is_drop_in then
    -- Early recharge: leftovers can be used for 7 days from today, then they are removed
    update lots set expires_at = now() + interval '7 days', reminder_sent = true
     where member_id = p.member_id and sessions_left > 0
       and (expires_at is null or expires_at > now());
  end if;
  insert into lots(member_id, payment_id, source, sessions_total, sessions_left,
                   weekly_limit, is_drop_in, expires_at)
  values (p.member_id, p.id, case when k.is_drop_in then 'dropin' else 'package' end,
          k.sessions, k.sessions, k.weekly_limit, k.is_drop_in,
          case when k.validity_days is null then null else now() + make_interval(days => k.validity_days) end);
end $$;

create or replace function purchase(p_member uuid, p_package text, p_method payment_method)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m members; k packages; v_id uuid; v_limit int; st settings;
begin
  if not can_manage_member(p_member) then raise exception 'Not allowed'; end if;
  select * into st from settings;
  if st.payments_locked then raise exception 'Payments are temporarily closed'; end if;
  select * into m from members where id = p_member;
  select * into k from packages where code = p_package and active;
  if not found then raise exception 'Unknown package'; end if;
  if (m.kind = 'adult' and k.audience <> 'adults') or (m.kind = 'child' and k.audience <> 'kids') then
    raise exception 'This package is not for this member';
  end if;
  if k.is_drop_in then
    v_limit := member_weekly_limit(p_member);
    if v_limit is not null and member_week_count(p_member, week_start(cairo_now()::date)) >= v_limit then
      raise exception 'Weekly limit reached — a drop-in cannot be used to go over it';
    end if;
  end if;
  if p_method = 'online' and not st.online_test_mode then
    raise exception 'Online payment is not available yet';
  end if;
  if exists(select 1 from payments where member_id = p_member and status = 'pending') then
    raise exception 'There is already a payment waiting for approval';
  end if;
  insert into payments(member_id, package_code, amount_egp, method, status, test_mode, created_by)
  values (p_member, k.code, k.price_egp, p_method,
          (case when p_method = 'online' then 'paid' else 'pending' end)::payment_status,
          p_method = 'online', auth.uid())
  returning id into v_id;
  if p_method = 'online' then perform _activate_payment(v_id); end if;
  return jsonb_build_object('payment_id', v_id,
    'status', case when p_method = 'online' then 'paid' else 'pending' end,
    'invoice_no', (select invoice_no from payments where id = v_id));
end $$;

-- Coach/owner approves or rejects a cash payment
create or replace function decide_payment(p_payment uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare p payments; k packages;
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  select * into p from payments where id = p_payment for update;
  if not found then raise exception 'Payment not found'; end if;
  if p.status <> 'pending' then raise exception 'Already decided'; end if;
  select * into k from packages where code = p.package_code;
  update payments set status = case when p_approve then 'paid'::payment_status else 'rejected' end,
         decided_by = auth.uid(), decided_at = now(), note = p_note
   where id = p.id;
  if p_approve then
    perform _activate_payment(p.id);
    perform notify_member(p.member_id, 'payment_approved', 'Payment approved',
      'Your cash payment for ' || k.name_en || ' (' || k.price_egp || ' EGP) was approved. You can book now.');
  else
    perform notify_member(p.member_id, 'payment_rejected', 'Payment not approved',
      'Your cash payment for ' || k.name_en || ' was not approved.' ||
      coalesce(' Reason: ' || p_note, ''));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Family
-- ---------------------------------------------------------------------
create or replace function add_child(p_full_name text, p_dob date, p_emergency text,
  p_medical text, p_experience text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if my_role() <> 'parent' then raise exception 'Only parent accounts can add children'; end if;
  if p_dob is null or p_dob <= (cairo_now()::date - interval '13 years') then
    raise exception 'Children must be under 13. From 13, they need their own client account';
  end if;
  insert into members(account_id, kind, full_name, date_of_birth, emergency_contact, medical_notes, experience)
  values (auth.uid(), 'child', p_full_name, p_dob, p_emergency, p_medical, p_experience)
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Coach / owner: classes and sessions
-- ---------------------------------------------------------------------
create or replace function save_class(p_id uuid, p_name text, p_audience audience, p_weekday int,
  p_start time, p_duration int, p_capacity int, p_coach uuid, p_location text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid := p_id; s record;
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  if v_id is null then
    insert into classes(name, audience, weekday, start_time, duration_min, capacity, coach_id, location)
    values (p_name, p_audience, p_weekday, p_start, p_duration, p_capacity, p_coach, p_location)
    returning id into v_id;
  else
    update classes set name = p_name, audience = p_audience, weekday = p_weekday, start_time = p_start,
           duration_min = p_duration, capacity = p_capacity, coach_id = p_coach, location = p_location
     where id = v_id;
    -- Move future sessions that have not started to the new day/time
    for s in select * from sessions where class_id = v_id and status = 'scheduled' and starts_at > now() loop
      declare d date := week_start(s.session_date) + ((p_weekday - 6 + 7) % 7);
      begin
        if d <> s.session_date and exists(select 1 from sessions where class_id = v_id and session_date = d) then
          continue;
        end if;
        update sessions set session_date = d,
               starts_at = (d + p_start) at time zone 'Africa/Cairo',
               ends_at = (d + p_start + make_interval(mins => p_duration)) at time zone 'Africa/Cairo',
               capacity = p_capacity
         where id = s.id;
        if (d + p_start) <> (s.session_date + (s.starts_at at time zone 'Africa/Cairo')::time) then
          perform notify_member(b.member_id, 'class_changed', 'Class time changed: ' || p_name,
            'New time: ' || to_char(d + p_start, 'Dy DD Mon HH24:MI'))
          from bookings b where b.session_id = s.id and b.status = 'booked';
        end if;
      end;
    end loop;
  end if;
  perform ensure_sessions();
  return v_id;
end $$;

create or replace function set_class_locked(p_id uuid, p_locked boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  update classes set locked = p_locked where id = p_id;
end $$;

-- Coach cancels one class: bookings removed, sessions go back, people notified
create or replace function cancel_session(p_session uuid, p_reason text) returns int
language plpgsql security definer set search_path = public as $$
declare s sessions; c classes; b record; n int := 0;
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  select * into s from sessions where id = p_session for update;
  if s.status = 'cancelled' then return 0; end if;
  select * into c from classes where id = s.class_id;
  update sessions set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
         cancel_reason = p_reason where id = s.id;
  for b in select * from bookings where session_id = s.id
           and status in ('booked','attended','no_show','late_cancel') loop
    update bookings set status = 'cancelled_by_coach', cancelled_at = now() where id = b.id;
    perform _refund(b.id);
    perform notify_member(b.member_id, 'class_cancelled', 'Class cancelled: ' || c.name,
      to_char(s.starts_at at time zone 'Africa/Cairo','Dy DD Mon HH24:MI') ||
      ' was cancelled by the coach. Your session is back on your balance.' ||
      coalesce(' Reason: ' || nullif(p_reason,''), ''));
    n := n + 1;
  end loop;
  for b in select * from waitlist where session_id = s.id loop
    perform notify_member(b.member_id, 'class_cancelled', 'Class cancelled: ' || c.name,
      to_char(s.starts_at at time zone 'Africa/Cairo','Dy DD Mon HH24:MI') || ' was cancelled by the coach.');
  end loop;
  delete from waitlist where session_id = s.id;
  return n;
end $$;

create or replace function remove_class(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  for s in select id from sessions where class_id = p_id and status = 'scheduled' and starts_at > now() loop
    perform cancel_session(s.id, 'Class removed from the schedule');
  end loop;
  update classes set active = false where id = p_id;
end $$;

create or replace function update_session(p_session uuid, p_start timestamptz, p_duration int, p_capacity int)
returns void language plpgsql security definer set search_path = public as $$
declare s sessions; c classes;
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  select * into s from sessions where id = p_session;
  select * into c from classes where id = s.class_id;
  update sessions set starts_at = p_start, ends_at = p_start + make_interval(mins => p_duration),
         session_date = (p_start at time zone 'Africa/Cairo')::date, capacity = p_capacity
   where id = p_session;
  if p_start <> s.starts_at then
    perform notify_member(b.member_id, 'class_changed', 'Class time changed: ' || c.name,
      'New time: ' || to_char(p_start at time zone 'Africa/Cairo','Dy DD Mon HH24:MI'))
    from bookings b where b.session_id = p_session and b.status = 'booked';
  end if;
  perform _promote_waitlist(p_session);
end $$;

create or replace function set_attendance(p_booking uuid, p_attended boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  update bookings set status = case when p_attended then 'attended'::booking_status else 'no_show' end
   where id = p_booking and status in ('booked','attended','no_show');
end $$;

-- ---------------------------------------------------------------------
-- Notifications from staff
-- ---------------------------------------------------------------------
create or replace function send_announcement(p_title text, p_body text) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  insert into notifications(account_id, kind, title, body)
  select id, 'announcement', p_title, coalesce(p_body,'') from profiles
   where role in ('client','parent') and active;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function expiring_soon() returns table(member_id uuid, member_name text,
  account_name text, kind member_kind, sessions_left int, expires_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  return query
    select m.id, m.full_name, p.full_name, m.kind, sum(l.sessions_left)::int, min(l.expires_at)
      from lots l join members m on m.id = l.member_id join profiles p on p.id = m.account_id
     where l.expires_at > now() and l.expires_at <= now() + interval '4 days' and l.sessions_left > 0
     group by m.id, m.full_name, p.full_name, m.kind
     order by min(l.expires_at);
end $$;

create or replace function notify_expiring(p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_exp timestamptz; v_left int;
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  select min(expires_at), sum(sessions_left) into v_exp, v_left from valid_lots(p_member) where sessions_left > 0;
  perform notify_member(p_member, 'expiring', 'Your sessions are expiring soon',
    v_left || ' session(s) left, expiring on ' ||
    to_char(v_exp at time zone 'Africa/Cairo', 'Dy DD Mon') || '. Book your classes or recharge.');
end $$;

-- ---------------------------------------------------------------------
-- Daily jobs (safe to run often; also called when people book)
-- ---------------------------------------------------------------------
create or replace function run_due_jobs() returns void
language plpgsql security definer set search_path = public as $$
declare l record;
begin
  perform ensure_sessions();
  -- Expiry reminder 7 days before
  for l in select * from lots where not reminder_sent and sessions_left > 0
            and expires_at is not null and expires_at > now()
            and expires_at <= now() + interval '7 days' loop
    perform notify_member(l.member_id, 'expiry_reminder', 'Your package expires soon',
      l.sessions_left || ' session(s) left, expiring on ' ||
      to_char(l.expires_at at time zone 'Africa/Cairo', 'Dy DD Mon') || '.');
    update lots set reminder_sent = true where id = l.id;
  end loop;
  -- Expired: balance resets to 0
  update lots set expired_sessions = expired_sessions + sessions_left, sessions_left = 0
   where sessions_left > 0 and expires_at is not null and expires_at <= now();
end $$;

-- ---------------------------------------------------------------------
-- Owner tools
-- ---------------------------------------------------------------------
create or replace function set_role(p_user uuid, p_role app_role) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  update profiles set role = p_role where id = p_user;
end $$;

create or replace function set_account_active(p_user uuid, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  update profiles set active = p_active where id = p_user;
  update members set active = p_active where account_id = p_user;
end $$;

create or replace function set_member_active(p_member uuid, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  update members set active = p_active where id = p_member;
end $$;

create or replace function delete_member(p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  delete from members where id = p_member;
end $$;

-- Owner adds/removes sessions or changes expiry by hand
create or replace function adjust_balance(p_member uuid, p_sessions int, p_expires_at timestamptz,
  p_weekly_limit int, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare l lots; v_rest int := -p_sessions;
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  if p_sessions > 0 then
    insert into lots(member_id, source, sessions_total, sessions_left, weekly_limit, expires_at)
    values (p_member, 'manual', p_sessions, p_sessions, p_weekly_limit, p_expires_at);
  elsif p_sessions < 0 then
    for l in select * from valid_lots(p_member) where sessions_left > 0 order by expires_at nulls last loop
      exit when v_rest <= 0;
      update lots set sessions_left = sessions_left - least(v_rest, l.sessions_left) where id = l.id;
      v_rest := v_rest - least(v_rest, l.sessions_left);
    end loop;
  elsif p_expires_at is not null then
    update lots set expires_at = p_expires_at, reminder_sent = false
     where member_id = p_member and sessions_left > 0;
  end if;
end $$;

create or replace function save_settings(p_bookings_locked boolean, p_payments_locked boolean,
  p_online_test_mode boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  update settings set bookings_locked = p_bookings_locked, payments_locked = p_payments_locked,
         online_test_mode = p_online_test_mode, updated_at = now();
end $$;

create or replace function save_package_price(p_code text, p_price numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  update packages set price_egp = p_price where code = p_code;
end $$;

-- ---------------------------------------------------------------------
-- Owner dashboard
-- ---------------------------------------------------------------------
create or replace function owner_stats(p_month date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m0 date := date_trunc('month', coalesce(p_month, cairo_now()::date))::date;
  m1 date := (m0 + interval '1 month')::date;
  pm date := (m0 - interval '1 month')::date;
  r jsonb;
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  with paid as (
    select p.*, k.audience, k.is_drop_in,
           date_trunc('month', coalesce(p.decided_at, p.created_at) at time zone 'Africa/Cairo')::date as mon
      from payments p join packages k on k.code = p.package_code
     where p.status = 'paid' and not p.test_mode
  ),
  sess as (select * from sessions where session_date >= m0 and session_date < m1),
  bk as (select b.* from bookings b join sess s on s.id = b.session_id),
  ended as (
    select l.*, least(coalesce(l.depleted_at, 'infinity'), coalesce(l.expires_at, 'infinity')) as ended_at
      from lots l where l.source = 'package'
  ),
  ended_m as (
    select * from ended where ended_at >= (m0::timestamp at time zone 'Africa/Cairo')
                         and ended_at <  (m1::timestamp at time zone 'Africa/Cairo')
                         and ended_at <= now()
  )
  select jsonb_build_object(
    'month', m0,
    'revenue', (select coalesce(sum(amount_egp),0) from paid where mon = m0),
    'revenue_adults', (select coalesce(sum(amount_egp),0) from paid where mon = m0 and audience = 'adults'),
    'revenue_kids', (select coalesce(sum(amount_egp),0) from paid where mon = m0 and audience = 'kids'),
    'revenue_prev', (select coalesce(sum(amount_egp),0) from paid where mon = pm),
    'revenue_prev_adults', (select coalesce(sum(amount_egp),0) from paid where mon = pm and audience = 'adults'),
    'revenue_prev_kids', (select coalesce(sum(amount_egp),0) from paid where mon = pm and audience = 'kids'),
    'revenue_by_month', (select coalesce(jsonb_agg(x order by x->>'month'), '[]'::jsonb) from (
        select jsonb_build_object('month', mon,
          'adults', coalesce(sum(amount_egp) filter (where audience='adults'),0),
          'kids',   coalesce(sum(amount_egp) filter (where audience='kids'),0)) x
          from paid where mon > (m0 - interval '12 months') and mon <= m0 group by mon) t),
    'pending_count', (select count(*) from payments where status = 'pending'),
    'pending_amount', (select coalesce(sum(amount_egp),0) from payments where status = 'pending'),
    'bookings_month', (select count(*) from bk where status in ('booked','attended','no_show','late_cancel')),
    'bookings_total', (select count(*) from bookings where status in ('booked','attended','no_show','late_cancel')),
    'active_packages', (select count(*) from lots where source = 'package' and sessions_left > 0
                          and (expires_at is null or expires_at > now())),
    'active_adults', (select count(distinct l.member_id) from lots l join members m on m.id = l.member_id
                       where m.kind = 'adult' and l.sessions_left > 0 and (l.expires_at is null or l.expires_at > now())),
    'active_kids', (select count(distinct l.member_id) from lots l join members m on m.id = l.member_id
                       where m.kind = 'child' and l.sessions_left > 0 and (l.expires_at is null or l.expires_at > now())),
    'retention_base', (select count(*) from ended_m),
    'retention_kept', (select count(*) from ended_m e where exists(
        select 1 from payments p join packages k on k.code = p.package_code
         where p.member_id = e.member_id and p.status = 'paid' and not k.is_drop_in
           and p.id is distinct from e.payment_id
           and p.created_at > e.created_at and p.created_at <= e.ended_at + interval '14 days')),
    'attended', (select count(*) from bk where status = 'attended'),
    'no_show', (select count(*) from bk where status = 'no_show'),
    'popular_classes', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('name', c.name, 'audience', c.audience, 'bookings', count(*)) x
          from bk b join sess s on s.id = b.session_id join classes c on c.id = s.class_id
         where b.status in ('booked','attended','no_show','late_cancel')
         group by c.id, c.name, c.audience order by count(*) desc limit 5) t),
    'cancelled_by_coach', (select coalesce(jsonb_agg(x order by x->>'starts_at'), '[]'::jsonb) from (
        select jsonb_build_object('name', c.name, 'starts_at', s.starts_at, 'reason', s.cancel_reason,
                                  'cancelled_at', s.cancelled_at) x
          from sess s join classes c on c.id = s.class_id where s.status = 'cancelled') t)
  ) into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Row level security: people see their own data, staff see everything.
-- All changes go through the functions above.
-- ---------------------------------------------------------------------
alter table settings      enable row level security;
alter table packages      enable row level security;
alter table profiles      enable row level security;
alter table members       enable row level security;
alter table payments      enable row level security;
alter table lots          enable row level security;
alter table classes       enable row level security;
alter table sessions      enable row level security;
alter table bookings      enable row level security;
alter table waitlist      enable row level security;
alter table notifications enable row level security;

create policy read_settings on settings for select to authenticated using (true);
create policy read_packages on packages for select to anon, authenticated using (true);
create policy read_profiles on profiles for select to authenticated using (id = auth.uid() or is_staff());
create policy upd_profiles  on profiles for update to authenticated using (id = auth.uid() or is_owner());
create policy read_members  on members  for select to authenticated using (account_id = auth.uid() or is_staff());
create policy upd_members   on members  for update to authenticated using (account_id = auth.uid() or is_staff());
create policy read_payments on payments for select to authenticated using (owns_member(member_id) or is_staff());
create policy read_lots     on lots     for select to authenticated using (owns_member(member_id) or is_staff());
create policy read_classes  on classes  for select to authenticated using (true);
create policy read_sessions on sessions for select to authenticated using (true);
create policy read_bookings on bookings for select to authenticated using (owns_member(member_id) or is_staff());
create policy read_waitlist on waitlist for select to authenticated using (owns_member(member_id) or is_staff());
create policy read_notif    on notifications for select to authenticated using (account_id = auth.uid());
create policy upd_notif     on notifications for update to authenticated using (account_id = auth.uid());

-- Column-level write permissions (role, ids, balances can never be edited directly)
revoke insert, update, delete on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;
grant select on packages to anon;
grant update (full_name, phone, locale) on profiles to authenticated;
grant update (full_name, date_of_birth, phone, emergency_contact, medical_notes, experience) on members to authenticated;
grant update (read_at) on notifications to authenticated;

-- Internal functions are not callable from the website
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;
revoke execute on function _book(uuid,uuid,uuid,boolean), _refund(uuid), _promote_waitlist(uuid),
  _activate_payment(uuid), notify(uuid,uuid,text,text,text), notify_member(uuid,text,text,text),
  handle_new_user() from authenticated;
