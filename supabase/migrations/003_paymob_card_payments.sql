-- =====================================================================
-- Update 003 — Paymob card payments. Run once in Supabase SQL Editor
-- (after update 002). Keeps all existing data. Safe to run again.
-- How it works:
--  1. The website asks our server (Vercel) to start a card payment.
--  2. The server calls start_online_payment() as the logged-in person: all the
--     usual rules are checked and a 'pending' online payment is created.
--  3. The person pays on Paymob's page.
--  4. Paymob tells our server the result (signed with the HMAC secret). Only then
--     the server calls confirm_online_payment() with the private service key, and
--     the sessions are added (30 days start at that moment).
-- =====================================================================

alter table payments add column if not exists provider          text;
alter table payments add column if not exists provider_order_id text;
alter table payments add column if not exists provider_txn_id   text;
create index if not exists payments_provider_order_idx on payments(provider_order_id);

-- Simulated online payments (the old test button) stay available only while the owner
-- leaves "online test mode" on in Settings. Turn it off to use Paymob.

-- Card checkout leftovers never block, and staff cannot approve card payments by hand
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
  -- Unfinished card checkouts never block a new payment
  update payments set status = 'rejected', note = 'Card checkout not completed', decided_at = now()
   where member_id = p_member and status = 'pending' and method = 'online';
  if exists(select 1 from payments where member_id = p_member and status = 'pending' and method = 'cash') then
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

create or replace function decide_payment(p_payment uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare p payments; k packages;
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  select * into p from payments where id = p_payment for update;
  if not found then raise exception 'Payment not found'; end if;
  if p.status <> 'pending' then raise exception 'Already decided'; end if;
  if p.method <> 'cash' then raise exception 'Card payments are confirmed by Paymob, not by hand'; end if;
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

-- Start a card payment (called by our server with the person's own login)
create or replace function start_online_payment(p_member uuid, p_package text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m members; k packages; acc profiles; v_id uuid; v_limit int; st settings;
begin
  if not can_manage_member(p_member) then raise exception 'Not allowed'; end if;
  select * into st from settings;
  if st.payments_locked then raise exception 'Payments are temporarily closed'; end if;
  select * into m from members where id = p_member;
  if not m.active then raise exception 'Member is not active'; end if;
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
  if exists(select 1 from payments where member_id = p_member and status = 'pending' and method = 'cash') then
    raise exception 'There is already a payment waiting for approval';
  end if;
  update payments set status = 'rejected', note = 'Card checkout not completed', decided_at = now()
   where member_id = p_member and status = 'pending' and method = 'online';
  insert into payments(member_id, package_code, amount_egp, method, status, provider, created_by)
  values (p_member, k.code, k.price_egp, 'online', 'pending', 'paymob', auth.uid())
  returning id into v_id;
  select * into acc from profiles where id = m.account_id;
  return jsonb_build_object('payment_id', v_id,
    'invoice_no', (select invoice_no from payments where id = v_id),
    'amount_cents', (k.price_egp * 100)::bigint,
    'package_name', k.name_en, 'audience', k.audience, 'member_name', m.full_name,
    'payer_name', coalesce(nullif(acc.full_name,''), m.full_name),
    'payer_email', acc.email, 'payer_phone', coalesce(acc.phone, m.phone));
end $$;

-- Our server saves Paymob's order number on the payment (only for the payer's own pending payment)
create or replace function set_payment_provider_order(p_payment uuid, p_order text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update payments set provider_order_id = p_order
   where id = p_payment and status = 'pending' and method = 'online' and can_manage_member(member_id);
end $$;

-- Paymob confirmed the payment: only our server (service key) can call this
create or replace function confirm_online_payment(p_payment uuid, p_order text, p_txn text,
  p_amount_cents bigint, p_success boolean, p_test boolean)
returns text language plpgsql security definer set search_path = public as $$
declare p payments; k packages;
begin
  select * into p from payments
   where (p_payment is not null and id = p_payment) or (p_order is not null and provider_order_id = p_order)
   order by created_at desc limit 1 for update;
  if not found then return 'not_found'; end if;
  if p.status = 'paid' then return 'already_paid'; end if;
  if p.method <> 'online' then return 'not_online'; end if;
  if not p_success then
    update payments set status = 'rejected', note = 'Card payment failed', decided_at = now(),
           provider_txn_id = p_txn where id = p.id and status = 'pending';
    return 'failed';
  end if;
  if p_amount_cents <> (p.amount_egp * 100)::bigint then
    update payments set note = 'Amount mismatch from Paymob: ' || p_amount_cents, provider_txn_id = p_txn
     where id = p.id;
    return 'amount_mismatch';
  end if;
  select * into k from packages where code = p.package_code;
  update payments set status = 'paid', decided_at = now(), provider_txn_id = p_txn,
         provider_order_id = coalesce(provider_order_id, p_order), test_mode = coalesce(p_test, false),
         note = null
   where id = p.id;
  perform _activate_payment(p.id);
  perform notify_member(p.member_id, 'payment_paid', 'Payment received',
    'Your card payment for ' || k.name_en || ' (' || k.price_egp || ' EGP) was received. Invoice #' ||
    p.invoice_no || '. You can book now.');
  return 'paid';
end $$;

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
    'pending_count', (select count(*) from payments where status = 'pending' and method = 'cash'),
    'pending_amount', (select coalesce(sum(amount_egp),0) from payments where status = 'pending' and method = 'cash'),
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

revoke execute on function start_online_payment(uuid,text), set_payment_provider_order(uuid,text),
  confirm_online_payment(uuid,text,text,bigint,boolean,boolean) from public, anon;
grant execute on function start_online_payment(uuid,text), set_payment_provider_order(uuid,text) to authenticated;
revoke execute on function confirm_online_payment(uuid,text,text,bigint,boolean,boolean) from authenticated;
do $$ begin
  grant execute on function confirm_online_payment(uuid,text,text,bigint,boolean,boolean) to service_role;
exception when undefined_object then null; end $$;
