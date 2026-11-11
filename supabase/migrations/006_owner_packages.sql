-- 006: the owner can create, edit, hide and show packages from Settings.
-- Safe to run more than once. Keeps all data.
-- Changing a package only affects purchases made after the change: sessions people already
-- have keep their own count, weekly limit and expiry.

create or replace function save_package(
  p_code text,              -- null = create a new package
  p_audience audience,
  p_name_en text,
  p_name_ar text,
  p_sessions int,
  p_price numeric,
  p_weekly_limit int,       -- null = no weekly limit
  p_validity_days int,      -- null = never expires
  p_is_drop_in boolean,
  p_is_private boolean,
  p_active boolean
) returns text
language plpgsql security definer set search_path = public as $$
declare v_code text := nullif(trim(coalesce(p_code, '')), ''); v_sort int;
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  if nullif(trim(coalesce(p_name_en, '')), '') is null then raise exception 'Package name is required'; end if;
  if p_sessions is null or p_sessions < 1 then raise exception 'Sessions must be at least 1'; end if;
  if p_price is null or p_price < 0 then raise exception 'Price must be 0 or more'; end if;
  if p_weekly_limit is not null and p_weekly_limit < 1 then raise exception 'Weekly limit must be at least 1'; end if;
  if p_validity_days is not null and p_validity_days < 1 then raise exception 'Valid days must be at least 1'; end if;
  if coalesce(p_is_drop_in, false) and p_sessions <> 1 then raise exception 'A drop-in is exactly 1 session'; end if;

  if v_code is null then
    select coalesce(max(sort), 0) + 1 into v_sort from packages where audience = p_audience;
    v_code := 'custom_' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
    insert into packages(code, audience, name_en, name_ar, sessions, price_egp, weekly_limit, validity_days,
                         is_drop_in, is_private, active, sort)
    values (v_code, p_audience, trim(p_name_en), coalesce(nullif(trim(p_name_ar), ''), trim(p_name_en)),
            p_sessions, p_price, case when coalesce(p_is_drop_in, false) then null else p_weekly_limit end,
            p_validity_days, coalesce(p_is_drop_in, false), coalesce(p_is_private, false),
            coalesce(p_active, true), v_sort);
  else
    if not exists (select 1 from packages where code = v_code) then raise exception 'Unknown package'; end if;
    update packages set audience = p_audience, name_en = trim(p_name_en),
           name_ar = coalesce(nullif(trim(p_name_ar), ''), trim(p_name_en)),
           sessions = p_sessions, price_egp = p_price,
           weekly_limit = case when coalesce(p_is_drop_in, false) then null else p_weekly_limit end,
           validity_days = p_validity_days, is_drop_in = coalesce(p_is_drop_in, false),
           is_private = coalesce(p_is_private, false), active = coalesce(p_active, true)
     where code = v_code;
  end if;
  return v_code;
end $$;

create or replace function set_package_active(p_code text, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  update packages set active = p_active where code = p_code;
end $$;

-- Move a package up or down within its own list (same audience and kind).
create or replace function move_package(p_code text, p_dir int) returns void
language plpgsql security definer set search_path = public as $$
declare k packages; o packages;
begin
  if not is_owner() then raise exception 'Not allowed'; end if;
  select * into k from packages where code = p_code;
  if k.code is null then raise exception 'Unknown package'; end if;
  -- give every package in the list a distinct sort first
  update packages x set sort = r.rn
    from (select code, row_number() over (order by sort, code) rn from packages
           where audience = k.audience and is_private = k.is_private) r
   where x.code = r.code;
  select * into k from packages where code = p_code;
  select * into o from packages
   where audience = k.audience and is_private = k.is_private
     and (case when p_dir < 0 then sort < k.sort else sort > k.sort end)
   order by case when p_dir < 0 then -sort else sort end limit 1;
  if o.code is null then return; end if;
  update packages set sort = o.sort where code = k.code;
  update packages set sort = k.sort where code = o.code;
end $$;

revoke all on function save_package(text, audience, text, text, int, numeric, int, int, boolean, boolean, boolean) from public, anon;
revoke all on function set_package_active(text, boolean) from public, anon;
revoke all on function move_package(text, int) from public, anon;
grant execute on function save_package(text, audience, text, text, int, numeric, int, int, boolean, boolean, boolean) to authenticated;
grant execute on function set_package_active(text, boolean) to authenticated;
grant execute on function move_package(text, int) to authenticated;
