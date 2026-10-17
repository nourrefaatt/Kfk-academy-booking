-- =====================================================================
-- Update 005 — adult 8-session package + private groups.
-- Run once in Supabase SQL Editor (after updates 002–004). Keeps all data. Safe to run again.
--  * Adults: 8 sessions, 2,800 EGP, 4 per week, 30 days.
--  * Private groups (adults and kids, separate): fixed members chosen by the coach, a maximum
--    size set by the coach (at least 3). Private sessions use a separate private balance:
--    8 sessions 4,500 EGP, 12 sessions 5,500 EGP (30 days, no weekly limit), drop-in 600 EGP.
--  * If at least one member books a private session, every member of that group who did not
--    book is also charged one private session (charged when booking closes, 12 h after the end).
-- =====================================================================

alter type booking_status add value if not exists 'group_charge';

alter table packages add column if not exists is_private boolean not null default false;
alter table lots     add column if not exists is_private boolean not null default false;
alter table classes  add column if not exists is_private boolean not null default false;
alter table sessions add column if not exists group_charged boolean not null default false;

-- Packages (prices from the owner). Drop-in expiry still undecided, so drop-ins do not expire.
insert into packages(code, audience, name_en, name_ar, sessions, price_egp, weekly_limit, validity_days,
                     is_drop_in, active, sort, is_private) values
 ('adult_8',          'adults', '8 sessions', '٨ حصص', 8, 2800, 4, 30, false, true, 1, false),
 ('adult_priv_8',     'adults', 'Private group · 8 sessions', 'مجموعة خاصة · ٨ حصص', 8, 4500, null, 30, false, true, 11, true),
 ('adult_priv_12',    'adults', 'Private group · 12 sessions', 'مجموعة خاصة · ١٢ حصة', 12, 5500, null, 30, false, true, 12, true),
 ('adult_priv_dropin','adults', 'Private group · Drop-in', 'مجموعة خاصة · حصة واحدة', 1, 600, null, null, true, true, 13, true),
 ('kids_priv_8',      'kids', 'Private group · 8 sessions', 'مجموعة خاصة · ٨ حصص', 8, 4500, null, 30, false, true, 11, true),
 ('kids_priv_12',     'kids', 'Private group · 12 sessions', 'مجموعة خاصة · ١٢ حصة', 12, 5500, null, 30, false, true, 12, true),
 ('kids_priv_dropin', 'kids', 'Private group · Drop-in', 'مجموعة خاصة · حصة واحدة', 1, 600, null, null, true, true, 13, true)
on conflict (code) do nothing;
update packages set sort = 2 where code = 'adult_12';
update packages set sort = 3 where code = 'adult_dropin';

-- Who belongs to each private group
create table if not exists class_members (
  class_id   uuid not null references classes(id) on delete cascade,
  member_id  uuid not null references members(id) on delete cascade,
  added_at   timestamptz not null default now(),
  primary key (class_id, member_id)
);
alter table class_members enable row level security;
drop policy if exists read_class_members on class_members;
create policy read_class_members on class_members for select to authenticated
  using (is_staff() or owns_member(member_id));
revoke insert, update, delete on class_members from anon, authenticated;
grant select on class_members to authenticated;

-- Regular weekly limit counts regular classes only (private groups have no weekly limit)
create or replace function member_week_count(p_member uuid, p_week date) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from bookings b join sessions s on s.id = b.session_id
    join classes c on c.id = s.class_id
  where b.member_id = p_member and not c.is_private
    and b.status in ('booked','attended','no_show','late_cancel')
    and week_start(s.session_date) = p_week
$$;
create or replace function member_weekly_limit(p_member uuid) returns int
language sql stable security definer set search_path = public as $$
  select max(weekly_limit) from valid_lots(p_member)
   where not is_drop_in and not is_private and weekly_limit is not null
$$;

create or replace function member_balance(p_member uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not can_manage_member(p_member) then raise exception 'Not allowed'; end if;
  select jsonb_build_object(
    'sessions_left', coalesce(sum(sessions_left) filter (where not is_private),0),
    'next_expiry', min(expires_at) filter (where sessions_left > 0 and not is_private),
    'private_left', coalesce(sum(sessions_left) filter (where is_private),0),
    'private_next_expiry', min(expires_at) filter (where sessions_left > 0 and is_private),
    'in_private_group', exists(select 1 from class_members cm join classes c on c.id = cm.class_id
                               where cm.member_id = p_member and c.active),
    'weekly_limit', member_weekly_limit(p_member),
    'used_this_week', member_week_count(p_member, week_start(cairo_now()::date)),
    'lots', coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'source', source, 'sessions_left', sessions_left,
        'sessions_total', sessions_total, 'expires_at', expires_at,
        'weekly_limit', weekly_limit, 'is_drop_in', is_drop_in, 'is_private', is_private)
        order by expires_at nulls last) filter (where sessions_left > 0), '[]'::jsonb))
  into r from valid_lots(p_member);
  return r;
end $$;

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
  -- Private groups: only the members the coach assigned can book
  if c.is_private and not exists(select 1 from class_members where class_id = c.id and member_id = m.id) then
    raise exception 'This private group is not yours';
  end if;
  -- Bookable from Friday midnight (start of its week) until 12 hours after the class ends
  -- (so someone who forgot to book can still add the class they attended)
  if week_start(s.session_date) > week_start(cairo_now()::date)
     or now() >= s.ends_at + interval '12 hours' then
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
  if not c.is_private and v_limit is not null and v_count >= v_limit then
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
     and is_private = c.is_private
   order by expires_at nulls last, created_at limit 1 for update;
  if not found then
    if c.is_private then raise exception 'No private group sessions left. Please recharge'; end if;
    raise exception 'No sessions left. Please recharge';
  end if;
  update lots set sessions_left = sessions_left - 1,
                  depleted_at = case when sessions_left - 1 = 0 then now() end
   where id = v_lot.id;
  insert into bookings(session_id, member_id, lot_id, booked_by, from_waitlist)
  values (s.id, m.id, v_lot.id, p_actor, p_from_waitlist);
  delete from waitlist where session_id = s.id and member_id = m.id;
  return 'booked';
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
  if k.is_drop_in and not k.is_private then
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
  if k.is_drop_in and not k.is_private then
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

create or replace function _activate_payment(p_payment uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p payments; k packages;
begin
  select * into p from payments where id = p_payment;
  select * into k from packages where code = p.package_code;
  if not k.is_drop_in then
    -- Early recharge: leftovers can be used for 7 days from today, then they are removed
    update lots set expires_at = now() + interval '7 days', reminder_sent = true
     where member_id = p.member_id and sessions_left > 0 and is_private = k.is_private
       and (expires_at is null or expires_at > now());
  end if;
  insert into lots(member_id, payment_id, source, sessions_total, sessions_left,
                   weekly_limit, is_drop_in, is_private, expires_at)
  values (p.member_id, p.id, case when k.is_drop_in then 'dropin' else 'package' end,
          k.sessions, k.sessions, k.weekly_limit, k.is_drop_in, k.is_private,
          case when k.validity_days is null then null else now() + make_interval(days => k.validity_days) end);
end $$;

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
                     weekly_limit, is_drop_in, is_private, expires_at, reminder_sent)
    values (l.member_id, l.payment_id, 'returned', 1, 1, l.weekly_limit, l.is_drop_in, l.is_private,
            l.expires_at + interval '7 days', true);
  end if;
end $$;

-- Charge the whole private group (see top of file)
create or replace function _charge_private_groups() returns void
language plpgsql security definer set search_path = public as $$
declare s record; m record; v_lot lots;
begin
  for s in select se.*, c.name as class_name from sessions se join classes c on c.id = se.class_id
            where c.is_private and se.status = 'scheduled' and not se.group_charged
              and se.ends_at + interval '12 hours' <= now()
            for update of se loop
    if exists(select 1 from bookings b where b.session_id = s.id
              and b.status::text in ('booked','attended','no_show','late_cancel')) then
      for m in select cm.member_id from class_members cm
                where cm.class_id = s.class_id
                  and not exists(select 1 from bookings b where b.session_id = s.id and b.member_id = cm.member_id
                                 and b.status::text in ('booked','attended','no_show','late_cancel','group_charge')) loop
        select * into v_lot from lots
         where member_id = m.member_id and is_private and sessions_left > 0
           and (expires_at is null or expires_at > now())
         order by expires_at nulls last, created_at limit 1 for update;
        if found then
          update lots set sessions_left = sessions_left - 1,
                          depleted_at = case when sessions_left - 1 = 0 then now() end where id = v_lot.id;
        end if;
        insert into bookings(session_id, member_id, lot_id, status, cancelled_at)
        values (s.id, m.member_id, v_lot.id, 'group_charge', now());
        perform notify_member(m.member_id, 'group_charge', 'Private group session counted: ' || s.class_name,
          to_char(s.starts_at at time zone 'Africa/Cairo', 'Dy DD Mon HH24:MI') ||
          ' took place with your group, so one private session was counted, as agreed for private groups.' ||
          case when v_lot.id is null then ' You had no private sessions left — please recharge.' else '' end);
        v_lot := null;
      end loop;
    end if;
    update sessions set group_charged = true where id = s.id;
  end loop;
end $$;

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
  -- Private groups: once booking closes (12 hours after the session ends), if at least one
  -- member booked, every group member who did not book is charged one private session.
  perform _charge_private_groups();
  -- Expired: balance resets to 0
  update lots set expired_sessions = expired_sessions + sessions_left, sessions_left = 0
   where sessions_left > 0 and expires_at is not null and expires_at <= now();
end $$;

-- Coach: create / edit a private group (max size at least 3)
create or replace function save_private_group(p_id uuid, p_name text, p_audience audience, p_weekday int,
  p_start time, p_duration int, p_max int, p_coach uuid, p_location text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  if p_max is null or p_max < 3 then raise exception 'A private group needs at least 3 places'; end if;
  if p_id is not null and (select count(*) from class_members where class_id = p_id) > p_max then
    raise exception 'The group already has more members than this size';
  end if;
  v_id := save_class(p_id, p_name, p_audience, p_weekday, p_start, p_duration, p_max, p_coach, p_location);
  update classes set is_private = true, capacity = p_max where id = v_id;
  update sessions set capacity = p_max where class_id = v_id and starts_at > now();
  return v_id;
end $$;

-- Coach: choose exactly who is in a private group
create or replace function set_group_members(p_class uuid, p_members uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare c classes; v_count int; m uuid;
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  select * into c from classes where id = p_class;
  if not found or not c.is_private then raise exception 'Not a private group'; end if;
  v_count := coalesce(array_length(p_members, 1), 0);
  if v_count > c.capacity then raise exception 'Too many members for this group (max %)', c.capacity; end if;
  if exists(select 1 from members where id = any(p_members)
            and ((c.audience = 'adults' and kind <> 'adult') or (c.audience = 'kids' and kind <> 'child'))) then
    raise exception 'Adults and kids cannot be in the same private group';
  end if;
  delete from class_members where class_id = p_class and not (member_id = any(coalesce(p_members, '{}')));
  foreach m in array coalesce(p_members, '{}') loop
    if not exists(select 1 from class_members where class_id = p_class and member_id = m) then
      insert into class_members(class_id, member_id) values (p_class, m);
      perform notify_member(m, 'group_added', 'You joined a private group: ' || c.name,
        'Every ' || to_char(date '2026-01-04' + c.weekday, 'FMDay') || ' at ' || to_char(c.start_time, 'HH24:MI') ||
        '. Book it from Book a class using your private group balance.');
    end if;
  end loop;
end $$;

-- Owner: add/remove regular or private sessions by hand
create or replace function adjust_balance_kind(p_member uuid, p_sessions int, p_expires_at timestamptz,
  p_weekly_limit int, p_note text, p_private boolean) returns void
language plpgsql security definer set search_path = public as $$
declare l lots; v_rest int := -p_sessions;
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  if p_sessions > 0 then
    insert into lots(member_id, source, sessions_total, sessions_left, weekly_limit, expires_at, is_private)
    values (p_member, 'manual', p_sessions, p_sessions, case when p_private then null else p_weekly_limit end,
            p_expires_at, coalesce(p_private, false));
  elsif p_sessions < 0 then
    for l in select * from valid_lots(p_member) where sessions_left > 0 and is_private = coalesce(p_private, false)
             order by expires_at nulls last loop
      exit when v_rest <= 0;
      update lots set sessions_left = sessions_left - least(v_rest, l.sessions_left) where id = l.id;
      v_rest := v_rest - least(v_rest, l.sessions_left);
    end loop;
  elsif p_expires_at is not null then
    update lots set expires_at = p_expires_at, reminder_sent = false
     where member_id = p_member and sessions_left > 0 and is_private = coalesce(p_private, false);
  end if;
end $$;

revoke execute on function _charge_private_groups() from public, anon, authenticated;
revoke execute on function save_private_group(uuid,text,audience,int,time,int,int,uuid,text),
  set_group_members(uuid,uuid[]), adjust_balance_kind(uuid,int,timestamptz,int,text,boolean) from public, anon;
grant execute on function save_private_group(uuid,text,audience,int,time,int,int,uuid,text),
  set_group_members(uuid,uuid[]), adjust_balance_kind(uuid,int,timestamptz,int,text,boolean) to authenticated;
