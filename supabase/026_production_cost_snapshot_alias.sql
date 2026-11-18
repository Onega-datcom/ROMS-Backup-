begin;

create or replace function public.apply_production_stock()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  ingredient_line record;
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
  elsif not exists (
    select 1
    from public.recipes as recipe
    where recipe.id = new.recipe_id and recipe.is_active
  ) then
    raise exception 'Inactive recipes cannot be used for new production'
      using errcode = '23514';
  end if;

  select round(
    coalesce(sum(recipe_ingredient.quantity * inventory.cost), 0)
      * (1 + coalesce(recipe.wastage, 0) / 100.0)
      * production_factor,
    4
  )
  into new.batch_cost_snapshot
  from public.recipes as recipe
  left join public.recipe_ingredients as recipe_ingredient
    on recipe_ingredient.recipe_id = recipe.id
  left join public.ingredients as inventory
    on inventory.id = recipe_ingredient.ingredient_id
  where recipe.id = new.recipe_id;
  new.cost_snapshot_at := clock_timestamp();

  prior_stock_permission := current_setting('costtrack.stock_movement', true);
  perform set_config('costtrack.stock_movement', 'on', true);
  for ingredient_line in
    select recipe_ingredient.ingredient_id, recipe_ingredient.quantity
    from public.recipe_ingredients as recipe_ingredient
    where recipe_ingredient.recipe_id = new.recipe_id
    order by recipe_ingredient.ingredient_id
  loop
    update public.ingredients
    set stock = stock - (ingredient_line.quantity * production_factor)
    where id = ingredient_line.ingredient_id
      and stock >= ingredient_line.quantity * production_factor;
    ingredient_updated := found;
    if not ingredient_updated then
      raise exception 'Production would make stock negative for ingredient %',
        ingredient_line.ingredient_id using errcode = '23514';
    end if;
  end loop;
  perform set_config('costtrack.stock_movement', coalesce(prior_stock_permission, ''), true);
  return new;
end;
$$;

revoke all on function public.apply_production_stock() from public, anon, authenticated;

commit;
