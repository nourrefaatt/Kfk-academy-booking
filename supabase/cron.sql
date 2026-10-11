-- Optional: run the daily jobs (expiry reminders, expiring balances, next week's classes)
-- every hour automatically. The app also runs them whenever someone books, so this is a
-- safety net. Supabase → Database → Extensions → enable "pg_cron", then run this file.

select cron.schedule('kfk-due-jobs', '0 * * * *', $$ select public.run_due_jobs(); $$);
