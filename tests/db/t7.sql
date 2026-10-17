\set ON_ERROR_STOP 0
\pset pager off
-- Private groups + adult 8 package (update 005)
reset role;
insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-0000000000f1','g1@x.com','{"role":"client","full_name":"G One","date_of_birth":"1990-01-01"}'),
 ('00000000-0000-0000-0000-0000000000f2','g2@x.com','{"role":"client","full_name":"G Two","date_of_birth":"1990-01-01"}'),
 ('00000000-0000-0000-0000-0000000000f3','g3@x.com','{"role":"client","full_name":"G Three","date_of_birth":"1990-01-01"}'),
 ('00000000-0000-0000-0000-0000000000f4','g4@x.com','{"role":"client","full_name":"G Four","date_of_birth":"1990-01-01"}');
select code, price_egp, weekly_limit, validity_days, is_private from packages order by audience, sort;
set role authenticated;
select as_user('00000000-0000-0000-0000-00000000000a');
\echo 'EXPECT ERROR: max below 3'
select save_private_group(null,'PG small','adults',3,'10:00',60,2,null,null);
select save_private_group(null,'PG Adults','adults', extract(dow from cairo_now())::int, '00:00', 60, 3, null, null) is not null as created;
\echo 'EXPECT ERROR: child in adult group'
select set_group_members((select id from classes where name='PG Adults'), array[(select id from members where full_name='Little Kid')]);
\echo 'EXPECT ERROR: too many'
select set_group_members((select id from classes where name='PG Adults'),
  array(select id from members where full_name in ('G One','G Two','G Three','G Four')));
select set_group_members((select id from classes where name='PG Adults'),
  array(select id from members where full_name in ('G One','G Two','G Three')));
select count(*) as roster from class_members;
-- balances: G One buys private 8, G Two private drop-in, G Three nothing; G Four adult_8 regular
select as_user('00000000-0000-0000-0000-0000000000f1');
select purchase((select id from members where full_name='G One'),'adult_priv_8','online')->>'status';
\echo 'EXPECT ERROR: regular class with only private balance'
select book_session((select id from members where full_name='G One'),
  (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Wed' and week_start(s.session_date)=week_start(cairo_now()::date)));
select member_balance((select id from members where full_name='G One')) - 'lots' as g1_bal;
select as_user('00000000-0000-0000-0000-0000000000f2');
select purchase((select id from members where full_name='G Two'),'adult_priv_dropin','online')->>'status';
select as_user('00000000-0000-0000-0000-0000000000f4');
select purchase((select id from members where full_name='G Four'),'adult_8','online')->>'status';
select member_balance((select id from members where full_name='G Four'))->>'weekly_limit' as g4_limit;
\echo 'EXPECT ERROR: not in private group'
reset role;
create temp table pg as select s.id sid from sessions s join classes c on c.id=s.class_id where c.name='PG Adults' and s.session_date = cairo_now()::date;
grant select on pg to authenticated;
-- make the session already over by more than 12h? First: booking (session at 00:00 today, ended; within 12h if now < 13:00) -> move it to 'just ended'
update sessions set starts_at = now() - interval '2 hours', ends_at = now() - interval '1 hour' where id = (select sid from pg);
set role authenticated;
select book_session((select id from members where full_name='G Four'), (select sid from pg));
select as_user('00000000-0000-0000-0000-0000000000f1');
select book_session((select id from members where full_name='G One'), (select sid from pg)) as g1_books;
select member_balance((select id from members where full_name='G One'))->>'private_left' as g1_private_after_book;
-- booking window closes: move session 13h back, run jobs
reset role;
update sessions set starts_at = now() - interval '14 hours', ends_at = now() - interval '13 hours' where id = (select sid from pg);
set role authenticated;
select run_due_jobs();
select run_due_jobs();
reset role;
select m.full_name, b.status, b.lot_id is not null as paid from bookings b join members m on m.id=b.member_id where b.session_id=(select sid from pg) order by 1;
select m.full_name, coalesce(sum(l.sessions_left) filter (where l.is_private),0) private_left
  from members m left join lots l on l.member_id=m.id where m.full_name like 'G %' group by 1 order by 1;
select n.title from notifications n join members m on m.id=n.member_id where n.kind='group_charge' order by 1;
