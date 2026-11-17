-- Restore the pre-Phase-A guest total rule.
-- NOT VALID preserves rows with Senior/PWD counts if Phase A data already exists.

begin;

alter table public.reservations
  drop constraint if exists reservations_guest_count_check;
alter table public.reservations
  add constraint reservations_guest_count_check
  check (guests = adults + children) not valid;

commit;
