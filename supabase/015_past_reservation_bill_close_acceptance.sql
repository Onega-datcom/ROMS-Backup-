-- Acceptance checks for closing a bill linked to a past reservation.
-- Run as the database owner after migrations 013, 014, and 015.
-- The test shift, reservation, bill, and payment are rolled back. The fixture
-- is moved to yesterday without an authenticated actor because app users
-- cannot create or move reservations to past dates.
begin;

do $$
declare
  receptionist_id uuid;
  shift_result jsonb;
  save_result jsonb;
  close_result jsonb;
  reservation_id_value text := 'PAST-CLOSE-' || gen_random_uuid()::text;
  unauthorized_reservation_id text := 'PAST-GUARD-' || gen_random_uuid()::text;
  bill_id_value text;
  due_value numeric(12,2);
  reservation_status text;
  reservation_covers integer;
  bill_status text;
  bill_balance numeric(12,2);
  unauthorized_update_rejected boolean := false;
begin
  select p.id into receptionist_id
  from public.profiles p
  where p.role = 'Receptionist'
    and not exists (
      select 1 from public.pos_shifts s
      where s.opened_by = p.id and s.status = 'Open'
    )
  order by p.id
  limit 1;
  if receptionist_id is null then
    raise exception 'Prerequisite: a Receptionist without an open shift is required.';
  end if;

  perform set_config('request.jwt.claim.sub', receptionist_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  shift_result := public.pos_open_shift(100, 'Past reservation close acceptance');
  if shift_result->'shift'->>'id' is null then
    raise exception 'FAIL: could not open the acceptance cashier shift.';
  end if;

  insert into public.reservations (
    id, name, reservation_date, reservation_time, guests, type,
    adults, senior_pwd_count, children, status, seated_at, actual_covers,
    source, created_by
  ) values (
    reservation_id_value, 'Past bill-close acceptance', current_date,
    '12:00 PM', 1, 'Walk-in', 1, 0, 0, 'Seated',
    now(), 1, 'Walk-in', receptionist_id
  );

  perform set_config('request.jwt.claim.sub', '', true);
  update public.reservations
  set reservation_date = current_date - 1
  where id = reservation_id_value;
  perform set_config('request.jwt.claim.sub', receptionist_id::text, true);

  save_result := public.pos_save_bill_phase3(
    null, 'Past bill-close acceptance', '', reservation_id_value,
    1, 0, 0, 0, null, '', '[]'::jsonb,
    gen_random_uuid()::text, null, false
  );
  bill_id_value := save_result->'bill'->>'id';
  due_value := (save_result->'bill'->>'balance_due')::numeric;
  if bill_id_value is null or due_value <= 0 then
    raise exception 'FAIL: acceptance bill was not created with a positive balance.';
  end if;

  close_result := public.pos_close_bill_phase3(
    bill_id_value, due_value, gen_random_uuid()::text
  );
  select status, balance_due into bill_status, bill_balance
  from public.pos_bills where id = bill_id_value;
  select status, actual_covers into reservation_status, reservation_covers
  from public.reservations where id = reservation_id_value;
  if close_result->>'already_closed' = 'true'
     or bill_status <> 'Closed'
     or bill_balance <> 0
     or reservation_status <> 'Completed'
     or reservation_covers <> 1 then
    raise exception 'FAIL: past reservation bill close did not settle the bill and complete the reservation.';
  end if;

  insert into public.reservations (
    id, name, reservation_date, reservation_time, guests, type,
    adults, senior_pwd_count, children, status, seated_at, actual_covers,
    source, created_by
  ) values (
    unauthorized_reservation_id, 'Past direct-update guard acceptance',
    current_date, '1:00 PM', 1, 'Walk-in', 1, 0, 0, 'Seated',
    now(), 1, 'Walk-in', receptionist_id
  );
  perform set_config('request.jwt.claim.sub', '', true);
  update public.reservations
  set reservation_date = current_date - 1
  where id = unauthorized_reservation_id;
  perform set_config('request.jwt.claim.sub', receptionist_id::text, true);

  begin
    update public.reservations
    set status = 'Completed', completed_at = now(), actual_covers = 1
    where id = unauthorized_reservation_id;
    raise exception 'FAIL: Receptionist directly completed an unrelated past reservation.';
  exception when insufficient_privilege then
    unauthorized_update_rejected := true;
  end;
  if not unauthorized_update_rejected then
    raise exception 'FAIL: past reservation direct-update guard did not reject the write.';
  end if;

  raise notice 'PASS: settled past-reservation bill completed; unrelated direct historical update remained blocked.';
end;
$$;

rollback;
