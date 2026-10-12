\set ON_ERROR_STOP 0
\pset pager off
do $$ begin create role service_role nologin; exception when others then null; end $$;
grant usage on schema public to service_role;
grant execute on function confirm_online_payment(uuid,text,text,bigint,boolean,boolean) to service_role;
set role authenticated;
select as_user('00000000-0000-0000-0000-00000000000c');
select start_online_payment((select id from members where full_name='Client Two'),'adult_12') - 'payment_id' as started;
select set_payment_provider_order((select id from payments where provider='paymob' and status='pending'), 'ORD-1');
\echo 'EXPECT ERROR: client confirms own payment'
select confirm_online_payment(null,'ORD-1','T1',350000,true,true);
\echo 'pending card does not block cash:'
select purchase((select id from members where full_name='Client Two'),'adult_dropin','cash')->>'status';
select status, method, note from payments where member_id=(select id from members where full_name='Client Two') order by created_at desc limit 2;
-- restart card checkout (cash pending now blocks)
\echo 'EXPECT ERROR: cash pending blocks card start'
select start_online_payment((select id from members where full_name='Client Two'),'adult_12');
select as_user('00000000-0000-0000-0000-00000000000a');
select decide_payment((select id from payments where method='cash' and status='pending' limit 1), false, 'test');
\echo 'EXPECT ERROR: staff approves card payment'
reset role;
update payments set status='pending' where provider_order_id='ORD-1';
set role authenticated;
select decide_payment((select id from payments where provider_order_id='ORD-1'), true, null);
select as_user('00000000-0000-0000-0000-00000000000c');
select (select member_balance(id)->>'sessions_left' from members where full_name='Client Two') as bal_before;
set role service_role;
select confirm_online_payment(null,'ORD-1','T1',100,true,true) as wrong_amount;
select confirm_online_payment(null,'ORD-1','T1',350000,true,true) as ok;
select confirm_online_payment(null,'ORD-1','T1',350000,true,true) as again;
set role authenticated;
select (select member_balance(id)->>'sessions_left' from members where full_name='Client Two') as bal_after;
select status, test_mode, provider_txn_id from payments where provider_order_id='ORD-1';
select title from notifications where kind='payment_paid';
-- failed payment
select start_online_payment((select id from members where full_name='Client Two'),'adult_dropin')->>'amount_cents' as dropin_cents;
set role service_role;
select confirm_online_payment((select id from payments where provider='paymob' and status='pending'), null, 'T2', 50000, false, true) as failed;
