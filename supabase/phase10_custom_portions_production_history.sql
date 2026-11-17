begin;

alter table public.production_logs
  add column if not exists production_batch_id text
    references public.production_batches (id) on delete restrict;
create unique index if not exists production_logs_production_batch_id_key
  on public.production_logs (production_batch_id)
  where production_batch_id is not null;

create or replace function public.costtrack_start_production_batches(
  recipe_id_value text,
  service_date_value date,
  batch_ids jsonb
)
returns setof public.production_batches
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  request_item jsonb;
  requested_id text;
  requested_portions integer;
  existing_batch public.production_batches%rowtype;
  next_batch_number integer;
  recipe_record public.recipes%rowtype;
  requested_ids text[] := array[]::text[];
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']) then
    raise exception 'Not authorized to start production batches'
      using errcode = '42501';
  end if;
  if nullif(btrim(recipe_id_value), '') is null or service_date_value is null
     or jsonb_typeof(batch_ids) is distinct from 'array'
     or jsonb_array_length(batch_ids) not between 1 and 3 then
    raise exception 'Choose a recipe, service date, and one to three batch requests';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(recipe_id_value || ':' || service_date_value::text, 0));
  select * into recipe_record
  from public.recipes as recipe
  where recipe.id = recipe_id_value;
  if not found then
    raise exception 'The selected recipe no longer exists';
  end if;

  for request_item in
    select request.value
    from jsonb_array_elements(batch_ids) as request(value)
  loop
    if jsonb_typeof(request_item) = 'string' then
      requested_id := nullif(btrim(request_item #>> '{}'), '');
      requested_portions := recipe_record.batch_yield;
    elsif jsonb_typeof(request_item) = 'object' then
      requested_id := nullif(btrim(request_item ->> 'id'), '');
      if coalesce(request_item ->> 'portions', '') !~ '^[0-9]+$' then
        raise exception 'Batch portions must be a positive whole number';
      end if;
      requested_portions := (request_item ->> 'portions')::integer;
    else
      raise exception 'Each batch request must be a batch ID or an object with ID and portions';
    end if;
    if requested_id is null or requested_portions not between 1 and 10000 then
      raise exception 'Each batch needs a valid ID and between 1 and 10000 portions';
    end if;
    if requested_id = any(requested_ids) then
      raise exception 'Batch IDs must be unique';
    end if;
    requested_ids := array_append(requested_ids, requested_id);

    select * into existing_batch
    from public.production_batches as batch
    where batch.id = requested_id
    for update;
    if found then
      if existing_batch.recipe_id <> recipe_id_value
         or existing_batch.service_date <> service_date_value
         or existing_batch.expected_covers <> requested_portions then
        raise exception 'This batch request ID was already used for a different production batch';
      end if;
      continue;
    end if;

    select coalesce(max(batch.batch_number), 0) + 1 into next_batch_number
    from public.production_batches as batch
    where batch.recipe_id = recipe_id_value
      and batch.service_date = service_date_value;
    insert into public.production_batches (
      id, recipe_id, service_date, batch_number, batch_count, batch_yield,
      expected_covers, prep_target, status, started_at, started_by
    ) values (
      requested_id, recipe_id_value, service_date_value, next_batch_number, 1,
      recipe_record.batch_yield, requested_portions, recipe_record.prep_target,
      'Cooking', now(), auth.uid()
    );
  end loop;

  return query
  select batch.*
  from public.production_batches as batch
  where batch.id = any(requested_ids)
  order by batch.batch_number;
end;
$$;

create or replace function public.apply_production_stock()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  recipe_line record;
  ingredient_updated boolean;
  prior_stock_permission text;
  production_factor numeric;
  batch public.production_batches%rowtype;
begin
  if tg_op <> 'INSERT' then
    raise exception 'Production logs are append-only' using errcode = '55000';
  end if;

  production_factor := new.quantity;
  if new.production_batch_id is not null then
    select * into batch
    from public.production_batches as production_batch
    where production_batch.id = new.production_batch_id;
    if not found or batch.recipe_id <> new.recipe_id or batch.status <> 'Cooking' then
      raise exception 'The linked production batch is missing or is not cooking';
    end if;
    production_factor := batch.expected_covers::numeric / batch.batch_yield;
  end if;

  prior_stock_permission := current_setting('costtrack.stock_movement', true);
  perform set_config('costtrack.stock_movement', 'on', true);
  for recipe_line in
    select ingredient_id, quantity
    from public.recipe_ingredients
    where recipe_id = new.recipe_id
    order by ingredient_id
  loop
    update public.ingredients
    set stock = stock - (recipe_line.quantity * production_factor)
    where id = recipe_line.ingredient_id
      and stock >= recipe_line.quantity * production_factor;
    ingredient_updated := found;
    if not ingredient_updated then
      raise exception 'Production would make stock negative for ingredient %',
        recipe_line.ingredient_id using errcode = '23514';
    end if;
  end loop;
  perform set_config('costtrack.stock_movement', coalesce(prior_stock_permission, ''), true);
  return new;
end;
$$;

create or replace function public.costtrack_complete_production_batch(batch_id_value text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  batch public.production_batches%rowtype;
  production_log_id_value text;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']) then
    raise exception 'Not authorized to complete production batches'
      using errcode = '42501';
  end if;
  if nullif(btrim(batch_id_value), '') is null then
    raise exception 'A production batch ID is required';
  end if;

  select * into batch
  from public.production_batches as production_batch
  where production_batch.id = batch_id_value
  for update;
  if not found then
    raise exception 'Production batch not found';
  end if;
  if batch.status = 'Ready' then
    return to_jsonb(batch);
  end if;

  production_log_id_value := 'PROD-' || batch.id;
  insert into public.production_logs (
    id, recipe_id, quantity, covers_produced, production_date, mode,
    production_batch_id
  ) values (
    production_log_id_value, batch.recipe_id, 1,
    batch.expected_covers, batch.service_date,
    'Buffet batch #' || batch.batch_number, batch.id
  );

  update public.production_batches as production_batch
  set status = 'Ready',
      ready_at = now(),
      ready_by = auth.uid(),
      production_log_id = production_log_id_value
  where production_batch.id = batch.id
  returning * into batch;

  return to_jsonb(batch);
end;
$$;

create or replace function public.costtrack_load_production_history(
  start_date_value date,
  end_date_value date
)
returns table (
  id text,
  recipe_id text,
  service_date date,
  batch_number integer,
  portions integer,
  status text,
  started_at timestamptz,
  ready_at timestamptz,
  production_log_id text,
  recipe_name text,
  category text,
  legacy_time_unknown boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']) then
    raise exception 'Not authorized to read production history'
      using errcode = '42501';
  end if;
  if start_date_value is null or end_date_value is null
     or end_date_value < start_date_value
     or end_date_value - start_date_value > 90 then
    raise exception 'Choose a valid date range of no more than 91 days';
  end if;

  return query
  select history_rows.id, history_rows.recipe_id, history_rows.service_date,
    history_rows.batch_number, history_rows.portions, history_rows.status,
    history_rows.started_at, history_rows.ready_at, history_rows.production_log_id,
    history_rows.recipe_name, history_rows.category, history_rows.legacy_time_unknown
  from (
    select batch.id, batch.recipe_id, batch.service_date, batch.batch_number,
      batch.expected_covers as portions, batch.status, batch.started_at, batch.ready_at,
      batch.production_log_id, recipe.name as recipe_name, recipe.category,
      batch.started_at is null and batch.ready_at is null as legacy_time_unknown
    from public.production_batches as batch
    join public.recipes as recipe on recipe.id = batch.recipe_id
    where batch.service_date between start_date_value and end_date_value

    union all

    select
      'LOG-' || production.id,
      production.recipe_id,
      production.production_date,
      row_number() over (
        partition by production.recipe_id, production.production_date
        order by production.id
      )::integer,
      coalesce(
        production.covers_produced,
        greatest(0, round(recipe.batch_yield * production.quantity)::integer)
      ),
      'Ready'::text,
      null::timestamptz,
      null::timestamptz,
      production.id,
      recipe.name,
      recipe.category,
      true
    from public.production_logs as production
    join public.recipes as recipe on recipe.id = production.recipe_id
    where production.production_date between start_date_value and end_date_value
      and not exists (
        select 1
        from public.production_batches as batch
        where batch.production_log_id = production.id
      )
  ) as history_rows
  order by history_rows.service_date desc, history_rows.recipe_name,
    history_rows.batch_number desc;
end;
$$;

revoke all on function public.costtrack_start_production_batches(text, date, jsonb)
  from public, anon, authenticated;
revoke all on function public.costtrack_complete_production_batch(text)
  from public, anon, authenticated;
revoke all on function public.costtrack_load_production_history(date, date)
  from public, anon, authenticated;
grant execute on function public.costtrack_start_production_batches(text, date, jsonb)
  to authenticated;
grant execute on function public.costtrack_complete_production_batch(text)
  to authenticated;
grant execute on function public.costtrack_load_production_history(date, date)
  to authenticated;

commit;
