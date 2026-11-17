-- Phase A follow-up: include Senior/PWD guests in the reservation total check.
-- Run after 011_reservation_guest_counts.sql.

begin;

alter table public.reservations
  drop constraint if exists reservations_guest_count_check;
alter table public.reservations
  add constraint reservations_guest_count_check
  check (guests = adults + senior_pwd_count + children) not valid;

commit;
