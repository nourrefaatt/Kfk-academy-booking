\set ON_ERROR_STOP 0
\pset pager off
set role authenticated;
-- PARENT
select as_user('00000000-0000-0000-0000-00000000000d');
\echo 'EXPECT ERROR child 13+'
select add_child('Big Kid','2010-01-01',null,null,null);
select add_child('Little Kid','2017-03-03','Mom 012','Asthma','None') is not null as child_added;
select add_child('Second Kid','2019-03-03',null,null,null) is not null as child2;
select full_name, kind from members order by full_name;
\echo 'EXPECT ERROR adult package for child'
select purchase((select id from members where full_name='Little Kid'),'adult_12','cash');
select purchase((select id from members where full_name='Little Kid'),'kids_8','cash')->>'status';
select purchase((select id from members where full_name='Second Kid'),'kids_dropin','cash')->>'status';
-- owner approves both
select as_user('00000000-0000-0000-0000-00000000000a');
select decide_payment(id, true) from payments where status='pending' and member_id in (select id from members where kind='child') and package_code='kids_8';
select decide_payment(id, false, 'Cash not received') from payments where status='pending';
select as_user('00000000-0000-0000-0000-00000000000d');
select title, body from notifications order by created_at;
select member_balance(id)->>'sessions_left' bal, member_balance(id)->>'weekly_limit' lim, full_name from members order by full_name;
select book_session((select id from members where full_name='Little Kid'),
  (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Kids Tue' and week_start(s.session_date)=week_start(cairo_now()::date)));
\echo 'EXPECT ERROR adult class for child'
select book_session((select id from members where full_name='Little Kid'),
  (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Fri' and week_start(s.session_date)=week_start(cairo_now()::date)));
select count(*) as parent_sees_payments from payments;

-- COACH tools as owner
select as_user('00000000-0000-0000-0000-00000000000a');
select set_attendance(b.id, true) from bookings b join members m on m.id=b.member_id where m.full_name='Little Kid';
select status from bookings b join members m on m.id=b.member_id where m.full_name='Little Kid';
-- expired-lot refund: client1 booked Fri? book Fri for client one as staff then expire lot then cancel
select book_session((select id from members where full_name='Client One'),
  (select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Fri' and week_start(s.session_date)=week_start(cairo_now()::date))) as staff_books_c1_fri;
reset role;
update lots set expires_at = now() - interval '1 day' where member_id=(select id from members where full_name='Client One');
set role authenticated;
select run_due_jobs();
select sessions_left, expired_sessions from lots where member_id=(select id from members where full_name='Client One');
select cancel_session((select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Fri' and week_start(s.session_date)=week_start(cairo_now()::date)), 'Holiday');
select source, sessions_left, (expires_at - now()) > interval '5 days' as six_days_left from lots where member_id=(select id from members where full_name='Client One') order by created_at;
-- expiry reminder
reset role;
update lots set expires_at = now() + interval '5 days', reminder_sent=false where member_id=(select id from members where full_name='Little Kid');
set role authenticated;
select run_due_jobs();
select * from expiring_soon();
reset role;
update lots set expires_at = now() + interval '3 days' where member_id=(select id from members where full_name='Little Kid');
set role authenticated;
select member_name, sessions_left from expiring_soon();
select notify_expiring((select id from members where full_name='Little Kid'));
select kind, title from notifications n join members m on m.id=n.member_id where m.full_name='Little Kid' order by n.created_at;
-- class time change notifies
select save_class((select id from classes where name='Kids Tue'),'Kids Tue','kids',2,'17:30',60,null,null,null);
select title, body from notifications where kind='class_changed';
-- locks
select save_settings(true,false,true);
select as_user('00000000-0000-0000-0000-00000000000b');
\echo 'EXPECT ERROR bookings locked'
select book_session((select id from members where full_name='Client One'),(select s.id from sessions s join classes c on c.id=s.class_id where c.name='Adults Tue2' and week_start(s.session_date)=week_start(cairo_now()::date)));
select as_user('00000000-0000-0000-0000-00000000000a');
select save_settings(false,false,true);
select adjust_balance((select id from members where full_name='Client One'), 3, now()+interval '10 days', 4, 'gift');
select as_user('00000000-0000-0000-0000-00000000000b');
select member_balance((select id from members where full_name='Client One'))->>'sessions_left' after_gift;
\echo 'EXPECT ERROR client stats'
select owner_stats();
select as_user('00000000-0000-0000-0000-00000000000a');
select jsonb_pretty(owner_stats());
select announce from (select send_announcement('Holiday','Gym closed Friday') announce) x;
