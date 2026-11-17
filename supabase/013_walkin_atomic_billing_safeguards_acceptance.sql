-- Acceptance checks for atomic Walk-in billing and package safeguards.
-- Run as the database owner after migrations 011, 012, 013, and 014.
-- All test rows and temporary catalog changes are rolled back.

begin;

do $$
declare
  rpc_signature regprocedure :=
    'public.pos_seat_and_open_walkin(text,text,text,date,text,text,integer,integer,integer,text,text)'::regprocedure;
begin
  if not has_function_privilege('authenticated', rpc_signature, 'EXECUTE')
    or has_function_privilege('anon', rpc_signature, 'EXECUTE') then
    raise exception 'FAIL: atomic Walk-in RPC execute grants are not authenticated-only.';
  end if;
  if not (
    select c.relrowsecurity
    from pg_class c
    where c.oid = 'public.pos_walkin_package_overrides'::regclass
  ) then
    raise exception 'FAIL: package override audit table does not have RLS enabled.';
  end if;
  if not (
    select c.relrowsecurity
    from pg_class c
    where c.oid = 'public.pos_walkin_bill_requests'::regclass
  )
    or has_table_privilege('authenticated', 'public.pos_walkin_bill_requests', 'SELECT')
    or exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = 'pos_walkin_bill_requests'
    ) then
    raise exception 'FAIL: idempotency records are not private from authenticated users.';
  end if;
  if (
    select count(*) from pg_policies
    where schemaname = 'public'
      and tablename = 'pos_walkin_package_overrides'
  ) <> 1
    or not exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and tablename = 'pos_walkin_package_overrides'
        and policyname = 'pos_walkin_package_overrides_manager_admin_select'
        and cmd = 'SELECT'
        and roles @> array['authenticated']::name[]
        and qual ilike '%Administrator%'
        and qual ilike '%Manager%'
    ) then
    raise exception 'FAIL: package override audit policies do not match Manager/Administrator read access.';
  end if;
end;
$$;

do $$
declare
  receptionist_id uuid;
  manager_id uuid;
  receptionist_shift_id text;
  manager_shift_id text;
  receptionist_table_id text := 'W13-' || gen_random_uuid()::text;
  manager_table_id text := 'W13-' || gen_random_uuid()::text;
  failure_table_id text := 'W13-' || gen_random_uuid()::text;
  undersized_table_id text := 'W13-' || gen_random_uuid()::text;
  receptionist_key text := 'W13-REC-' || gen_random_uuid()::text;
  manager_key text := 'W13-MGR-' || gen_random_uuid()::text;
  failure_key text := 'W13-FAIL-' || gen_random_uuid()::text;
  receptionist_result jsonb;
  retry_result jsonb;
  manager_result jsonb;
  failure_rejected boolean := false;
  duplicate_bill_rejected boolean := false;
  zero_guests_rejected boolean := false;
  negative_count_rejected boolean := false;
  decimal_count_rejected boolean := false;
  undersized_table_rejected boolean := false;
  receptionist_override_rejected boolean := false;
  receptionist_line_rejected boolean := false;
  missing_reason_rejected boolean := false;
  reservation_id text;
  manager_reservation_id text;
  bill_id text;
  manager_bill_id text;
  leftover_id text;
  leftover_price numeric(12,2);
  v_package_item_id text;
  v_package_tier_id text;
  audit_count integer;
begin
  select p.id into receptionist_id
  from public.profiles p
  where p.role = 'Receptionist'
    and not exists (
      select 1 from public.pos_shifts s
      where s.opened_by = p.id and s.status = 'Open'
    )
  order by p.id limit 1;
  select p.id into manager_id
  from public.profiles p
  where p.role in ('Manager', 'Administrator')
    and not exists (
      select 1 from public.pos_shifts s
      where s.opened_by = p.id and s.status = 'Open'
    )
    and p.id is distinct from receptionist_id
  order by p.id limit 1;
  if receptionist_id is null or manager_id is null then
    raise exception 'Prerequisite: a Receptionist and a Manager/Administrator without open shifts are required.';
  end if;

  select id, unit_price into leftover_id, leftover_price
  from public.pos_charge_items
  where code = 'LEFTOVER' and is_active and type in ('food', 'non_food', 'other')
    and not is_package
  order by id limit 1;
  select id into v_package_item_id
  from public.pos_charge_items
  where code = 'PACKAGE' and type = 'package' and is_package and is_active
  order by id limit 1;
  select id into v_package_tier_id
  from public.pos_package_tiers
  where code = 'ADULT' and is_active
  order by id limit 1;
  if leftover_id is null or v_package_item_id is null or v_package_tier_id is null then
    raise exception 'Prerequisite: active LEFTOVER, PACKAGE, and ADULT catalog rows are required.';
  end if;
  if leftover_price <> 200 then
    raise exception 'Expected the active LEFTOVER catalog price to be 200.00; found %.', leftover_price;
  end if;

  insert into public.restaurant_tables (id, seats, status, x, y, guest)
  values
    (receptionist_table_id, 7, 'Available', 0, 0, ''),
    (manager_table_id, 7, 'Available', 0, 0, ''),
    (failure_table_id, 7, 'Available', 0, 0, ''),
    (undersized_table_id, 6, 'Available', 0, 0, '');

  perform set_config('request.jwt.claim.sub', receptionist_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  receptionist_result := public.pos_open_shift(500, 'Phase 13 acceptance');
  receptionist_shift_id := receptionist_result->'shift'->>'id';

  begin
    perform public.pos_seat_and_open_walkin(
      'Phase 13 zero-guest test', '', '', current_date, '11:00 AM',
      receptionist_table_id, 0, 0, 0, '', gen_random_uuid()::text
    );
    raise exception 'FAIL: a zero-guest Walk-in was accepted.';
  exception when sqlstate '22023' then
    zero_guests_rejected := true;
  end;
  begin
    perform public.pos_seat_and_open_walkin(
      'Phase 13 negative-count test', '', '', current_date, '11:00 AM',
      receptionist_table_id, -1, 1, 0, '', gen_random_uuid()::text
    );
    raise exception 'FAIL: a negative Walk-in count was accepted.';
  exception when sqlstate '22023' then
    negative_count_rejected := true;
  end;
  if not zero_guests_rejected or not negative_count_rejected then
    raise exception 'FAIL: zero or negative guest counts were not rejected.';
  end if;
  begin
    execute format(
      'select public.pos_seat_and_open_walkin(%L, %L, %L, current_date, %L, %L, 0.5::numeric, 0, 1, %L, %L)',
      'Phase 13 decimal-count test', '', '', '11:00 AM',
      receptionist_table_id, '', gen_random_uuid()::text
    );
    raise exception 'FAIL: a decimal Walk-in count was accepted.';
  exception
    when undefined_function or invalid_text_representation then
      decimal_count_rejected := true;
  end;
  if not decimal_count_rejected then
    raise exception 'FAIL: decimal guest counts were not rejected by the integer RPC contract.';
  end if;
  begin
    perform public.pos_seat_and_open_walkin(
      'Phase 13 undersized-table test', '', '', current_date, '11:00 AM',
      undersized_table_id, 4, 1, 2, '', gen_random_uuid()::text
    );
    raise exception 'FAIL: a seven-guest Walk-in was seated at a six-seat table.';
  exception when check_violation then
    undersized_table_rejected := true;
  end;
  if not undersized_table_rejected then
    raise exception 'FAIL: Walk-in table capacity was not enforced.';
  end if;

  receptionist_result := public.pos_seat_and_open_walkin(
    'Phase 13 Receptionist test', '', '', current_date, '12:00 PM',
    receptionist_table_id, 4, 1, 2, '', receptionist_key
  );
  reservation_id := receptionist_result->'reservation'->>'id';
  bill_id := receptionist_result->'bill'->>'id';
  if reservation_id is null or bill_id is null
    or (receptionist_result->'reservation'->>'status') <> 'Seated'
    or (receptionist_result->'reservation'->>'guests')::integer <> 7
    or (receptionist_result->'reservation'->>'adults')::integer <> 4
    or (receptionist_result->'reservation'->>'senior_pwd_count')::integer <> 1
    or (receptionist_result->'reservation'->>'children')::integer <> 2
    or (receptionist_result->'bill'->>'adult_count')::integer <> 4
    or (receptionist_result->'bill'->>'senior_count')::integer <> 1
    or (receptionist_result->'bill'->>'kids_count')::integer <> 2
    or (receptionist_result->'bill'->>'subtotal')::numeric <> 2606 then
    raise exception 'FAIL: Walk-in and Open bill did not preserve 4/1/2 counts and the 2,606 subtotal.';
  end if;

  retry_result := public.pos_seat_and_open_walkin(
    'Phase 13 Receptionist test', '', '', current_date, '12:00 PM',
    receptionist_table_id, 4, 1, 2, '', receptionist_key
  );
  if (retry_result->>'already_created')::boolean is not true
    or retry_result->'reservation'->>'id' <> reservation_id
    or retry_result->'bill'->>'id' <> bill_id then
    raise exception 'FAIL: retry with the same cashier/key did not return the same reservation and bill.';
  end if;

  perform public.pos_record_reservation_deposit(
    reservation_id, 500, 'Phase 13 acceptance deposit', gen_random_uuid()::text
  );
  receptionist_result := public.pos_save_bill_phase3(
    bill_id, 'Phase 13 Receptionist test', '', reservation_id,
    4, 1, 2, 0, null, '',
    jsonb_build_array(jsonb_build_object('charge_item_id', leftover_id, 'quantity', 1)),
    gen_random_uuid()::text, receptionist_table_id, false
  );
  if (receptionist_result->'bill'->>'subtotal')::numeric <> 2806 then
    raise exception 'FAIL: catalog leftover item did not add 200 to the 2,606 bill.';
  end if;

  begin
    perform public.pos_save_bill_phase3(
      null, 'Duplicate open bill', '', reservation_id,
      4, 1, 2, 0, null, '', '[]'::jsonb,
      gen_random_uuid()::text, receptionist_table_id, false
    );
    raise exception 'FAIL: a second open bill for this reservation was accepted.';
  exception when unique_violation then
    duplicate_bill_rejected := true;
  end;
  if not duplicate_bill_rejected then
    raise exception 'FAIL: one-open-bill-per-reservation rule was not enforced.';
  end if;

  begin
    update public.reservations
    set package_charge_item_id = v_package_item_id,
        package_tier_id = v_package_tier_id,
        package_pax_count = 2,
        package_override_reason = 'Unauthorized Receptionist attempt'
    where id = reservation_id;
    raise exception 'FAIL: Receptionist attached an event package to a Walk-in.';
  exception when insufficient_privilege then
    receptionist_override_rejected := true;
  end;
  begin
    insert into public.pos_bill_lines (
      id, bill_id, charge_item_id, package_tier_id, description,
      quantity, unit_price, line_type, food_revenue_amount,
      non_food_revenue_amount, is_food_revenue_snapshot, created_by
    ) values (
      gen_random_uuid()::text, bill_id, v_package_item_id, v_package_tier_id,
      'Unauthorized package line', 1, 449, 'package', 449, 0, true, receptionist_id
    );
    raise exception 'FAIL: Receptionist directly inserted a Walk-in package line.';
  exception when insufficient_privilege then
    receptionist_line_rejected := true;
  end;
  if not receptionist_override_rejected or not receptionist_line_rejected then
    raise exception 'FAIL: Receptionist package override protection did not reject direct writes.';
  end if;

  receptionist_result := public.pos_close_bill_phase3(
    bill_id, 2500, gen_random_uuid()::text
  );
  if (receptionist_result->>'deposit_applied')::numeric <> 500
    or (receptionist_result->'payment'->>'amount')::numeric <> 2306
    or (receptionist_result->'payment'->>'change_amount')::numeric <> 194 then
    raise exception 'FAIL: expected deposit/payment/change was not 500 / 2,306 / 194.';
  end if;

  -- The bill-stage failure is forced by deactivating the Adult POS rate within
  -- a nested transaction. The caught error rolls back both that change and the
  -- attempted reservation insert.
  perform set_config('request.jwt.claim.sub', receptionist_id::text, true);
  begin
    update public.pos_package_tiers set is_active = false where id = v_package_tier_id;
    perform public.pos_seat_and_open_walkin(
      'Phase 13 forced bill failure', '', '', current_date, '1:00 PM',
      failure_table_id, 1, 0, 0, '', failure_key
    );
    raise exception 'FAIL: the forced bill-stage failure did not occur.';
  exception when sqlstate '55000' then
    failure_rejected := true;
  end;
  if not failure_rejected
    or exists (
      select 1 from public.reservations
      where name = 'Phase 13 forced bill failure' and created_by = receptionist_id
    )
    or exists (
      select 1 from public.pos_walkin_bill_requests
      where cashier_id = receptionist_id and idempotency_key = failure_key
    )
    or exists (
      select 1 from public.pos_bills
      where customer_name = 'Phase 13 forced bill failure' and created_by = receptionist_id
    )
    or (select status from public.restaurant_tables where id = failure_table_id) <> 'Available' then
    raise exception 'FAIL: failed bill creation left a reservation, request row, or occupied table behind.';
  end if;

  -- A caller without their own open shift must not seat a Walk-in or create a bill.
  perform set_config('request.jwt.claim.sub', manager_id::text, true);
  begin
    perform public.pos_seat_and_open_walkin(
      'Phase 13 no-shift failure', '', '', current_date, '2:00 PM',
      failure_table_id, 1, 0, 0, '', failure_key
    );
    raise exception 'FAIL: a Manager without an open shift seated a Walk-in.';
  exception when sqlstate '55000' then
    null;
  end;
  if exists (
    select 1 from public.reservations
    where name = 'Phase 13 no-shift failure' and created_by = manager_id
  ) then
    raise exception 'FAIL: no-shift request left a reservation behind.';
  end if;

  manager_result := public.pos_open_shift(500, 'Phase 13 manager acceptance');
  manager_shift_id := manager_result->'shift'->>'id';
  manager_result := public.pos_seat_and_open_walkin(
    'Phase 13 Manager package test', '', '', current_date, '3:00 PM',
    manager_table_id, 1, 0, 0, '', manager_key
  );
  manager_reservation_id := manager_result->'reservation'->>'id';
  manager_bill_id := manager_result->'bill'->>'id';

  update public.reservations
  set package_charge_item_id = v_package_item_id,
      package_tier_id = v_package_tier_id,
      package_pax_count = 2,
      package_override_reason = 'Client-approved event package'
  where id = manager_reservation_id;
  select count(*) into audit_count
  from public.pos_walkin_package_overrides as override_log
  where override_log.reservation_id = manager_reservation_id
    and override_log.overridden_by = manager_id
    and override_log.reason = 'Client-approved event package';
  if audit_count <> 1 then
    raise exception 'FAIL: Manager package override audit row was not recorded.';
  end if;

  begin
    update public.reservations
    set package_pax_count = 3, package_override_reason = ''
    where id = manager_reservation_id;
    raise exception 'FAIL: Manager package change without a reason was accepted.';
  exception when sqlstate '22023' then
    missing_reason_rejected := true;
  end;
  if not missing_reason_rejected then
    raise exception 'FAIL: required package override reason was not enforced.';
  end if;

  manager_result := public.pos_save_bill_phase3(
    manager_bill_id, 'Phase 13 Manager package test', '', manager_reservation_id,
    1, 0, 0, 0, null, '', '[]'::jsonb, gen_random_uuid()::text,
    manager_table_id, false
  );
  if not exists (
    select 1 from public.pos_bill_lines as package_line
    where package_line.bill_id = manager_bill_id
      and package_line.line_type = 'package'
      and not package_line.is_voided
      and package_line.charge_item_id = v_package_item_id
      and package_line.package_tier_id = v_package_tier_id
  ) then
    raise exception 'FAIL: authorized Manager package did not produce its bill line.';
  end if;

  raise notice 'PASS: zero/negative/decimal/table-capacity rejection, atomic counts/subtotal, idempotent retry, duplicate bill block, package role/reason/audit, no-shift denial, forced-failure rollback, deposit/leftover/payment/change.';
  raise notice 'Receptionist shift: %, Manager shift: %.', receptionist_shift_id, manager_shift_id;
end;
$$;

rollback;
