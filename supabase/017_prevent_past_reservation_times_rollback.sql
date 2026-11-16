-- Remove same-day past reservation-time protection from migration 017.
-- This does not modify existing reservations.

begin;

drop trigger if exists enforce_reservation_start_not_past on public.reservations;
drop function if exists public.enforce_reservation_start_not_past();

commit;
