begin;

do $$
declare
  routine_definition text;
  manager_id uuid;
  clerk_id uuid;
  ingredient_id_value text;
  ingredient_stock_before numeric;
  ingredient_stock_after numeric;
  waste_id_value text;
  rpc_result jsonb;
  retry_result jsonb;
  denied boolean;
  today_manila date := (clock_timestamp() at time zone 'Asia/Manila')::date;
begin
  if to_regclass('public.prepared_food_waste_logs') is null then
    raise exception 'prepared_food_waste_logs table is missing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class as relation
    where relation.oid = 'public.prepared_food_waste_logs'::regclass
      and relation.relrowsecurity
  ) then
    raise exception 'prepared_food_waste_logs must have row-level security enabled';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'public.prepared_food_waste_logs'::regclass
      and tgname = 'prevent_prepared_food_waste_mutation'
      and not tgisinternal
  ) then
    raise exception 'prepared-food waste must be append-only';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'public.prepared_food_waste_logs'::regclass
      and tgname = 'write_audit_log'
      and not tgisinternal
  ) then
    raise exception 'prepared-food waste insert audit trigger is missing';
  end if;

  if exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'public.prepared_food_waste_logs'::regclass
      and tgname = 'apply_waste_stock'
      and not tgisinternal
  ) then
    raise exception 'prepared-food waste must not use the ingredient stock deduction trigger';
  end if;

  if has_table_privilege('authenticated', 'public.prepared_food_waste_logs', 'INSERT') then
    raise exception 'prepared-food waste inserts must go through the validated RPC';
  end if;

  select lower(pg_catalog.pg_get_functiondef(
    'public.costtrack_log_prepared_food_waste(jsonb)'::regprocedure
  )) into routine_definition;
  if routine_definition like '%update public.ingredients%'
     or routine_definition like '%public.waste_logs%'
     or routine_definition like '%costtrack.stock_movement%' then
    raise exception 'prepared-food waste RPC must not change ingredient inventory';
  end if;

  select id into manager_id
  from public.profiles
  where role = 'Manager'
  order by id
  limit 1;
  select id into clerk_id
  from public.profiles
  where role = 'Inventory Clerk'
  order by id
  limit 1;
  if manager_id is null or clerk_id is null then
    raise exception 'Acceptance requires existing Manager and Inventory Clerk profiles.';
  end if;
  select id, stock into ingredient_id_value, ingredient_stock_before
  from public.ingredients
  where stock > 0
  order by id
  limit 1;
  if ingredient_id_value is null then
    raise exception 'Acceptance requires an ingredient with positive stock to verify it remains unchanged.';
  end if;

  perform set_config('request.jwt.claim.sub', manager_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', manager_id::text, 'role', 'authenticated')::text,
    true
  );
  waste_id_value := 'P35-accept-' || txid_current()::text;
  rpc_result := public.costtrack_log_prepared_food_waste(jsonb_build_object(
    'id', waste_id_value,
    'dish_name', 'P35 acceptance dish',
    'quantity', 3,
    'reason', 'Leftover after service',
    'waste_date', today_manila::text,
    'notes', 'Prepared food only'
  ));
  if rpc_result ->> 'dish_name' <> 'P35 acceptance dish'
     or rpc_result ->> 'recorded_by' <> manager_id::text
     or (rpc_result ->> 'recorded_at')::timestamptz is null then
    raise exception 'Prepared-food waste RPC did not return its recorded data and server audit fields.';
  end if;
  select stock into ingredient_stock_after
  from public.ingredients
  where id = ingredient_id_value;
  if ingredient_stock_after <> ingredient_stock_before then
    raise exception 'Prepared-food waste changed ingredient stock from % to %.',
      ingredient_stock_before, ingredient_stock_after;
  end if;

  retry_result := public.costtrack_log_prepared_food_waste(jsonb_build_object(
    'id', waste_id_value,
    'dish_name', 'P35 acceptance dish',
    'quantity', 3,
    'reason', 'Leftover after service',
    'waste_date', today_manila::text,
    'notes', 'Prepared food only'
  ));
  if retry_result ->> 'recorded_at' <> rpc_result ->> 'recorded_at'
     or (select count(*) from public.prepared_food_waste_logs where id = waste_id_value) <> 1 then
    raise exception 'Prepared-food waste retry was not idempotent.';
  end if;

  perform set_config('request.jwt.claim.sub', clerk_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', clerk_id::text, 'role', 'authenticated')::text,
    true
  );
  denied := false;
  begin
    perform public.costtrack_log_prepared_food_waste(jsonb_build_object(
      'id', waste_id_value || '-denied',
      'dish_name', 'P35 denied dish',
      'quantity', 1,
      'reason', 'Leftover after service',
      'waste_date', today_manila::text,
      'notes', ''
    ));
  exception when sqlstate '42501' then
    denied := true;
  end;
  if not denied then
    raise exception 'Inventory Clerk was allowed to write prepared-food waste.';
  end if;
end;
$$;

rollback;
