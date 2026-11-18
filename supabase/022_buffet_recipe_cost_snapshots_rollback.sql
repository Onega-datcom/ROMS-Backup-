begin;

drop trigger if exists production_batches_require_active_recipe
  on public.production_batches;
drop function if exists public.costtrack_require_active_recipe_for_production();

drop function if exists public.report_analytics(text, date, date, text, boolean);
create function public.report_analytics(
  report_key text,
  start_date date,
  end_date date,
  group_by text default 'day',
  include_waste boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if report_key in ('revenue', 'food_cost') then
    if not public.has_app_role(array['Administrator', 'Manager']) then
      raise exception 'Not authorized to read financial reports.'
        using errcode = '42501';
    end if;
    return public.pos_revenue_report(
      case when report_key = 'revenue' then 'daily_revenue' else 'food_cost' end,
      start_date, end_date, group_by, include_waste
    );
  end if;
  if not public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']) then
    raise exception 'Not authorized to read operational reports.'
      using errcode = '42501';
  end if;
  return public.costtrack_report_analytics_legacy(
    report_key, start_date, end_date, group_by, include_waste
  );
end;
$$;
revoke all on function public.report_analytics(text, date, date, text, boolean)
  from public, anon;
grant execute on function public.report_analytics(text, date, date, text, boolean)
  to authenticated;

drop function if exists public.pos_revenue_report(text, date, date, text, boolean, integer, integer);
do $$
begin
  if to_regprocedure(
    'public.costtrack_pos_revenue_report_legacy(text,date,date,text,boolean,integer,integer)'
  ) is not null then
    execute 'alter function public.costtrack_pos_revenue_report_legacy(text, date, date, text, boolean, integer, integer) rename to pos_revenue_report';
  end if;
end;
$$;
revoke all on function public.pos_revenue_report(text, date, date, text, boolean, integer, integer)
  from public, anon;
grant execute on function public.pos_revenue_report(text, date, date, text, boolean, integer, integer)
  to authenticated;

drop function if exists public.costtrack_food_cost_report_with_snapshots(date, date, text, boolean);
drop function if exists public.costtrack_production_report_with_snapshots(date, date);

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
    payload - 'batch_yield' - 'prep_target' - 'prep_notes' - 'is_active',
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
    case when public.current_app_role() = 'Chef / Kitchen Staff'
      then null::numeric else recipe.menu_price end,
    case when public.current_app_role() = 'Chef / Kitchen Staff'
      then null::numeric else recipe.wastage end,
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
revoke all on function public.apply_production_stock() from public, anon, authenticated;
drop trigger if exists apply_production_stock on public.production_logs;
create trigger apply_production_stock
  before insert or update or delete on public.production_logs
  for each row execute function public.apply_production_stock();

-- Keep is_active and historical snapshot columns so rollback never discards data.
commit;
