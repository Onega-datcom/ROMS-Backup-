-- Acceptance checks for 010_pos_single_source_security.sql.
-- Run as the database owner. The final ROLLBACK removes all generated test rows.
-- Also run 008_pos_phase3_acceptance.sql to exercise bill save/close/void,
-- deposit, and seated-reservation RPC flows; browser printing needs manual QA.

begin;

select set_config(
  'costtrack.acceptance.rec_a',
  coalesce(
    (select id::text from public.profiles where role = 'Receptionist' order by id offset 0 limit 1),
    ''
  ),
  true
);
select set_config(
  'costtrack.acceptance.rec_b',
  coalesce(
    (select id::text from public.profiles where role = 'Receptionist' order by id offset 1 limit 1),
    ''
  ),
  true
);
select set_config(
  'costtrack.acceptance.manager',
  coalesce(
    (select id::text from public.profiles where role = 'Manager' order by id limit 1),
    ''
  ),
  true
);
select set_config(
  'costtrack.acceptance.admin',
  coalesce(
    (select id::text from public.profiles where role = 'Administrator' order by id limit 1),
    ''
  ),
  true
);
select set_config('costtrack.acceptance.bill_a', gen_random_uuid()::text, true);
select set_config('costtrack.acceptance.bill_b', gen_random_uuid()::text, true);

do $$
begin
  if nullif(btrim(current_setting('costtrack.acceptance.rec_a', true)), '') is null then
    raise exception 'Acceptance prerequisite missing: at least one Receptionist profile is required.';
  end if;
  if nullif(btrim(current_setting('costtrack.acceptance.rec_b', true)), '') is null then
    raise exception 'Acceptance prerequisite missing: at least two Receptionist profiles are required.';
  end if;
  if nullif(btrim(current_setting('costtrack.acceptance.manager', true)), '') is null then
    raise exception 'Acceptance prerequisite missing: a Manager profile is required.';
  end if;
  if nullif(btrim(current_setting('costtrack.acceptance.admin', true)), '') is null then
    raise exception 'Acceptance prerequisite missing: an Administrator profile is required.';
  end if;
  if current_setting('costtrack.acceptance.rec_a') =
    current_setting('costtrack.acceptance.rec_b') then
    raise exception 'Acceptance prerequisite failed: Receptionist A and B must be distinct.';
  end if;
end;
$$;

insert into public.pos_bills
  (id, bill_number, customer_name, status, created_by)
values
  (current_setting('costtrack.acceptance.bill_a'),
   current_setting('costtrack.acceptance.bill_a'), 'Policy test A', 'Open',
   current_setting('costtrack.acceptance.rec_a')::uuid),
  (current_setting('costtrack.acceptance.bill_b'),
   current_setting('costtrack.acceptance.bill_b'), 'Policy test B', 'Open',
   current_setting('costtrack.acceptance.rec_b')::uuid);

insert into public.pos_bill_lines
  (id, bill_id, description, quantity, unit_price, created_by)
values
  (gen_random_uuid()::text, current_setting('costtrack.acceptance.bill_a'),
   'Policy test line A', 1, 1, current_setting('costtrack.acceptance.rec_a')::uuid),
  (gen_random_uuid()::text, current_setting('costtrack.acceptance.bill_b'),
   'Policy test line B', 1, 1, current_setting('costtrack.acceptance.rec_b')::uuid);

insert into public.pos_bill_payments
  (id, bill_id, payment_method, amount, paid_by)
values
  (gen_random_uuid()::text, current_setting('costtrack.acceptance.bill_a'), 'cash', 1,
   current_setting('costtrack.acceptance.rec_a')::uuid),
  (gen_random_uuid()::text, current_setting('costtrack.acceptance.bill_b'), 'cash', 1,
   current_setting('costtrack.acceptance.rec_b')::uuid);

do $$
declare
  unexpected text;
begin
  with expected(tablename, policyname) as (
    values
      ('pos_charge_items', 'pos_charge_items_admin_full'),
      ('pos_charge_items', 'pos_charge_items_receptionist_read'),
      ('pos_charge_item_variants', 'pos_charge_item_variants_admin_full'),
      ('pos_charge_item_variants', 'pos_charge_item_variants_receptionist_read'),
      ('pos_package_tiers', 'pos_package_tiers_admin_full'),
      ('pos_package_tiers', 'pos_package_tiers_receptionist_read'),
      ('pos_package_inclusions', 'pos_package_inclusions_admin_full'),
      ('pos_package_inclusions', 'pos_package_inclusions_receptionist_read'),
      ('pos_discounts', 'pos_discounts_admin_full'),
      ('pos_discounts', 'pos_discounts_receptionist_read'),
      ('pos_settings', 'pos_settings_admin_full'),
      ('pos_settings', 'pos_settings_receptionist_read'),
      ('pos_shifts', 'pos_shifts_phase3_read'),
      ('pos_cash_movements', 'pos_cash_movements_phase3_read'),
      ('pos_bills', 'pos_bills_manager_admin_select'),
      ('pos_bills', 'pos_bills_receptionist_own_select'),
      ('pos_bill_lines', 'pos_bill_lines_manager_admin_select'),
      ('pos_bill_lines', 'pos_bill_lines_receptionist_own_select'),
      ('pos_bill_payments', 'pos_bill_payments_manager_admin_select'),
      ('pos_bill_payments', 'pos_bill_payments_receptionist_own_select'),
      ('pos_bill_approvals', 'pos_bill_approvals_phase2_select'),
      ('pos_reservation_deposits', 'pos_reservation_deposits_phase3_read'),
      ('pos_deposit_actions', 'pos_deposit_actions_role_read'),
      ('pos_notifications', 'pos_notifications_role_read'),
      ('reservations', 'reservations_read'),
      ('reservations', 'reservations_insert'),
      ('reservations', 'reservations_update'),
      ('reservations', 'reservations_delete'),
      ('revenue_records', 'revenue_records_read'),
      ('revenue_records', 'revenue_records_insert'),
      ('revenue_records', 'revenue_records_update'),
      ('revenue_records', 'revenue_records_delete'),
      ('buffet_rates', 'buffet_rates_read'),
      ('buffet_rates', 'buffet_rates_insert'),
      ('buffet_rates', 'buffet_rates_update'),
      ('buffet_rates', 'buffet_rates_delete')
  ),
  actual(tablename, policyname) as (
    select tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'pos_charge_items', 'pos_charge_item_variants', 'pos_package_tiers',
        'pos_package_inclusions', 'pos_discounts', 'pos_settings',
        'pos_shifts', 'pos_cash_movements', 'pos_bills', 'pos_bill_lines',
        'pos_bill_payments', 'pos_bill_approvals', 'pos_reservation_deposits',
        'pos_deposit_actions', 'pos_notifications', 'reservations',
        'revenue_records', 'buffet_rates'
      )
  )
  select string_agg(format('%s.%s', diff.tablename, diff.policyname), ', ')
  into unexpected
  from (
    (select * from expected except select * from actual)
    union all
    (select * from actual except select * from expected)
  ) as diff;

  if unexpected is not null then
    raise exception 'FAIL: final policy set differs from migration 010 matrix: %', unexpected;
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'pos_bills'
      and policyname = 'pos_bills_receptionist_own_select'
      and qual ilike '%created_by%auth.uid%'
  ) then
    raise exception 'FAIL: Receptionist bill SELECT is not scoped to created_by = auth.uid().';
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'pos_bill_lines'
      and policyname = 'pos_bill_lines_receptionist_own_select'
      and qual ilike '%created_by%auth.uid%'
  ) or not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'pos_bill_payments'
      and policyname = 'pos_bill_payments_receptionist_own_select'
      and qual ilike '%created_by%auth.uid%'
  ) then
    raise exception 'FAIL: Receptionist line/payment SELECT is not parent-bill scoped.';
  end if;
  if exists (
    select 1
    from pg_proc p
    cross join lateral aclexplode(
      coalesce(p.proacl, acldefault('f', p.proowner))
    ) acl
    where p.oid = to_regprocedure('public.create_revenue_draft(text)')
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'FAIL: PUBLIC still has create_revenue_draft execution.';
  end if;
end;
$$;

-- Non-POS inventory and table-management policies must remain present.
do $$
declare
  missing text;
begin
  with expected(tablename, policyname) as (
    values
      ('ingredients', 'ingredients_read'),
      ('inventory_transactions', 'inventory_transactions_read'),
      ('inventory_transactions', 'inventory_transactions_insert'),
      ('production_logs', 'production_logs_read'),
      ('production_logs', 'production_logs_insert'),
      ('waste_logs', 'waste_logs_read'),
      ('waste_logs', 'waste_logs_insert'),
      ('restaurant_tables', 'restaurant_tables_read'),
      ('restaurant_tables', 'restaurant_tables_insert'),
      ('restaurant_tables', 'restaurant_tables_update'),
      ('restaurant_tables', 'restaurant_tables_delete')
  )
  select string_agg(format('%s.%s', e.tablename, e.policyname), ', ')
  into missing
  from expected e
  where not exists (
    select 1 from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = e.tablename
      and p.policyname = e.policyname
  );
  if missing is not null then
    raise exception 'FAIL: non-POS policy regression detected: %', missing;
  end if;
end;
$$;

set local role authenticated;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', current_setting('costtrack.acceptance.rec_a'), true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object('role', 'authenticated', 'sub', current_setting('costtrack.acceptance.rec_a'))::text,
  true
);

do $$
declare
  row_count integer;
begin
  select count(*) into row_count
  from public.pos_bills
  where id in (
    current_setting('costtrack.acceptance.bill_a'),
    current_setting('costtrack.acceptance.bill_b')
  );
  if row_count <> 1
    or not exists (
      select 1 from public.pos_bills
      where id = current_setting('costtrack.acceptance.bill_a')
    )
    or exists (
      select 1 from public.pos_bills
      where id = current_setting('costtrack.acceptance.bill_b')
    ) then
    raise exception 'FAIL: Receptionist A can read another cashier''s bill or cannot read their own.';
  end if;

  select count(*) into row_count
  from public.pos_bill_lines l
  where l.bill_id in (
    current_setting('costtrack.acceptance.bill_a'),
    current_setting('costtrack.acceptance.bill_b')
  );
  if row_count <> 1 or exists (
    select 1 from public.pos_bill_lines l
    join public.pos_bills b on b.id = l.bill_id
    where b.id = current_setting('costtrack.acceptance.bill_b')
  ) then
    raise exception 'FAIL: Receptionist A can read another cashier''s bill lines.';
  end if;

  select count(*) into row_count
  from public.pos_bill_payments p
  where p.bill_id in (
    current_setting('costtrack.acceptance.bill_a'),
    current_setting('costtrack.acceptance.bill_b')
  );
  if row_count <> 1 or exists (
    select 1 from public.pos_bill_payments p
    join public.pos_bills b on b.id = p.bill_id
    where b.id = current_setting('costtrack.acceptance.bill_b')
  ) then
    raise exception 'FAIL: Receptionist A can read another cashier''s bill payments.';
  end if;

  if has_function_privilege(
    'authenticated', 'public.create_revenue_draft(text)', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'public.create_revenue_draft(text)', 'EXECUTE'
  ) then
    raise exception 'FAIL: an unauthorised role still has create_revenue_draft execution.';
  end if;

  begin
    execute 'select public.create_revenue_draft($1)'
      using 'POS-010-RETIRED-TEST';
    raise exception 'FAIL: Receptionist called retired create_revenue_draft.';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

select set_config('request.jwt.claim.sub', current_setting('costtrack.acceptance.rec_b'), true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object('role', 'authenticated', 'sub', current_setting('costtrack.acceptance.rec_b'))::text,
  true
);
do $$
begin
  if not exists (
    select 1 from public.pos_bills
    where id = current_setting('costtrack.acceptance.bill_b')
  ) or exists (
    select 1 from public.pos_bills
    where id = current_setting('costtrack.acceptance.bill_a')
  ) then
    raise exception 'FAIL: Receptionist B bill ownership is not isolated.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', current_setting('costtrack.acceptance.manager'), true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object('role', 'authenticated', 'sub', current_setting('costtrack.acceptance.manager'))::text,
  true
);
do $$
begin
  if (select count(*) from public.pos_bills
      where id in (
        current_setting('costtrack.acceptance.bill_a'),
        current_setting('costtrack.acceptance.bill_b')
      )) <> 2
    or (select count(*) from public.pos_bill_lines
      where bill_id in (
        current_setting('costtrack.acceptance.bill_a'),
        current_setting('costtrack.acceptance.bill_b')
      )) <> 2
    or (select count(*) from public.pos_bill_payments
      where bill_id in (
        current_setting('costtrack.acceptance.bill_a'),
        current_setting('costtrack.acceptance.bill_b')
      )) <> 2 then
    raise exception 'FAIL: Manager cannot read all acceptance bills, lines, and payments.';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub', current_setting('costtrack.acceptance.admin'), true);
select set_config(
  'request.jwt.claims',
  jsonb_build_object('role', 'authenticated', 'sub', current_setting('costtrack.acceptance.admin'))::text,
  true
);
do $$
begin
  if (select count(*) from public.pos_bills
      where id in (
        current_setting('costtrack.acceptance.bill_a'),
        current_setting('costtrack.acceptance.bill_b')
      )) <> 2
    or (select count(*) from public.pos_bill_lines
      where bill_id in (
        current_setting('costtrack.acceptance.bill_a'),
        current_setting('costtrack.acceptance.bill_b')
      )) <> 2
    or (select count(*) from public.pos_bill_payments
      where bill_id in (
        current_setting('costtrack.acceptance.bill_a'),
        current_setting('costtrack.acceptance.bill_b')
      )) <> 2 then
    raise exception 'FAIL: Administrator cannot read all acceptance bills, lines, and payments.';
  end if;
end;
$$;

reset role;

do $$
begin
  raise notice 'PASS: POS policy matrix, Receptionist own-bill privacy, retired RPC denial, and non-POS policy preservation.';
end;
$$;
rollback;
