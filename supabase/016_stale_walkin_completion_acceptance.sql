-- Acceptance checks for audited stale Walk-in completion.
-- Run as the database owner after migrations 013 through 019.
-- Test rows are rolled back; the production date guard stays enabled.

begin;

do $$
declare
  rpc_signature regprocedure :=
    'public.pos_resolve_stale_booking(text,text,text,boolean,text,text,text)'::regprocedure;
  legacy_rpc_signature regprocedure :=
    'public.pos_resolve_stale_walkin(text,text)'::regprocedure;
  manager_id uuid;
  receptionist_id uuid;
  business_date_value date := timezone('Asia/Manila', statement_timestamp())::date;
  reservation_id_value text := 'STALE-WI-' || gen_random_uuid()::text;
  same_day_reservation_id text := 'STALE-TODAY-' || gen_random_uuid()::text;
  non_walkin_reservation_id text := 'STALE-BOOKING-' || gen_random_uuid()::text;
  open_bill_reservation_id text := 'STALE-OPEN-' || gen_random_uuid()::text;
  held_deposit_reservation_id text := 'STALE-DEP-' || gen_random_uuid()::text;
  direct_update_reservation_id text := 'STALE-DIRECT-' || gen_random_uuid()::text;
  table_id_value text := 'ST-' || substr(gen_random_uuid()::text, 1, 16);
  result jsonb;
  reservation_status text;
  reservation_reason text;
  table_status text;
  bill_status text;
  bill_balance numeric(12,2);
  deposit_status text;
  reservation_type text;
  audit_count integer;
  same_day_blocked boolean := false;
  non_walkin_blocked boolean := false;
  open_bill_blocked boolean := false;
  direct_update_blocked boolean := false;
  receptionist_blocked boolean := false;
  reason_value text := 'Guests confirmed departed; resolving stale table occupancy.';
  deposit_reason_value text := 'Held deposit forfeited under the manager-approved resolution.';
  reservation_idempotency_key text := gen_random_uuid()::text;
begin
  if not has_function_privilege('authenticated', rpc_signature, 'EXECUTE')
     or has_function_privilege('anon', rpc_signature, 'EXECUTE') then
    raise exception 'FAIL: stale-booking RPC grants are not authenticated-only.';
  end if;
  if has_function_privilege('authenticated', legacy_rpc_signature, 'EXECUTE') then
    raise exception 'FAIL: the retired Walk-in resolver remains executable.';
  end if;

  select p.id into manager_id
  from public.profiles p
  where p.role in ('Manager', 'Administrator')
  order by case when p.role = 'Manager' then 0 else 1 end, p.id
  limit 1;
  select p.id into receptionist_id
  from public.profiles p
  where p.role = 'Receptionist'
  order by p.id
  limit 1;
  if manager_id is null or receptionist_id is null then
    raise exception 'Prerequisite: a Manager/Administrator and Receptionist profile are required.';
  end if;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', manager_id::text, true);

  insert into public.restaurant_tables (id, seats, status, x, y, guest)
  values (table_id_value, 4, 'Available', 0, 0, '');
  insert into public.reservations (
    id, name, reservation_date, reservation_time, guests, type,
    adults, senior_pwd_count, children, status, seated_at, actual_covers,
    table_id, source, created_by
  ) values (
    reservation_id_value, 'Stale Walk-in acceptance', business_date_value,
    '12:00 PM', 1, 'Walk-in', 1, 0, 0, 'Seated', now(), 1,
    table_id_value, 'Walk-in', manager_id
  );
  perform set_config('request.jwt.claim.sub', '', true);
  update public.reservations
  set reservation_date = business_date_value - 1
  where id = reservation_id_value;
  perform set_config('request.jwt.claim.sub', manager_id::text, true);

  result := public.pos_resolve_stale_booking(
    reservation_id_value, 'close_without_charge', reason_value, true,
    null, null, reservation_idempotency_key
  );
  select status, last_correction_reason
    into reservation_status, reservation_reason
  from public.reservations
  where id = reservation_id_value;
  select status into table_status
  from public.restaurant_tables
  where id = table_id_value;
  select count(*) into audit_count
  from public.audit_logs
  where actor_id = manager_id
    and table_name = 'reservations'
    and record_id = reservation_id_value
    and action = 'UPDATE';
  if result->>'status' <> 'Completed'
     or result->>'already_resolved' <> 'false'
     or reservation_status <> 'Completed'
     or reservation_reason <> reason_value
     or table_status <> 'Needs cleaning'
     or audit_count <> 1 then
    raise exception 'FAIL: stale Walk-in was not completed with its reason, audit row, and cleaning state.';
  end if;

  result := public.pos_resolve_stale_booking(
    reservation_id_value, 'close_without_charge', reason_value, true,
    null, null, reservation_idempotency_key
  );
  if result->>'already_resolved' <> 'true' then
    raise exception 'FAIL: retrying completion was not idempotent.';
  end if;

  insert into public.reservations (
    id, name, reservation_date, reservation_time, guests, type,
    adults, senior_pwd_count, children, status, seated_at, actual_covers,
    source, created_by
  ) values (
    same_day_reservation_id, 'Same-day completion blocker acceptance',
    business_date_value, '12:30 PM', 1, 'Walk-in', 1, 0, 0, 'Seated', now(), 1,
    'Walk-in', manager_id
  );
  begin
    perform public.pos_resolve_stale_booking(
      same_day_reservation_id, 'close_without_charge',
      'Same-day visits must remain active.', true,
      null, null, gen_random_uuid()::text
    );
    raise exception 'FAIL: stale completion accepted a same-day Walk-in.';
  exception when sqlstate '55000' then
    same_day_blocked := true;
  end;
  select status into reservation_status
  from public.reservations where id = same_day_reservation_id;
  if not same_day_blocked or reservation_status <> 'Seated' then
    raise exception 'FAIL: same-day Walk-in was not protected.';
  end if;

  -- Start tomorrow so migration 017 cannot reject setup after the 1:30 PM slot.
  insert into public.reservations (
    id, name, phone, reservation_date, reservation_time, guests, type,
    adults, senior_pwd_count, children, status, seated_at, actual_covers,
    source, created_by
  ) values (
    non_walkin_reservation_id, 'Past reservation type blocker acceptance',
    '09171234567', business_date_value + 1, '1:30 PM', 1, 'Reservation', 1, 0, 0,
    'Pending', null, null,
    'Phone', manager_id
  );
  update public.reservations
  set status = 'Confirmed'
  where id = non_walkin_reservation_id;
  update public.reservations
  set status = 'Seated',
      seated_at = now(),
      actual_covers = 1
  where id = non_walkin_reservation_id;
  perform set_config('request.jwt.claim.sub', '', true);
  update public.reservations
  set reservation_date = business_date_value - 1
  where id = non_walkin_reservation_id;
  perform set_config('request.jwt.claim.sub', manager_id::text, true);
  begin
    perform public.pos_resolve_stale_walkin(
      non_walkin_reservation_id, 'Legacy entry point must be retired.'
    );
    raise exception 'FAIL: legacy Walk-in RPC was still executable.';
  exception
    when sqlstate '0A000' then
      non_walkin_blocked := true;
    when insufficient_privilege then
      non_walkin_blocked := true;
  end;
  result := public.pos_resolve_stale_booking(
    non_walkin_reservation_id, 'close_without_charge',
    'Past reservation is a verified test record with no meal served.',
    true, null, null, gen_random_uuid()::text
  );
  select status, type into reservation_status, reservation_type
  from public.reservations where id = non_walkin_reservation_id;
  if not non_walkin_blocked
     or result->>'status' <> 'Completed'
     or reservation_status <> 'Completed'
     or reservation_type <> 'Reservation' then
    raise exception 'FAIL: unified resolver did not accept a valid past Reservation, or legacy RPC remained active.';
  end if;

  insert into public.reservations (
    id, name, reservation_date, reservation_time, guests, type,
    adults, senior_pwd_count, children, status, seated_at, actual_covers,
    source, created_by
  ) values (
    open_bill_reservation_id, 'Open bill blocker acceptance', business_date_value,
    '1:00 PM', 1, 'Walk-in', 1, 0, 0, 'Seated', now(), 1,
    'Walk-in', manager_id
  );
  perform set_config('request.jwt.claim.sub', '', true);
  update public.reservations
  set reservation_date = business_date_value - 1
  where id = open_bill_reservation_id;
  perform set_config('request.jwt.claim.sub', manager_id::text, true);
  insert into public.pos_bills (
    bill_number, reservation_id, customer_name, status, balance_due
  ) values (
    'STALE-' || gen_random_uuid()::text, open_bill_reservation_id,
    'Open bill blocker acceptance', 'Open', 100
  );

  begin
    perform public.pos_resolve_stale_booking(
      open_bill_reservation_id, 'close_without_charge',
      'Open bill must remain protected.', true,
      null, null, gen_random_uuid()::text
    );
    raise exception 'FAIL: stale completion bypassed an open bill.';
  exception when sqlstate '55000' then
    open_bill_blocked := true;
  end;
  select status into reservation_status
  from public.reservations where id = open_bill_reservation_id;
  select b.status, b.balance_due into bill_status, bill_balance
  from public.pos_bills b where b.reservation_id = open_bill_reservation_id;
  if not open_bill_blocked
     or reservation_status <> 'Seated'
     or bill_status <> 'Open'
     or bill_balance <> 100 then
    raise exception 'FAIL: stale completion changed a reservation or financial record with an open bill.';
  end if;

  insert into public.reservations (
    id, name, reservation_date, reservation_time, guests, type,
    adults, senior_pwd_count, children, status, seated_at, actual_covers,
    source, created_by
  ) values (
    held_deposit_reservation_id, 'Held deposit blocker acceptance', business_date_value,
    '2:00 PM', 1, 'Walk-in', 1, 0, 0, 'Seated', now(), 1,
    'Walk-in', manager_id
  );
  perform set_config('request.jwt.claim.sub', '', true);
  update public.reservations
  set reservation_date = business_date_value - 1
  where id = held_deposit_reservation_id;
  perform set_config('request.jwt.claim.sub', manager_id::text, true);
  insert into public.pos_reservation_deposits (
    id, reservation_id, amount, payment_method, status, created_by
  ) values (
    gen_random_uuid()::text, held_deposit_reservation_id, 100,
    'cash', 'Held', manager_id
  );

  result := public.pos_resolve_stale_booking(
    held_deposit_reservation_id, 'close_without_charge',
    'Past Walk-in is a verified test record; no meal was served.',
    true, 'forfeit', deposit_reason_value, gen_random_uuid()::text
  );
  select status into reservation_status
  from public.reservations where id = held_deposit_reservation_id;
  select status into deposit_status
  from public.pos_reservation_deposits
  where reservation_id = held_deposit_reservation_id;
  if result->>'status' <> 'Completed'
     or reservation_status <> 'Completed'
     or deposit_status <> 'Forfeited' then
    raise exception 'FAIL: unified resolver did not complete the Walk-in and settle its held deposit.';
  end if;

  insert into public.reservations (
    id, name, reservation_date, reservation_time, guests, type,
    adults, senior_pwd_count, children, status, seated_at, actual_covers,
    source, created_by
  ) values (
    direct_update_reservation_id, 'Direct update guard acceptance', business_date_value,
    '3:00 PM', 1, 'Walk-in', 1, 0, 0, 'Seated', now(), 1,
    'Walk-in', manager_id
  );
  perform set_config('request.jwt.claim.sub', '', true);
  update public.reservations
  set reservation_date = business_date_value - 1
  where id = direct_update_reservation_id;
  perform set_config('request.jwt.claim.sub', manager_id::text, true);
  begin
    update public.reservations
    set status = 'Completed',
        completed_at = now(),
        last_correction_reason = 'Direct update must remain blocked.'
    where id = direct_update_reservation_id;
    raise exception 'FAIL: direct historical status update bypassed the RPC.';
  exception when insufficient_privilege then
    direct_update_blocked := true;
  end;
  if not direct_update_blocked then
    raise exception 'FAIL: direct historical status update was not blocked.';
  end if;

  perform set_config('request.jwt.claim.sub', receptionist_id::text, true);
  begin
    perform public.pos_resolve_stale_booking(
      direct_update_reservation_id, 'close_without_charge',
      'Receptionist must not complete history.', true,
      null, null, gen_random_uuid()::text
    );
    raise exception 'FAIL: Receptionist was allowed to resolve a stale Walk-in.';
  exception when insufficient_privilege then
    receptionist_blocked := true;
  end;
  if not receptionist_blocked then
    raise exception 'FAIL: stale completion did not enforce the Manager/Administrator role.';
  end if;

  raise notice 'PASS: unified stale-booking resolution handled Walk-ins and Reservations; date/status scope, idempotency, bill/deposit handling, direct-update denial, and role restrictions passed.';
end;
$$;

rollback;
