-- =====================================================================
-- Update 002 — run once in Supabase SQL Editor (after schema.sql).
-- Safe: keeps all existing data. Safe to run again.
--  1. Clients/parents can book up to 12 hours after a class ends
--  2. Announcements to parents, clients or everyone
--  3. Private messages between coaches and accounts
-- (Cash/InstaPay: the 30 days already start when the coach approves.)
-- =====================================================================

-- 1. Booking window ----------------------------------------------------
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

-- 2. Announcements by audience -----------------------------------------
drop function if exists send_announcement(text, text);
create or replace function send_announcement(p_title text, p_body text, p_audience text default 'all')
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  insert into notifications(account_id, kind, title, body)
  select id, 'announcement', p_title, coalesce(p_body,'') from profiles
   where active and role in ('client','parent')
     and (p_audience = 'all' or (p_audience = 'clients' and role = 'client')
          or (p_audience = 'parents' and role = 'parent'));
  get diagnostics n = row_count;
  return n;
end $$;

-- 3. Private messages ---------------------------------------------------
-- One conversation per client/parent account; every coach and the owner can see and reply.
create table if not exists messages (
  id                uuid primary key default gen_random_uuid(),
  account_id        uuid not null references profiles(id) on delete cascade,  -- the client/parent
  sender_id         uuid not null references profiles(id) on delete cascade,
  from_staff        boolean not null,
  body              text not null check (length(body) between 1 and 2000),
  read_by_account   timestamptz,
  read_by_staff     timestamptz,
  created_at        timestamptz not null default now()
);
create index if not exists messages_account_idx on messages(account_id, created_at);
alter table messages enable row level security;
drop policy if exists read_messages on messages;
create policy read_messages on messages for select to authenticated
  using (account_id = auth.uid() or is_staff());
revoke insert, update, delete on messages from anon, authenticated;
grant select on messages to authenticated;

create or replace function send_message(p_account uuid, p_body text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_staff boolean := is_staff(); v_role app_role;
begin
  if p_body is null or length(trim(p_body)) = 0 then raise exception 'Message is empty'; end if;
  select role into v_role from profiles where id = p_account;
  if v_role not in ('client','parent') then raise exception 'Not allowed'; end if;
  if not v_staff and p_account <> auth.uid() then raise exception 'Not allowed'; end if;
  insert into messages(account_id, sender_id, from_staff, body, read_by_account, read_by_staff)
  values (p_account, auth.uid(), v_staff, trim(p_body),
          case when v_staff then null else now() end,
          case when v_staff then now() else null end)
  returning id into v_id;
  if v_staff then
    perform notify(p_account, null, 'message', 'New message from KFK', left(trim(p_body), 140));
  end if;
  return v_id;
end $$;

create or replace function mark_messages_read(p_account uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if is_staff() then
    update messages set read_by_staff = now() where account_id = p_account and read_by_staff is null;
  elsif p_account = auth.uid() then
    update messages set read_by_account = now() where account_id = p_account and read_by_account is null;
  else
    raise exception 'Not allowed';
  end if;
end $$;

-- Staff inbox: one row per conversation
create or replace function message_threads() returns table(account_id uuid, full_name text, role app_role,
  email text, last_body text, last_at timestamptz, last_from_staff boolean, unread int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_staff() then raise exception 'Not allowed'; end if;
  return query
    select p.id, p.full_name, p.role, p.email,
      (select m.body from messages m where m.account_id = p.id order by m.created_at desc limit 1),
      (select max(m.created_at) from messages m where m.account_id = p.id),
      (select m.from_staff from messages m where m.account_id = p.id order by m.created_at desc limit 1),
      (select count(*)::int from messages m where m.account_id = p.id and m.read_by_staff is null)
    from profiles p
    where exists(select 1 from messages m where m.account_id = p.id)
    order by 6 desc;
end $$;

revoke execute on function send_message(uuid,text), mark_messages_read(uuid), message_threads(),
  send_announcement(text,text,text) from public, anon;
grant execute on function send_message(uuid,text), mark_messages_read(uuid), message_threads(),
  send_announcement(text,text,text) to authenticated;
