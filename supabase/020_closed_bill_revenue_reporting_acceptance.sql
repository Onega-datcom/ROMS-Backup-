-- Acceptance checks for Phase 4 closed-bill revenue reporting.
-- Run as the database owner after migration 020; all fixtures are rolled back.

begin;
set transaction isolation level repeatable read;

do $$
declare
  manager_id uuid;
  receptionist_id uuid;
  shift_id text := 'PH4-SHIFT-' || gen_random_uuid()::text;
  closed_bill_id text := 'PH4-CLOSED-' || gen_random_uuid()::text;
  second_closed_bill_id text := 'PH4-CLOSED-' || gen_random_uuid()::text;
  voided_closed_bill_id text := 'PH4-VOID-CLOSED-' || gen_random_uuid()::text;
  voided_open_bill_id text := 'PH4-VOID-OPEN-' || gen_random_uuid()::text;
  open_bill_id text := 'PH4-OPEN-' || gen_random_uuid()::text;
  next_day_bill_id text := 'PH4-MANILA-MIDNIGHT-' || gen_random_uuid()::text;
  deposit_id text := 'PH4-DEPOSIT-' || gen_random_uuid()::text;
  legacy_revenue_id text := 'PH4-LEGACY-' || gen_random_uuid()::text;
  business_date_value date := public.pos_business_date();
  dashboard_value jsonb;
  dashboard_retry_value jsonb;
  daily_value jsonb;
  trend_value jsonb;
  customers_value jsonb;
  shift_value jsonb;
  bill_summary_value jsonb;
  food_cost_value jsonb;
  row_value jsonb;
  dashboard_before jsonb;
  daily_before jsonb;
  trend_before jsonb;
  customers_before jsonb;
  food_cost_before jsonb;
  bill_summary_before jsonb;
  receptionist_denied boolean := false;
begin
  if to_regclass('public.pos_closed_bill_revenue_v') is null
    or to_regclass('public.pos_voided_bill_revenue_v') is null
    or to_regprocedure(
      'public.pos_revenue_report(text,date,date,text,boolean,integer,integer)'
    ) is null then
    raise exception 'FAIL: Phase 4 revenue views or RPC are missing.';
  end if;
  if not has_function_privilege(
      'authenticated',
      'public.pos_revenue_report(text,date,date,text,boolean,integer,integer)',
      'EXECUTE'
    )
    or has_function_privilege(
      'anon',
      'public.pos_revenue_report(text,date,date,text,boolean,integer,integer)',
      'EXECUTE'
    )
    or has_table_privilege(
      'authenticated', 'public.pos_closed_bill_revenue_v', 'SELECT'
    ) then
    raise exception 'FAIL: Phase 4 report grants are not RPC-only for authenticated users.';
  end if;
  if has_table_privilege('authenticated', 'public.revenue_records', 'INSERT')
    or has_table_privilege('authenticated', 'public.revenue_records', 'UPDATE')
    or has_table_privilege('authenticated', 'public.revenue_records', 'DELETE')
    or has_function_privilege(
      'authenticated', 'public.confirm_revenue(text,jsonb)', 'EXECUTE'
    ) then
    raise exception 'FAIL: Legacy revenue records are still writable through the app role.';
  end if;

  select p.id into manager_id
  from public.profiles as p
  where p.role in ('Manager', 'Administrator')
  order by case when p.role = 'Manager' then 0 else 1 end, p.id
  limit 1;
  select p.id into receptionist_id
  from public.profiles as p
  where p.role = 'Receptionist'
  order by p.id
  limit 1;
  if manager_id is null or receptionist_id is null then
    raise exception 'Acceptance requires Manager/Administrator and Receptionist profiles.';
  end if;

  perform set_config('request.jwt.claim.sub', manager_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  dashboard_before := public.pos_revenue_report('dashboard');
  daily_before := public.pos_revenue_report(
    'daily_revenue', business_date_value, business_date_value
  );
  trend_before := public.pos_revenue_report(
    'revenue_trend', business_date_value, business_date_value + 1, 'day'
  );
  customers_before := public.pos_revenue_report(
    'customer_count', business_date_value, business_date_value, 'day'
  );
  food_cost_before := public.pos_revenue_report(
    'food_cost', business_date_value, business_date_value
  );
  bill_summary_before := public.pos_revenue_report(
    'closed_bill_summary', business_date_value, business_date_value,
    'day', true, 1, 500
  );

  insert into public.pos_shifts (
    id, shift_code, opened_by, status, opened_at, closed_at
  ) values (
    shift_id, shift_id, manager_id, 'Closed', now(), now()
  );

  insert into public.pos_bills (
    id, bill_number, customer_name, status, subtotal, service_charge,
    discount_total, deposit_total, paid_total, balance_due, created_by,
    closed_by, closed_at, shift_id, adult_count, senior_count, kids_count,
    comped_count, customers_served, food_revenue_total, non_food_revenue_total
  ) values
    (
      closed_bill_id, closed_bill_id, 'Phase 4 closed fixture', 'Closed',
      1000, 50, 100, 300, 650, 0, manager_id, manager_id,
      (business_date_value + time '12:00') at time zone 'Asia/Manila',
      shift_id, 2, 1, 3, 1, 7, 900, 50
    ),
    (
      second_closed_bill_id, second_closed_bill_id, 'Phase 4 second closed fixture', 'Closed',
      200, 0, 0, 0, 200, 0, manager_id, manager_id,
      (business_date_value + time '13:00') at time zone 'Asia/Manila',
      shift_id, 1, 0, 1, 0, 2, 200, 0
    ),
    (
      open_bill_id, open_bill_id, 'Phase 4 open fixture', 'Open',
      900, 0, 0, 0, 0, 900, manager_id, null, null,
      shift_id, 9, 0, 0, 0, 9, 900, 0
    ),
    (
      voided_closed_bill_id, voided_closed_bill_id, 'Phase 4 voided closed fixture', 'Voided',
      500, 0, 50, 0, 450, 0, manager_id, manager_id,
      (business_date_value + time '14:00') at time zone 'Asia/Manila',
      shift_id, 2, 0, 0, 0, 2, 500, 0
    ),
    (
      voided_open_bill_id, voided_open_bill_id, 'Phase 4 voided open fixture', 'Voided',
      300, 0, 0, 0, 0, 300, manager_id, null, null,
      shift_id, 1, 0, 0, 0, 1, 300, 0
    ),
    (
      next_day_bill_id, next_day_bill_id, 'Phase 4 Manila date fixture', 'Closed',
      100, 0, 0, 0, 100, 0, manager_id, manager_id,
      (business_date_value + 1 + time '00:30') at time zone 'Asia/Manila',
      shift_id, 1, 0, 0, 0, 1, 100, 0
    );

  update public.pos_bills
  set voided_by = manager_id,
      voided_at = (business_date_value + time '15:00') at time zone 'Asia/Manila',
      void_reason = 'Phase 4 acceptance void.'
  where id = voided_closed_bill_id;
  update public.pos_bills
  set voided_by = manager_id,
      voided_at = (business_date_value + time '15:30') at time zone 'Asia/Manila',
      void_reason = 'Phase 4 acceptance open void.'
  where id = voided_open_bill_id;

  insert into public.pos_bill_payments (
    id, bill_id, payment_method, amount, paid_by, shift_id
  ) values (
    'PH4-PAYMENT-' || gen_random_uuid()::text,
    closed_bill_id, 'deposit', 300, manager_id, shift_id
  );
  insert into public.pos_reservation_deposits (
    id, amount, payment_method, status, created_by, received_shift_id,
    receipt_amount, created_at
  ) values (
    deposit_id, 300, 'cash', 'Held', manager_id, shift_id, 300,
    (business_date_value + time '11:00') at time zone 'Asia/Manila'
  );
  insert into public.revenue_records (
    id, business_date, meal_period, adult_customers, adult_rate,
    status, recorded_by
  ) values (
    legacy_revenue_id, business_date_value, 'PH4-' || gen_random_uuid()::text,
    99, 999, 'Confirmed', manager_id::text
  );

  dashboard_value := public.pos_revenue_report('dashboard');
  dashboard_retry_value := public.pos_revenue_report('dashboard');
  if (dashboard_value->>'today_revenue')::numeric
      <> (dashboard_before->>'today_revenue')::numeric + 1150
    or (dashboard_value->>'closed_bill_count')::integer
      <> (dashboard_before->>'closed_bill_count')::integer + 2
    or (dashboard_value->>'customers_served')::integer
      <> (dashboard_before->>'customers_served')::integer + 9
    or (dashboard_value->>'adult_count')::integer
      <> (dashboard_before->>'adult_count')::integer + 3
    or (dashboard_value->>'senior_count')::integer
      <> (dashboard_before->>'senior_count')::integer + 1
    or (dashboard_value->>'kids_count')::integer
      <> (dashboard_before->>'kids_count')::integer + 4
    or (dashboard_value->>'comped_count')::integer
      <> (dashboard_before->>'comped_count')::integer + 1
    or (dashboard_value->>'average_check')::numeric
      <> round((
        (dashboard_before->>'today_revenue')::numeric + 1150
      ) / ((dashboard_before->>'closed_bill_count')::integer + 2), 2)
    or (dashboard_value->>'discount_total')::numeric
      <> (dashboard_before->>'discount_total')::numeric + 100
    or (dashboard_value->>'voided_bill_count')::integer
      <> (dashboard_before->>'voided_bill_count')::integer + 2
    or (dashboard_value->>'voided_bill_amount')::numeric
      <> (dashboard_before->>'voided_bill_amount')::numeric + 450
    or dashboard_retry_value is distinct from dashboard_value then
    raise exception 'FAIL: dashboard fixture deltas or repeat-read count are incorrect. Before: %, after: %',
      dashboard_before, dashboard_value;
  end if;

  daily_value := public.pos_revenue_report(
    'daily_revenue', business_date_value, business_date_value
  );
  row_value := daily_value->'rows'->0;
  if (row_value->>'closed_bill_count')::integer
      <> ((daily_before->'rows'->0->>'closed_bill_count')::integer + 2)
    or (row_value->>'net_revenue')::numeric
      <> ((daily_before->'rows'->0->>'net_revenue')::numeric + 1150)
    or (row_value->>'discount_total')::numeric
      <> ((daily_before->'rows'->0->>'discount_total')::numeric + 100)
    or (row_value->>'voided_bill_count')::integer
      <> ((daily_before->'rows'->0->>'voided_bill_count')::integer + 2)
    or (row_value->>'voided_bill_amount')::numeric
      <> ((daily_before->'rows'->0->>'voided_bill_amount')::numeric + 450) then
    raise exception 'FAIL: daily report includes ineligible bills or misses void statistics: %',
      daily_value;
  end if;

  trend_value := public.pos_revenue_report(
    'revenue_trend', business_date_value, business_date_value + 1, 'day'
  );
  customers_value := public.pos_revenue_report(
    'customer_count', business_date_value, business_date_value, 'day'
  );
  row_value := customers_value->'rows'->0;
  if (row_value->>'adult_count')::integer
      <> ((customers_before->'rows'->0->>'adult_count')::integer + 3)
    or (row_value->>'senior_count')::integer
      <> ((customers_before->'rows'->0->>'senior_count')::integer + 1)
    or (row_value->>'kids_count')::integer
      <> ((customers_before->'rows'->0->>'kids_count')::integer + 4)
    or (row_value->>'customers_served')::integer
      <> ((customers_before->'rows'->0->>'customers_served')::integer + 9) then
    raise exception 'FAIL: customer report did not use actual bill counts: %',
      customers_value;
  end if;
  if (trend_value->'rows'->0->>'net_revenue')::numeric
      <> ((trend_before->'rows'->0->>'net_revenue')::numeric + 1150)
    or (trend_value->'rows'->1->>'net_revenue')::numeric
      <> ((trend_before->'rows'->1->>'net_revenue')::numeric + 100) then
    raise exception 'FAIL: close timestamps were not grouped by Manila business date: %',
      trend_value;
  end if;
  food_cost_value := public.pos_revenue_report(
    'food_cost', business_date_value, business_date_value
  );
  if (food_cost_value->'rows'->0->>'revenue')::numeric
      <> ((food_cost_before->'rows'->0->>'revenue')::numeric + 1150) then
    raise exception 'FAIL: food-cost denominator includes non-closed or legacy revenue: %',
      food_cost_value;
  end if;

  shift_value := public.pos_revenue_report(
    'shift_revenue', business_date_value, business_date_value
  );
  select rows.row into row_value
  from jsonb_array_elements(shift_value->'rows') as rows(row)
  where rows.row->>'shift_id' = shift_id;
  if row_value is null then
    raise exception 'FAIL: shift report omitted the acceptance shift: %',
      shift_value;
  end if;
  if (row_value->>'net_revenue')::numeric <> 1150
    or (row_value->>'deposit_applied')::numeric <> 300
    or (row_value->>'deposit_receipts')::numeric <> 300 then
    raise exception 'FAIL: shift report did not separate deposit operations from revenue: %',
      shift_value;
  end if;

  bill_summary_value := public.pos_revenue_report(
    'closed_bill_summary', business_date_value, business_date_value,
    'day', true, 1, 500
  );
  if (bill_summary_value->>'total_rows')::integer
      <> ((bill_summary_before->>'total_rows')::integer + 2)
    or exists (
      select 1
      from jsonb_array_elements(bill_summary_value->'rows') as rows(row)
      where row->>'bill_id' in (open_bill_id, voided_closed_bill_id, voided_open_bill_id)
    )
    or (
      select count(*)
      from jsonb_array_elements(bill_summary_value->'rows') as rows(row)
      where row->>'bill_id' in (closed_bill_id, second_closed_bill_id)
    ) <> 2 then
    raise exception 'FAIL: closed-bill summary contains an Open or Voided bill: %',
      bill_summary_value;
  end if;
  if (
    select v.business_date from public.pos_closed_bill_revenue_v as v
    where v.bill_id = next_day_bill_id
  ) is distinct from business_date_value + 1 then
    raise exception 'FAIL: close timestamp was not converted to Manila business date.';
  end if;

  perform set_config('request.jwt.claim.sub', receptionist_id::text, true);
  begin
    perform public.pos_revenue_report('dashboard');
  exception when sqlstate '42501' then
    receptionist_denied := true;
  end;
  if not receptionist_denied then
    raise exception 'FAIL: Receptionist can execute the financial revenue RPC.';
  end if;

  raise notice 'PASS: only Closed bills contribute revenue; deposits and legacy records are excluded; voids are separate; reports use actual covers and Manila close date; reports are role-restricted.';
end;
$$;

rollback;
