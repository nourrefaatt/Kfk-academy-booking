-- =====================================================================
-- Update 004 — fixes "UPDATE requires a WHERE clause" when the owner saves Settings.
-- Run once in Supabase SQL Editor. Keeps all data. Safe to run again.
-- =====================================================================

create or replace function save_settings(p_bookings_locked boolean, p_payments_locked boolean,
  p_online_test_mode boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  update settings set bookings_locked = p_bookings_locked, payments_locked = p_payments_locked,
         online_test_mode = p_online_test_mode, updated_at = now()
   where id = 1;
end $$;
