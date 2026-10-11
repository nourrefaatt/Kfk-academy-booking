\set ON_ERROR_STOP 0
\pset pager off
set role authenticated;
-- OWNER sets up classes
select as_user('00000000-0000-0000-0000-00000000000a');
select now() at time zone 'Africa/Cairo' as cairo_now, week_start(cairo_now()::date) as week;
-- today class starting in 2h (for 3-hour rule)
select save_class(null,'Adults Today','adults', extract(dow from cairo_now())::int, (cairo_now() + interval '2 hours')::time(0), 60, null, null, 'Les Rois');
select save_class(null,'Adults Tue','adults',2,'18:00',60,1,null,null);
select save_class(null,'Adults Tue2','adults',2,'20:00',60,null,null,null);
select save_class(null,'Adults Wed','adults',3,'18:00',60,null,null,null);
select save_class(null,'Adults Thu','adults',4,'18:00',60,null,null,null);
select save_class(null,'Adults Fri','adults',5,'18:00',60,null,null,null);
select save_class(null,'Kids Tue','kids',2,'17:00',60,null,null,null);
select c.name, s.session_date, to_char(s.starts_at at time zone 'Africa/Cairo','Dy HH24:MI') t, s.capacity from sessions s join classes c on c.id=s.class_id order by s.starts_at;

reset role;
create temp table ids as select
 (select id from members where full_name='Client One') m1,
 (select id from members where full_name='Client Two') m2,
 (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Today' and week_start(s.session_date)=week_start(cairo_now()::date)) s_today,
 (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Tue' and week_start(s.session_date)=week_start(cairo_now()::date)) s_tue,
 (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Tue2' and week_start(s.session_date)=week_start(cairo_now()::date)) s_tue2,
 (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Wed' and week_start(s.session_date)=week_start(cairo_now()::date)) s_wed,
 (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Thu' and week_start(s.session_date)=week_start(cairo_now()::date)) s_thu,
 (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Fri' and week_start(s.session_date)=week_start(cairo_now()::date)) s_fri,
 (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Wed' and week_start(s.session_date)>week_start(cairo_now()::date)) s_nextwed,
 (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Kids Tue' and week_start(s.session_date)=week_start(cairo_now()::date)) s_kids;
grant select on ids to authenticated;
set role authenticated;
select as_user('00000000-0000-0000-0000-00000000000b');
\echo 'EXPECT ERROR no sessions'
select book_session(m1, s_tue) from ids;
\echo 'EXPECT ERROR kids package for adult'
select purchase(m1,'kids_8','cash') from ids;
select purchase(m1,'adult_12','cash') from ids;
\echo 'EXPECT ERROR second pending'
select purchase(m1,'adult_12','cash') from ids;
\echo 'EXPECT ERROR client approves'
select decide_payment((select id from payments limit 1), true);
-- OWNER approves
select as_user('00000000-0000-0000-0000-00000000000a');
select decide_payment((select id from payments where status='pending' limit 1), true, null);
select as_user('00000000-0000-0000-0000-00000000000b');
select member_balance(m1)->'sessions_left' bal, member_balance(m1)->'weekly_limit' lim from ids;
select book_session(m1, s_today) from ids;
select book_session(m1, s_tue) from ids;
\echo 'EXPECT ERROR one per day'
select book_session(m1, s_tue2) from ids;
\echo 'EXPECT ERROR next week not open'
select book_session(m1, s_nextwed) from ids;
\echo 'EXPECT ERROR kids class'
select book_session(m1, s_kids) from ids;
select book_session(m1, s_wed) from ids;
select book_session(m1, s_thu) from ids;
\echo 'EXPECT ERROR weekly limit 4'
select book_session(m1, s_fri) from ids;
\echo 'EXPECT ERROR drop-in over limit'
select purchase(m1,'adult_dropin','online') from ids;
select member_balance(m1)->'sessions_left' bal_before_cancels from ids;
\echo 'today cancel within 3h -> late_cancel'
select cancel_booking((select id from bookings where session_id=s_today and member_id=m1)) from ids;
\echo 'wed cancel -> cancelled (refund)'
select cancel_booking((select id from bookings where session_id=s_wed and member_id=m1)) from ids;
select member_balance(m1)->'sessions_left' bal_after, member_balance(m1)->'used_this_week' used from ids;

-- CLIENT TWO buys online test, waitlists on full Tue
select as_user('00000000-0000-0000-0000-00000000000c');
select purchase(m2,'adult_12','online') from ids;
select book_session(m2, s_tue) as expect_waitlisted from ids;
\echo 'RLS: client2 sees bookings count (expect 0)'
select count(*) from bookings;
\echo 'EXPECT ERROR: client2 cancel client1 booking'
select cancel_booking((select id from bookings b where b.member_id = (select m1 from ids) limit 1));
\echo 'EXPECT ERROR: update role'
update profiles set role='owner' where id=auth.uid();
update profiles set full_name='Client Two B' where id=auth.uid();
-- client1 cancels Tue -> client2 promoted
select as_user('00000000-0000-0000-0000-00000000000b');
select cancel_booking((select id from bookings where session_id=s_tue and member_id=m1 and status='booked')) from ids;
select as_user('00000000-0000-0000-0000-00000000000c');
select b.status, b.from_waitlist from bookings b, ids where b.session_id=s_tue and b.member_id=m2;
select kind, title from notifications order by created_at;
select member_balance(m2)->'sessions_left' c2_bal from ids;

-- Early recharge for client2
select purchase(m2,'adult_12','online') from ids;
select source, sessions_left, round(extract(epoch from expires_at-now())/86400) days_left from lots where member_id=(select m2 from ids) order by created_at;

-- OWNER/COACH cancels Thu (client1 booked)
select as_user('00000000-0000-0000-0000-00000000000a');
select cancel_session(s_thu, 'Coach sick') from ids;
select b.status from bookings b, ids where b.session_id=s_thu;
select as_user('00000000-0000-0000-0000-00000000000b');
select member_balance(m1)->'sessions_left' c1_after_coach_cancel from ids;
select kind, title, body from notifications where kind='class_cancelled';
