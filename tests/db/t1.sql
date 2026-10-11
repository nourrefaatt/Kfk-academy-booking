\set ON_ERROR_STOP 0
\pset pager off
-- users
insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a','seif@x.com','{"role":"client","full_name":"Seif","date_of_birth":"1998-01-01"}'),
 ('00000000-0000-0000-0000-00000000000b','c1@x.com','{"role":"client","full_name":"Client One","date_of_birth":"1995-05-05","phone":"010"}'),
 ('00000000-0000-0000-0000-00000000000c','c2@x.com','{"role":"client","full_name":"Client Two","date_of_birth":"2012-01-01"}'),
 ('00000000-0000-0000-0000-00000000000d','p@x.com','{"role":"parent","full_name":"Parent"}');
\echo 'EXPECT ERROR: 12-year-old client'
insert into auth.users(id,email,raw_user_meta_data) values ('00000000-0000-0000-0000-00000000000e','kid@x.com','{"role":"client","full_name":"Too Young","date_of_birth":"2015-01-01"}');
update profiles set role='owner' where email='seif@x.com';
select email, role from profiles order by email;
select full_name, kind from members order by full_name;

create or replace function as_user(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u, false); end $$;
grant execute on function as_user(text) to authenticated;
