-- Run as the database owner after migration 027.
-- Requires one existing Chef / Kitchen Staff profile. All fixture rows roll back.
begin;

do $$
declare
  chef_id uuid;
  good_recipe_id text := 'P26-RECIPE-' || gen_random_uuid()::text;
  low_recipe_id text := 'P26-LOW-RECIPE-' || gen_random_uuid()::text;
  good_a_id text := 'P26-ING-A-' || gen_random_uuid()::text;
  good_b_id text := 'P26-ING-B-' || gen_random_uuid()::text;
  low_stock_id text := 'P26-ING-LOW-' || gen_random_uuid()::text;
  good_batch_id text := 'P26-BATCH-' || gen_random_uuid()::text;
  low_batch_id text := 'P26-LOW-BATCH-' || gen_random_uuid()::text;
  completion_result jsonb;
  snapshot_value numeric;
  log_count integer;
begin
  select id into chef_id
  from public.profiles
  where role = 'Chef / Kitchen Staff'
  limit 1;
  if chef_id is null then
    raise exception 'FAIL: provision a Chef / Kitchen Staff profile before running acceptance.';
  end if;

  insert into public.ingredients (id, name, category, unit, cost, stock, minimum)
  values
    (good_a_id, 'P26 acceptance ingredient A', 'Acceptance', 'unit', 2, 10, 0),
    (good_b_id, 'P26 acceptance ingredient B', 'Acceptance', 'unit', 3, 20, 0),
    (low_stock_id, 'P26 acceptance low-stock ingredient', 'Acceptance', 'unit', 1, 0.5, 0);

  insert into public.recipes (
    id, name, category, wastage, batch_yield, prep_target, prep_notes, is_active
  ) values
    (good_recipe_id, 'P26 acceptance recipe', 'Acceptance', 10, 30, 30, '', true),
    (low_recipe_id, 'P26 low-stock recipe', 'Acceptance', 0, 30, 30, '', true);

  insert into public.recipe_ingredients (recipe_id, ingredient_id, quantity)
  values
    (good_recipe_id, good_a_id, 2),
    (good_recipe_id, good_b_id, 3),
    (low_recipe_id, low_stock_id, 1);

  insert into public.production_batches (
    id, recipe_id, service_date, batch_number, batch_count, batch_yield,
    expected_covers, prep_target, status, started_at, started_by
  ) values
    (good_batch_id, good_recipe_id, current_date, 1, 1, 30, 15, 30, 'Cooking', now(), chef_id),
    (low_batch_id, low_recipe_id, current_date, 1, 1, 30, 30, 30, 'Cooking', now(), chef_id);

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', chef_id::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', chef_id::text, 'role', 'authenticated')::text, true);

  completion_result := public.costtrack_complete_production_batch(good_batch_id);
  if completion_result ->> 'status' is distinct from 'Ready'
     or not exists (
       select 1 from public.production_batches
       where id = good_batch_id and status = 'Ready'
     ) then
    raise exception 'FAIL: a valid production batch did not become Ready.';
  end if;
  if (select stock from public.ingredients where id = good_a_id) <> 9
     or (select stock from public.ingredients where id = good_b_id) <> 18.5 then
    raise exception 'FAIL: successful completion did not deduct the expected scaled stock exactly once.';
  end if;
  select batch_cost_snapshot into snapshot_value
  from public.production_logs
  where production_batch_id = good_batch_id;
  if snapshot_value is distinct from 7.15::numeric then
    raise exception 'FAIL: expected the cost snapshot 7.15, received %.', snapshot_value;
  end if;

  completion_result := public.costtrack_complete_production_batch(good_batch_id);
  select count(*) into log_count
  from public.production_logs
  where production_batch_id = good_batch_id;
  if completion_result ->> 'status' is distinct from 'Ready'
     or log_count <> 1
     or (select stock from public.ingredients where id = good_a_id) <> 9
     or (select stock from public.ingredients where id = good_b_id) <> 18.5 then
    raise exception 'FAIL: repeating completion changed stock or created another production log.';
  end if;

  begin
    perform public.costtrack_complete_production_batch(low_batch_id);
    raise exception 'FAIL: completion with insufficient stock unexpectedly succeeded.';
  exception
    when check_violation then
      null;
  end;
  if not exists (
       select 1 from public.production_batches
       where id = low_batch_id and status = 'Cooking' and production_log_id is null
     )
     or exists (
       select 1 from public.production_logs where production_batch_id = low_batch_id
     )
     or (select stock from public.ingredients where id = low_stock_id) <> 0.5 then
    raise exception 'FAIL: failed completion did not leave the batch, log, and stock unchanged.';
  end if;

  raise notice 'PASS: completion snapshots cost, deducts scaled stock once, is idempotent, and rolls back insufficient-stock attempts.';
end;
$$;

rollback;
