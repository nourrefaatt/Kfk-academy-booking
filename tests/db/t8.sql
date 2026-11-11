\set ON_ERROR_STOP 0
\pset pager off
-- Owner package editor (update 006)
reset role;
insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-0000000000e1','p1@x.com','{"role":"client","full_name":"P One","date_of_birth":"1990-01-01"}');
set role authenticated;
select as_user('00000000-0000-0000-0000-0000000000e1');
\echo 'EXPECT ERROR: client cannot create packages'
select save_package(null,'adults','Hack','',10,1,null,null,false,false,true);
select as_user('00000000-0000-0000-0000-00000000000a');
\echo 'EXPECT ERROR: drop-in must be 1 session'
select save_package(null,'adults','Bad drop','',2,100,null,null,true,false,true);
\echo 'EXPECT ERROR: name required'
select save_package(null,'adults','  ','',5,100,null,null,false,false,true);
\echo 'EXPECT ERROR: weekly 0'
select save_package(null,'adults','Bad wk','',5,100,0,30,false,false,true);
select save_package(null,'adults','16 sessions','١٦ حصة',16,4200,5,45,false,false,true) like 'custom_%' as created;
select name_en, name_ar, sessions, price_egp, weekly_limit, validity_days, is_drop_in, is_private, active,
       sort > (select max(sort) from packages where audience='adults' and code not like 'custom_%') as at_end
  from packages where name_en='16 sessions';
-- buy it as a client: lot copies the package values
select as_user('00000000-0000-0000-0000-0000000000e1');
select purchase((select id from members where full_name='P One'),(select code from packages where name_en='16 sessions'),'online')->>'status' as bought;
select sessions_left, weekly_limit, expires_at::date - now()::date as days, is_private from lots
 where member_id=(select id from members where full_name='P One');
-- edit: price and sessions change; existing lot does not
select as_user('00000000-0000-0000-0000-00000000000a');
select save_package((select code from packages where name_en='16 sessions'),'adults','16 sessions','',16,4000,null,null,false,false,true) is not null as edited;
select price_egp, weekly_limit, validity_days, name_ar from packages where name_en='16 sessions';
select sessions_left, weekly_limit from lots where member_id=(select id from members where full_name='P One');
-- hide: clients can no longer buy it
select set_package_active((select code from packages where name_en='16 sessions'), false);
select as_user('00000000-0000-0000-0000-0000000000e1');
\echo 'EXPECT ERROR: hidden package'
select purchase((select id from members where full_name='P One'),(select code from packages where name_en='16 sessions'),'online');
-- move
select as_user('00000000-0000-0000-0000-00000000000a');
select string_agg(code, ',' order by sort) as before from packages where audience='adults' and not is_private;
select move_package('adult_dropin', -1);
select string_agg(code, ',' order by sort) as after_up from packages where audience='adults' and not is_private;
select move_package('adult_8', -1);
select string_agg(code, ',' order by sort) as after_top from packages where audience='adults' and not is_private;
