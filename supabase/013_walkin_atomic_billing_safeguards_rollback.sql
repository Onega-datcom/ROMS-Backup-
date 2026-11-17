-- Retire the Phase B entry point without deleting idempotency or audit data.
-- Phase C guards and audit storage intentionally remain active to avoid
-- invalidating override records or reopening the Walk-in package path.

begin;

revoke all on function public.pos_seat_and_open_walkin(text, text, text, date, text, text, integer, integer, integer, text, text)
  from public, anon, authenticated;
drop function if exists public.pos_seat_and_open_walkin(text, text, text, date, text, text, integer, integer, integer, text, text);

commit;
