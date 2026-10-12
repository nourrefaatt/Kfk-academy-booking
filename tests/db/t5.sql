\set ON_ERROR_STOP 0
\pset pager off
reset role;
-- a class that ended 1 hour ago and one that ended 13 hours ago (inside current week if possible)
insert into classes(id,name,audience,weekday,start_time,duration_min) values
 ('11111111-1111-1111-1111-111111111111','Past1h','adults',0,'00:00',60),
 ('22222222-2222-2222-2222-222222222222','Past13h','adults',0,'00:00',60);
insert into sessions(class_id,session_date,starts_at,ends_at) values
 ('11111111-1111-1111-1111-111111111111', ((now()-interval '2 hours') at time zone 'Africa/Cairo')::date, now()-interval '2 hours', now()-interval '1 hour'),
 ('22222222-2222-2222-2222-222222222222', ((now()-interval '14 hours') at time zone 'Africa/Cairo')::date, now()-interval '14 hours', now()-interval '13 hours');
set role authenticated;
select as_user('00000000-0000-0000-0000-00000000000c');
\echo 'book class ended 1h ago (expect booked, unless one-per-day)'
select book_session((select id from members where full_name='Client Two'), (select id from sessions where class_id='11111111-1111-1111-1111-111111111111' and ends_at < now()));
\echo 'EXPECT ERROR: ended 13h ago'
select book_session((select id from members where full_name='Client Two'), (select id from sessions where class_id='22222222-2222-2222-2222-222222222222' and ends_at < now() order by ends_at desc limit 1));
-- cash expiry from approval
reset role;
insert into payments(member_id, package_code, amount_egp, method, status, created_at)
values ((select id from members where full_name='Client One'),'adult_12',3500,'cash','pending', now() - interval '5 days');
set role authenticated;
select as_user('00000000-0000-0000-0000-00000000000a');
select decide_payment((select id from payments where status='pending' limit 1), true, null);
-- announcements
select send_announcement('To parents','x','parents') parents, send_announcement('To clients','y','clients') clients, send_announcement('All','z') alls;
-- messages
select send_message('00000000-0000-0000-0000-00000000000c','Hi Client Two, see you tonight') is not null as staff_sent;
\echo 'EXPECT ERROR staff to coach/owner account'
select send_message('00000000-0000-0000-0000-00000000000a','x');
select as_user('00000000-0000-0000-0000-00000000000c');
select body, from_staff, read_by_account is null as unread from messages;
select send_message('00000000-0000-0000-0000-00000000000c','Thanks coach!') is not null as client_replied;
\echo 'EXPECT ERROR client writes to other account'
select send_message('00000000-0000-0000-0000-00000000000b','spam');
select mark_messages_read('00000000-0000-0000-0000-00000000000c');
select as_user('00000000-0000-0000-0000-00000000000b');
select count(*) as other_client_sees from messages;
\echo 'EXPECT ERROR client threads'
select * from message_threads();
select as_user('00000000-0000-0000-0000-00000000000a');
select full_name, last_body, unread from message_threads();
