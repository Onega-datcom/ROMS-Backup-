-- Roll back Phase A reservation guest counts and source support.
-- Contactless Walk-ins may remain; the restored contact constraint is NOT VALID
-- so rollback preserves those rows while enforcing the old rule on new writes.

begin;

create or replace function public.enforce_reservation_table_capacity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  table_capacity integer;
begin
  if tg_op = 'INSERT'
     or new.table_id is distinct from old.table_id
     or new.guests is distinct from old.guests
     or new.actual_covers is distinct from old.actual_covers then
    if new.table_id is not null then
      select seats into table_capacity
      from public.restaurant_tables
      where id = new.table_id;
      if not found then
        raise exception 'The selected table does not exist'
          using errcode = '23503';
      end if;
      if coalesce(new.actual_covers, new.guests) > table_capacity then
        raise exception 'The selected table does not have enough seats for this reservation'
          using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_reservation_capacity on public.reservations;
create trigger enforce_reservation_capacity
  before insert or update on public.reservations
  for each row execute function public.enforce_reservation_table_capacity();

drop trigger if exists set_public_reservation_source on public.reservations;
drop function if exists public.set_public_reservation_source();
drop trigger if exists prevent_historical_reservation_phase_a_changes on public.reservations;
drop function if exists public.prevent_historical_reservation_phase_a_changes();

alter table public.reservations
  drop constraint if exists reservations_contact_check;
alter table public.reservations
  add constraint reservations_contact_check check (
    nullif(btrim(coalesce(email, '')), '') is not null
    or nullif(btrim(coalesce(phone, '')), '') is not null
  ) not valid;

alter table public.reservations
  drop constraint if exists reservations_source_check,
  drop constraint if exists reservations_senior_pwd_count_check,
  drop column if exists source,
  drop column if exists senior_pwd_count;

revoke all on function public.enforce_reservation_table_capacity() from public, anon, authenticated;

commit;
