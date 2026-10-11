\pset pager off
select n.kind, n.title, n.body from notifications n join members m on m.id=n.member_id where m.full_name='Little Kid' order by n.created_at;
