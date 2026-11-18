-- Run after 021 as the database owner. All fixture writes are rolled back.
begin;

do $$
declare
  manager_id uuid;
  ingredient_id_value text;
  initial_stock numeric;
  ingredient_cost numeric;
  resulting_stock numeric;
  test_quantity constant numeric := 0.0001;
  waste_id_value text;
  direct_waste_id_value text;
  invalid_reason_id_value text;
  other_note_id_value text;
  rpc_result jsonb;
  retry_result jsonb;
  report_before jsonb;
  report_after jsonb;
  before_call timestamptz;
  after_call timestamptz;
  rpc_timestamp timestamptz;
  direct_timestamp timestamptz;
  direct_row public.waste_logs%rowtype;
  today_manila date := (clock_timestamp() at time zone 'Asia/Manila')::date;
  before_reason_quantity numeric;
  after_reason_quantity numeric;
  before_reason_cost numeric;
  after_reason_cost numeric;
  before_day_quantity numeric;
  after_day_quantity numeric;
  before_day_cost numeric;
  after_day_cost numeric;
  request_rejected boolean;
  waste_insert_policy text;
begin
  select id into manager_id
  from public.profiles
  where role = 'Manager'
  order by id
  limit 1;
  if manager_id is null then
    raise exception 'Acceptance requires an existing Manager profile.';
  end if;

  select id, stock, cost
  into ingredient_id_value, initial_stock, ingredient_cost
  from public.ingredients
  where stock >= test_quantity * 2
    and cost is not null
  order by id
  limit 1;
  if ingredient_id_value is null then
    raise exception 'Acceptance requires an ingredient with at least 0.0002 stock and a cost.';
  end if;

  perform set_config('request.jwt.claim.sub', manager_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', manager_id::text, 'role', 'authenticated')::text,
    true
  );

  select with_check into waste_insert_policy
  from pg_policies
  where schemaname = 'public'
    and tablename = 'waste_logs'
    and policyname = 'waste_logs_insert';
  if waste_insert_policy is null
     or position('Inventory Clerk' in waste_insert_policy) > 0
     or position('Chef / Kitchen Staff' in waste_insert_policy) = 0 then
    raise exception 'Waste insert RLS does not match the existing RPC/UI write roles.';
  end if;

  waste_id_value := 'P021-accept-rpc-' || txid_current()::text;
  direct_waste_id_value := 'P021-accept-direct-' || txid_current()::text;
  invalid_reason_id_value := 'P021-accept-no-reason-' || txid_current()::text;
  other_note_id_value := 'P021-accept-other-no-note-' || txid_current()::text;

  report_before := public.report_analytics('waste', today_manila, today_manila, 'day', true);

  before_call := clock_timestamp();
  rpc_result := public.costtrack_log_waste(jsonb_build_object(
    'id', waste_id_value,
    'ingredient_id', ingredient_id_value,
    'quantity', test_quantity,
    'reason', 'Over-preparation',
    'waste_date', '1900-01-01',
    'recorded_at', '1900-01-01T00:00:00Z',
    'production_log_id', null,
    'notes', '021 acceptance'
  ));
  after_call := clock_timestamp();
  rpc_timestamp := (rpc_result ->> 'recorded_at')::timestamptz;

  if rpc_result ->> 'waste_date' <> today_manila::text
     or rpc_timestamp < before_call or rpc_timestamp > after_call then
    raise exception 'RPC did not replace the client timestamp/date with current server Manila time.';
  end if;

  retry_result := public.costtrack_log_waste(jsonb_build_object(
    'id', waste_id_value,
    'ingredient_id', ingredient_id_value,
    'quantity', test_quantity,
    'reason', 'Over-preparation',
    'waste_date', '2999-12-31',
    'recorded_at', '2999-12-31T23:59:59Z',
    'production_log_id', null,
    'notes', '021 acceptance'
  ));
  if retry_result ->> 'recorded_at' <> rpc_result ->> 'recorded_at'
     or retry_result ->> 'waste_date' <> rpc_result ->> 'waste_date' then
    raise exception 'An idempotent retry did not return the original saved waste record.';
  end if;
  if (select count(*) from public.waste_logs where id = waste_id_value) <> 1 then
    raise exception 'Retry created more than one waste record.';
  end if;

  request_rejected := false;
  begin
    perform public.costtrack_log_waste(jsonb_build_object(
      'id', invalid_reason_id_value,
      'ingredient_id', ingredient_id_value,
      'quantity', test_quantity,
      'reason', '',
      'waste_date', today_manila::text
    ));
  exception when others then
    request_rejected := true;
  end;
  if not request_rejected then
    raise exception 'RPC accepted a waste entry without a reason.';
  end if;

  request_rejected := false;
  begin
    perform public.costtrack_log_waste(jsonb_build_object(
      'id', other_note_id_value,
      'ingredient_id', ingredient_id_value,
      'quantity', test_quantity,
      'reason', 'Other',
      'notes', '   ',
      'waste_date', today_manila::text
    ));
  exception when others then
    request_rejected := true;
  end;
  if not request_rejected then
    raise exception 'RPC accepted Other without a non-blank note.';
  end if;

  before_call := clock_timestamp();
  insert into public.waste_logs (
    id, ingredient_id, quantity, reason, waste_date, recorded_at, notes
  ) values (
    direct_waste_id_value, ingredient_id_value, test_quantity, 'Expired',
    '1900-01-01', '1900-01-01T00:00:00Z', '021 direct insert check'
  )
  returning * into direct_row;
  after_call := clock_timestamp();
  direct_timestamp := direct_row.recorded_at;
  if direct_row.waste_date <> today_manila
     or direct_timestamp < before_call or direct_timestamp > after_call then
    raise exception 'The insert trigger did not replace a direct client timestamp/date.';
  end if;

  select stock into resulting_stock
  from public.ingredients
  where id = ingredient_id_value;
  if resulting_stock <> initial_stock - (test_quantity * 2) then
    raise exception 'Expected exactly two deductions for two unique waste rows; stock changed from % to %.',
      initial_stock, resulting_stock;
  end if;

  if (select count(*) from public.waste_logs where id in (waste_id_value, direct_waste_id_value)) <> 2 then
    raise exception 'Expected exactly two unique acceptance waste records.';
  end if;

  report_after := public.report_analytics('waste', today_manila, today_manila, 'day', true);
  if jsonb_typeof(report_before -> 'by_ingredient') <> 'array'
     or jsonb_typeof(report_after -> 'by_ingredient') <> 'array'
     or jsonb_typeof(report_after -> 'by_reason') <> 'array'
     or jsonb_typeof(report_after -> 'by_day') <> 'array'
     or (report_after ->> 'linked_count')::bigint <> (report_before ->> 'linked_count')::bigint
     or (report_after ->> 'unlinked_count')::bigint <> (report_before ->> 'unlinked_count')::bigint + 2 then
    raise exception 'The existing waste report shape or linked/unlinked counts changed unexpectedly.';
  end if;

  select coalesce(sum((entry ->> 'quantity')::numeric), 0),
         coalesce(sum((entry ->> 'waste_cost')::numeric), 0)
  into before_reason_quantity, before_reason_cost
  from jsonb_array_elements(report_before -> 'by_reason') as rows(entry)
  where entry ->> 'reason' = 'Over-preparation';
  select coalesce(sum((entry ->> 'quantity')::numeric), 0),
         coalesce(sum((entry ->> 'waste_cost')::numeric), 0)
  into after_reason_quantity, after_reason_cost
  from jsonb_array_elements(report_after -> 'by_reason') as rows(entry)
  where entry ->> 'reason' = 'Over-preparation';
  if after_reason_quantity - before_reason_quantity <> test_quantity
     or after_reason_cost - before_reason_cost <> test_quantity * ingredient_cost then
    raise exception 'The existing by-reason report did not reflect the saved quantity and current-cost calculation.';
  end if;

  select coalesce(sum((entry ->> 'quantity')::numeric), 0),
         coalesce(sum((entry ->> 'waste_cost')::numeric), 0)
  into before_day_quantity, before_day_cost
  from jsonb_array_elements(report_before -> 'by_day') as rows(entry)
  where (entry ->> 'period')::date = today_manila;
  select coalesce(sum((entry ->> 'quantity')::numeric), 0),
         coalesce(sum((entry ->> 'waste_cost')::numeric), 0)
  into after_day_quantity, after_day_cost
  from jsonb_array_elements(report_after -> 'by_day') as rows(entry)
  where (entry ->> 'period')::date = today_manila;
  if after_day_quantity - before_day_quantity <> test_quantity * 2
     or after_day_cost - before_day_cost <> test_quantity * 2 * ingredient_cost then
    raise exception 'The existing by-day report did not reflect both rows using current ingredient cost.';
  end if;

  raise notice 'PASS: server time/date, ignored client timestamps, required reason/note, idempotent retry, one stock deduction per unique row, and existing report aggregation.';
end;
$$;

rollback;
