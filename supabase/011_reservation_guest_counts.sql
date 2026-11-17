-- Phase A: reservation Senior/PWD counts, sources, and walk-in contact rules.
-- Run after 010_pos_single_source_security.sql.

begin;

alter table public.reservations
  add column if not exists senior_pwd_count integer not null default 0,
  add column if not exists source text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reservations'::regclass
      and conname = 'reservations_senior_pwd_count_check'
  ) then
    alter table public.reservations
      add constraint reservations_senior_pwd_count_check
      check (senior_pwd_count >= 0) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reservations'::regclass
      and conname = 'reservations_source_check'
  ) then
    alter table public.reservations
      add constraint reservations_source_check
      check (source is null or source in ('Website', 'Phone', 'Facebook', 'Walk-in', 'Other')) not valid;
  end if;
end;
$$;

alter table public.reservations
  validate constraint reservations_senior_pwd_count_check,
  validate constraint reservations_source_check;

alter table public.reservations
  drop constraint if exists reservations_contact_check;
alter table public.reservations
  add constraint reservations_contact_check check (
    type = 'Walk-in'
    or nullif(btrim(coalesce(email, '')), '') is not null
    or nullif(btrim(coalesce(phone, '')), '') is not null
  ) not valid;
alter table public.reservations
  validate constraint reservations_contact_check;

create or replace function public.enforce_reservation_table_capacity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  table_capacity integer;
  total_covers integer;
  capacity_covers integer;
  guest_counts_changed boolean;
begin
  total_covers := coalesce(new.adults, 0)
    + coalesce(new.senior_pwd_count, 0)
    + coalesce(new.children, 0);
  guest_counts_changed := tg_op = 'INSERT'
    or new.adults is distinct from old.adults
    or new.senior_pwd_count is distinct from old.senior_pwd_count
    or new.children is distinct from old.children;

  if guest_counts_changed or new.guests is distinct from old.guests then
    if total_covers < 1 or total_covers > 1000 then
      raise exception 'Reservation guest counts must total between 1 and 1,000'
        using errcode = '23514';
    end if;
    new.guests := total_covers;
  end if;
  capacity_covers := case
    when new.type = 'Walk-in' and total_covers > 0 then total_covers
    when total_covers > 0 then coalesce(new.actual_covers, total_covers)
    else coalesce(new.actual_covers, new.guests, 0)
  end;

  if new.type = 'Walk-in' and new.status = 'Seated'
     and (tg_op = 'INSERT' or guest_counts_changed
       or new.status is distinct from old.status) then
    new.actual_covers := total_covers;
  end if;

  if tg_op = 'INSERT'
     or new.table_id is distinct from old.table_id
     or new.guests is distinct from old.guests
     or new.adults is distinct from old.adults
     or new.senior_pwd_count is distinct from old.senior_pwd_count
     or new.children is distinct from old.children
     or new.actual_covers is distinct from old.actual_covers then
    if new.table_id is not null then
      select seats into table_capacity
      from public.restaurant_tables
      where id = new.table_id;
      if not found then
        raise exception 'The selected table does not exist'
          using errcode = '23503';
      end if;
      if capacity_covers > table_capacity then
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

create or replace function public.set_public_reservation_source()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.id like 'RSV-%' then
    new.source := 'Website';
  end if;
  return new;
end;
$$;

drop trigger if exists set_public_reservation_source on public.reservations;
create trigger set_public_reservation_source
  before insert on public.reservations
  for each row execute function public.set_public_reservation_source();

create or replace function public.prevent_historical_reservation_phase_a_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if old.reservation_date < current_date
     and (new.senior_pwd_count is distinct from old.senior_pwd_count
       or new.source is distinct from old.source) then
    raise exception 'Historical corrections cannot change Senior/PWD count or reservation source'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_historical_reservation_phase_a_changes on public.reservations;
create trigger prevent_historical_reservation_phase_a_changes
  before update on public.reservations
  for each row execute function public.prevent_historical_reservation_phase_a_changes();

revoke all on function public.enforce_reservation_table_capacity() from public, anon, authenticated;
revoke all on function public.set_public_reservation_source() from public, anon, authenticated;
revoke all on function public.prevent_historical_reservation_phase_a_changes() from public, anon, authenticated;

commit;
