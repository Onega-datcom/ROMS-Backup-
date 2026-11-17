-- Reject new or rescheduled reservations whose same-day start time has passed.
-- Walk-ins are exempt because their start time is recorded as they arrive.
-- Run after 016_stale_walkin_completion.sql.

begin;

create or replace function public.enforce_reservation_start_not_past()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  business_now timestamp without time zone :=
    timezone('Asia/Manila', clock_timestamp());
  now_minutes numeric;
  start_minutes integer;
  schedule_changed boolean;
begin
  if new.type = 'Walk-in' then
    return new;
  end if;

  schedule_changed := tg_op = 'INSERT'
    or new.reservation_date is distinct from old.reservation_date
    or new.reservation_time is distinct from old.reservation_time
    or new.type is distinct from old.type;

  if schedule_changed and new.reservation_date = business_now::date then
    start_minutes := public.reservation_time_to_minutes(new.reservation_time);
    now_minutes :=
      extract(hour from business_now) * 60
      + extract(minute from business_now)
      + extract(second from business_now) / 60;

    if start_minutes is not null and start_minutes < now_minutes then
      raise exception 'Reservation start time has already passed'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_reservation_start_not_past()
  from public, anon, authenticated;

drop trigger if exists enforce_reservation_start_not_past on public.reservations;
create trigger enforce_reservation_start_not_past
  before insert or update on public.reservations
  for each row execute function public.enforce_reservation_start_not_past();

commit;
