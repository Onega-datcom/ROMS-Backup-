begin;

create or replace function public.reservation_time_within_open_hours(time_value text)
returns boolean
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
    return false;
  end if;

  hour_value := split_part(clock_value, ':', 1)::integer;
  minute_value := split_part(clock_value, ':', 2)::integer;
  if meridiem = 'AM' then
    if hour_value = 12 then hour_value := 0; end if;
  elsif meridiem = 'PM' and hour_value < 12 then
    hour_value := hour_value + 12;
  end if;

  return hour_value * 60 + minute_value >= 10 * 60
    and hour_value * 60 + minute_value < 21 * 60;
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
      raise exception 'Reservation time must be within restaurant hours (10:00 AM to before 9:00 PM)'
        using errcode = '23514';
    end if;
  elsif new.reservation_date is distinct from old.reservation_date
        or new.reservation_time is distinct from old.reservation_time then
    if not public.reservation_time_within_open_hours(new.reservation_time) then
      raise exception 'Reservation time must be within restaurant hours (10:00 AM to before 9:00 PM)'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_reservation_hours on public.reservations;
create trigger enforce_reservation_hours
  before insert or update on public.reservations
  for each row execute function public.enforce_reservation_hours();

revoke all on function public.reservation_time_within_open_hours(text) from public, anon, authenticated;
revoke all on function public.enforce_reservation_hours() from public, anon, authenticated;

commit;
