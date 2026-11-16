-- Acceptance checks for same-day past reservation-time protection.
-- Run as the database owner after migration 017. All fixture rows are rolled back.

begin;

do $$
declare
  business_now timestamp without time zone :=
    timezone('Asia/Manila', clock_timestamp());
  now_minutes numeric;
  past_minutes integer;
  past_time text;
  future_reservation_id text := 'PAST-TIME-' || gen_random_uuid()::text;
  insert_blocked boolean := false;
  update_blocked boolean := false;
begin
  now_minutes :=
    extract(hour from business_now) * 60
    + extract(minute from business_now)
    + extract(second from business_now) / 60;
  if now_minutes <= 10 * 60 then
    raise exception 'Prerequisite: run this acceptance script after 10:00 AM Asia/Manila.';
  end if;

  past_minutes := greatest(
    10 * 60,
    least(19 * 60, floor((now_minutes - 0.000001) / 30)::integer * 30)
  );
  past_time := to_char(
    timestamp '2000-01-01' + make_interval(mins => past_minutes),
    'FMHH12:MI AM'
  );

  begin
    insert into public.reservations (
      id, name, phone, reservation_date, reservation_time, guests, type,
      adults, senior_pwd_count, children, status, source
    ) values (
      'PAST-INSERT-' || gen_random_uuid()::text,
      'Past-time acceptance insert', '09170000001',
      business_now::date, past_time, 1, 'Reservation',
      1, 0, 0, 'Pending', 'Phone'
    );
    raise exception 'FAIL: a same-day reservation with a past start time was accepted.';
  exception when check_violation then
    if sqlerrm not ilike '%start time has already passed%' then
      raise;
    end if;
    insert_blocked := true;
  end;
  if not insert_blocked then
    raise exception 'FAIL: same-day past reservation insert was not rejected.';
  end if;

  insert into public.reservations (
    id, name, phone, reservation_date, reservation_time, guests, type,
    adults, senior_pwd_count, children, status, source
  ) values (
    future_reservation_id, 'Past-time acceptance update', '09170000002',
    business_now::date + 1, past_time, 1, 'Reservation',
    1, 0, 0, 'Pending', 'Phone'
  );

  begin
    update public.reservations
    set reservation_date = business_now::date
    where id = future_reservation_id;
    raise exception 'FAIL: moving a reservation to a past same-day start was accepted.';
  exception when check_violation then
    if sqlerrm not ilike '%start time has already passed%' then
      raise;
    end if;
    update_blocked := true;
  end;
  if not update_blocked
     or not exists (
       select 1
       from public.reservations
       where id = future_reservation_id
         and reservation_date = business_now::date + 1
     ) then
    raise exception 'FAIL: same-day past reservation rescheduling was not rejected.';
  end if;
end;
$$;

rollback;
