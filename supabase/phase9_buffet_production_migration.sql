begin;

alter table public.recipes
  add column if not exists batch_yield integer not null default 30
    check (batch_yield > 0),
  add column if not exists prep_target integer not null default 30
    check (prep_target > 0),
  add column if not exists prep_notes text not null default '';

create table if not exists public.production_batches (
  id text primary key,
  recipe_id text not null references public.recipes (id) on delete restrict,
  service_date date not null,
  batch_number integer not null check (batch_number > 0),
  batch_count integer not null default 1 check (batch_count > 0),
  batch_yield integer not null check (batch_yield > 0),
  expected_covers integer not null check (expected_covers >= 0),
  prep_target integer not null check (prep_target > 0),
  status text not null check (status in ('Cooking', 'Ready')),
  started_at timestamptz,
  started_by uuid references auth.users (id) on delete set null,
  ready_at timestamptz,
  ready_by uuid references auth.users (id) on delete set null,
  production_log_id text unique references public.production_logs (id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint production_batches_recipe_day_number_key
    unique (recipe_id, service_date, batch_number),
  constraint production_batches_completion_check
    check ((status = 'Cooking' and production_log_id is null and ready_at is null)
      or (status = 'Ready' and production_log_id is not null))
);

create index if not exists production_batches_service_date_status_idx
  on public.production_batches (service_date, status, started_at);
create index if not exists production_batches_recipe_service_date_idx
  on public.production_batches (recipe_id, service_date, batch_number);

insert into public.production_batches (
  id, recipe_id, service_date, batch_number, batch_count, batch_yield,
  expected_covers, prep_target, status, production_log_id
)
select
  'HIST-' || production.id,
  production.recipe_id,
  production.production_date,
  row_number() over (
    partition by production.recipe_id, production.production_date
    order by production.id
  )::integer,
  greatest(1, ceil(production.quantity)::integer),
  recipe.batch_yield,
  coalesce(
    production.covers_produced,
    greatest(0, round(recipe.batch_yield * production.quantity)::integer)
  ),
  recipe.prep_target,
  'Ready',
  production.id
from public.production_logs as production
join public.recipes as recipe on recipe.id = production.recipe_id
on conflict (id) do nothing;

drop function if exists public.costtrack_load_recipes();
create function public.costtrack_load_recipes()
returns table (
  id text, name text, category text, menu_price numeric, wastage numeric,
  batch_yield integer, prep_target integer, prep_notes text,
  updated_at timestamptz, ingredients jsonb
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']) then
    raise exception 'Not authorized to read recipes' using errcode = '42501';
  end if;
  return query
  select recipe.id, recipe.name, recipe.category,
    case when public.current_app_role() = 'Chef / Kitchen Staff' then null::numeric else recipe.menu_price end,
    case when public.current_app_role() = 'Chef / Kitchen Staff' then null::numeric else recipe.wastage end,
    recipe.batch_yield, recipe.prep_target, recipe.prep_notes, recipe.updated_at,
    coalesce(
      jsonb_agg(jsonb_build_object(
        'ingredient_id', recipe_ingredient.ingredient_id,
        'quantity', recipe_ingredient.quantity
      )) filter (where recipe_ingredient.ingredient_id is not null),
      '[]'::jsonb
    )
  from public.recipes as recipe
  left join public.recipe_ingredients as recipe_ingredient
    on recipe_ingredient.recipe_id = recipe.id
  group by recipe.id, recipe.name, recipe.category, recipe.menu_price,
    recipe.wastage, recipe.batch_yield, recipe.prep_target,
    recipe.prep_notes, recipe.updated_at
  order by recipe.name;
end;
$$;

revoke all on function public.costtrack_load_recipes() from public, anon, authenticated;
grant execute on function public.costtrack_load_recipes() to authenticated;

drop function if exists public.save_recipe(jsonb, timestamptz);
create function public.save_recipe(
  payload jsonb,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  batch_yield_value integer;
  prep_target_value integer;
  prep_notes_value text;
  saved_recipe jsonb;
  saved_updated_at timestamptz;
  recipe_id_value text;
begin
  if not public.has_app_role(array['Administrator', 'Manager']) then
    raise exception 'Only Administrators and Managers may manage recipes'
      using errcode = '42501';
  end if;
  if payload is null or jsonb_typeof(payload) is distinct from 'object' then
    raise exception 'Recipe payload must be a JSON object';
  end if;

  batch_yield_value := coalesce(nullif(payload ->> 'batch_yield', '')::integer, 30);
  prep_target_value := coalesce(nullif(payload ->> 'prep_target', '')::integer, 30);
  prep_notes_value := left(btrim(coalesce(payload ->> 'prep_notes', '')), 1000);
  if batch_yield_value <= 0 or prep_target_value <= 0 then
    raise exception 'Batch yield and prep target must be positive whole numbers';
  end if;

  saved_recipe := public.costtrack_save_recipe_legacy(
    payload - 'batch_yield' - 'prep_target' - 'prep_notes',
    expected_updated_at
  );
  recipe_id_value := saved_recipe ->> 'id';
  update public.recipes as recipe
  set batch_yield = batch_yield_value,
      prep_target = prep_target_value,
      prep_notes = prep_notes_value,
      updated_at = now()
  where recipe.id = recipe_id_value
  returning recipe.updated_at into saved_updated_at;

  return saved_recipe || jsonb_build_object(
    'batch_yield', batch_yield_value,
    'prep_target', prep_target_value,
    'prep_notes', prep_notes_value,
    'updated_at', saved_updated_at
  );
end;
$$;

revoke all on function public.save_recipe(jsonb, timestamptz)
  from public, anon, authenticated;
grant execute on function public.save_recipe(jsonb, timestamptz) to authenticated;

create or replace function public.costtrack_load_production_batches(service_date_value date)
returns table (
  id text,
  recipe_id text,
  service_date date,
  batch_number integer,
  batch_count integer,
  batch_yield integer,
  expected_covers integer,
  prep_target integer,
  status text,
  started_at timestamptz,
  started_by uuid,
  ready_at timestamptz,
  ready_by uuid,
  production_log_id text,
  recipe_name text,
  category text
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']) then
    raise exception 'Not authorized to read production batches'
      using errcode = '42501';
  end if;
  if service_date_value is null then
    raise exception 'A service date is required';
  end if;

  return query
  select batch.id, batch.recipe_id, batch.service_date, batch.batch_number,
    batch.batch_count, batch.batch_yield, batch.expected_covers, batch.prep_target,
    batch.status, batch.started_at, batch.started_by, batch.ready_at, batch.ready_by,
    batch.production_log_id, recipe.name, recipe.category
  from public.production_batches as batch
  join public.recipes as recipe on recipe.id = batch.recipe_id
  where batch.service_date = service_date_value
  order by recipe.category, recipe.name, batch.batch_number;
end;
$$;

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
  requested_id text;
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
    raise exception 'Choose a recipe, service date, and one to three batch IDs';
  end if;
  if exists (
    select 1 from jsonb_array_elements(batch_ids) as value
    where jsonb_typeof(value) is distinct from 'string'
      or nullif(btrim(value #>> '{}'), '') is null
  ) then
    raise exception 'Each batch needs a valid ID';
  end if;
  if (select count(distinct value #>> '{}') from jsonb_array_elements(batch_ids) as value)
     <> jsonb_array_length(batch_ids) then
    raise exception 'Batch IDs must be unique';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(recipe_id_value || ':' || service_date_value::text, 0));
  select * into recipe_record
  from public.recipes as recipe
  where recipe.id = recipe_id_value;
  if not found then
    raise exception 'The selected recipe no longer exists';
  end if;

  for requested_id in select value #>> '{}' from jsonb_array_elements(batch_ids) as value
  loop
    requested_ids := array_append(requested_ids, requested_id);
    select * into existing_batch
    from public.production_batches as batch
    where batch.id = requested_id
    for update;
    if found then
      if existing_batch.recipe_id <> recipe_id_value
         or existing_batch.service_date <> service_date_value then
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
      recipe_record.batch_yield, recipe_record.batch_yield, recipe_record.prep_target,
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
    id, recipe_id, quantity, covers_produced, production_date, mode
  ) values (
    production_log_id_value, batch.recipe_id, batch.batch_count,
    batch.expected_covers, batch.service_date,
    'Buffet batch #' || batch.batch_number
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

revoke all on function public.costtrack_load_production_batches(date)
  from public, anon, authenticated;
revoke all on function public.costtrack_start_production_batches(text, date, jsonb)
  from public, anon, authenticated;
revoke all on function public.costtrack_complete_production_batch(text)
  from public, anon, authenticated;
grant execute on function public.costtrack_load_production_batches(date) to authenticated;
grant execute on function public.costtrack_start_production_batches(text, date, jsonb) to authenticated;
grant execute on function public.costtrack_complete_production_batch(text) to authenticated;

alter table public.production_batches enable row level security;
drop policy if exists production_batches_read on public.production_batches;
create policy production_batches_read on public.production_batches
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']));
revoke all on table public.production_batches from public, anon, authenticated;
grant select on table public.production_batches to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'production_batches'
     ) then
    alter publication supabase_realtime add table public.production_batches;
  end if;
end;
$$;

commit;
