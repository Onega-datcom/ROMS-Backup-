-- Phase 16: enforce two-hour reservation windows and prevent overlapping
-- active bookings for the same table and date.
begin;

create or replace function public.reservation_time_to_minutes(time_value text)
returns integer
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  normalized text := upper(btrim(coalesce(time_value, '')));
  clock_value text;
  meridiem text;
  hour_value integer;
  minute_value integer;
begin
  if normalized ~ '^(0?[1-9]|1[0-2]):[0-5][0-9][[:space:]]*(AM|PM)$' then
    clock_value := regexp_replace(normalized, '[[:space:]]*(AM|PM)$', '');
    meridiem := right(normalized, 2);
  elsif normalized ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    clock_value := normalized;
    meridiem := null;
  else
    return null;
  end if;

  hour_value := split_part(clock_value, ':', 1)::integer;
  minute_value := split_part(clock_value, ':', 2)::integer;
  if meridiem = 'AM' then
    if hour_value = 12 then hour_value := 0; end if;
  elsif meridiem = 'PM' and hour_value < 12 then
    hour_value := hour_value + 12;
  end if;

  return hour_value * 60 + minute_value;
end;
$$;

create or replace function public.reservation_time_within_open_hours(time_value text)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  start_minutes integer := public.reservation_time_to_minutes(time_value);
begin
  return start_minutes is not null
    and start_minutes >= 10 * 60
    and start_minutes + 120 <= 21 * 60;
end;
$$;

create or replace function public.enforce_reservation_hours()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'INSERT' then
    if not public.reservation_time_within_open_hours(new.reservation_time) then
      raise exception 'The two-hour reservation window must fit between 10:00 AM and 9:00 PM'
        using errcode = '23514';
    end if;
  elsif new.reservation_date is distinct from old.reservation_date
        or new.reservation_time is distinct from old.reservation_time then
    if not public.reservation_time_within_open_hours(new.reservation_time) then
      raise exception 'The two-hour reservation window must fit between 10:00 AM and 9:00 PM'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.enforce_reservation_table_overlap()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  new_start integer;
begin
  if new.table_id is null or new.status not in ('Pending', 'Confirmed', 'Seated') then
    return new;
  end if;

  if not public.reservation_time_within_open_hours(new.reservation_time) then
    raise exception 'The two-hour reservation window must fit between 10:00 AM and 9:00 PM'
      using errcode = '23514';
  end if;
  new_start := public.reservation_time_to_minutes(new.reservation_time);

  perform pg_advisory_xact_lock(hashtext(new.table_id), hashtext(new.reservation_date::text));

  if exists (
    select 1
    from public.reservations existing
    where existing.table_id = new.table_id
      and existing.id <> new.id
      and existing.status in ('Pending', 'Confirmed', 'Seated')
      and (
        (existing.status = 'Seated' and existing.reservation_date < new.reservation_date and new.reservation_date = current_date)
        or (
          existing.reservation_date = new.reservation_date
          and new_start < public.reservation_time_to_minutes(existing.reservation_time) + 120
          and public.reservation_time_to_minutes(existing.reservation_time) < new_start + 120
        )
      )
  ) then
    raise exception 'The selected table already has an overlapping two-hour reservation'
      using errcode = '23505';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_reservation_hours on public.reservations;
create trigger enforce_reservation_hours
  before insert or update on public.reservations
  for each row execute function public.enforce_reservation_hours();

drop trigger if exists enforce_reservation_table_overlap on public.reservations;
create trigger enforce_reservation_table_overlap
  before insert or update on public.reservations
  for each row execute function public.enforce_reservation_table_overlap();

revoke all on function public.reservation_time_to_minutes(text) from public, anon, authenticated;
revoke all on function public.reservation_time_within_open_hours(text) from public, anon, authenticated;
revoke all on function public.enforce_reservation_hours() from public, anon, authenticated;
revoke all on function public.enforce_reservation_table_overlap() from public, anon, authenticated;

commit;
