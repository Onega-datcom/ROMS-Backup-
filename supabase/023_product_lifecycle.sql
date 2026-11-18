begin;

create table if not exists public.product_lifecycle_audit (
  id uuid primary key default gen_random_uuid(),
  product_id text not null,
  product_name text not null,
  action text not null check (action in ('delete', 'deactivate', 'reactivate')),
  reason text not null,
  actor_id uuid not null,
  actor_name text not null,
  occurred_at timestamptz not null default clock_timestamp()
);
create index if not exists product_lifecycle_audit_product_time_idx
  on public.product_lifecycle_audit (product_id, occurred_at desc);

alter table public.product_lifecycle_audit enable row level security;
drop policy if exists product_lifecycle_audit_admin_read
  on public.product_lifecycle_audit;
create policy product_lifecycle_audit_admin_read
  on public.product_lifecycle_audit for select to authenticated
  using (public.has_app_role(array['Administrator']));
revoke all on table public.product_lifecycle_audit
  from public, anon, authenticated;
grant select on table public.product_lifecycle_audit to authenticated;

create or replace function public.costtrack_product_lifecycle(
  action_value text,
  product_id_value text,
  reason_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  product_row public.ingredients%rowtype;
  usage_counts jsonb;
  active_recipes jsonb;
  used_value boolean;
  usage_summary text;
  recipe_summary text;
  reason_text text;
  saved_updated_at timestamptz;
begin
  if not public.has_app_role(array['Administrator']) then
    raise exception 'Only Administrators may manage product lifecycle'
      using errcode = '42501';
  end if;
  if action_value not in ('inspect', 'delete', 'deactivate', 'reactivate') then
    raise exception 'Choose inspect, delete, deactivate, or reactivate'
      using errcode = '22023';
  end if;
  product_id_value := nullif(btrim(product_id_value), '');
  if product_id_value is null then
    raise exception 'A product ID is required' using errcode = '22023';
  end if;

  select * into product_row
  from public.ingredients
  where id = product_id_value
  for update;
  if not found then
    raise exception 'This product no longer exists';
  end if;

  select jsonb_build_object(
    'recipe_ingredients', (select count(*) from public.recipe_ingredients where ingredient_id = product_id_value),
    'dish_recipe_ingredients', (select count(*) from public.dish_recipe_ingredients where product_id = product_id_value),
    'inventory_transactions', (select count(*) from public.inventory_transactions where ingredient_id = product_id_value),
    'inventory_batches', (select count(*) from public.inventory_batches where product_id = product_id_value),
    'stock_movements', (select count(*) from public.stock_movements where product_id = product_id_value),
    'waste_logs', (select count(*) from public.waste_logs where ingredient_id = product_id_value),
    'physical_counts', (select count(*) from public.physical_counts where ingredient_id = product_id_value),
    'production_consumption', (select count(*) from public.production_consumption where product_id = product_id_value),
    'inventory_migration_issues', (
      select count(*) from public.inventory_migration_issues
      where (source_table = 'ingredients' and source_id = product_id_value)
         or details -> 'product_ids' ? product_id_value
    )
  ) into usage_counts;

  select exists (
    select 1
    from jsonb_each_text(usage_counts) as usage_item(key, value)
    where usage_item.value::bigint > 0
  ) into used_value;

  select coalesce(
    jsonb_agg(
      jsonb_build_object('id', active.id, 'name', active.name, 'source', active.source)
      order by active.name
    ),
    '[]'::jsonb
  ) into active_recipes
  from (
    select recipe.id, recipe.name, 'recipe'::text as source
    from public.recipes as recipe
    join public.recipe_ingredients as recipe_ingredient
      on recipe_ingredient.recipe_id = recipe.id
    where recipe_ingredient.ingredient_id = product_id_value
      and recipe.is_active
    union all
    select dish.id::text, dish.name, 'dish recipe'::text
    from public.dishes as dish
    join public.dish_recipe_versions as version
      on version.dish_id = dish.id and version.is_active
    join public.dish_recipe_ingredients as recipe_ingredient
      on recipe_ingredient.recipe_version_id = version.id
    where recipe_ingredient.product_id = product_id_value
      and dish.is_active
  ) as active;

  if action_value = 'inspect' then
    return jsonb_build_object(
      'product_id', product_row.id,
      'product_name', product_row.name,
      'is_active', product_row.is_active,
      'is_used', used_value,
      'usage', usage_counts,
      'active_recipes', active_recipes
    );
  end if;

  if action_value = 'delete' then
    if used_value then
      select string_agg(
        format('%s (%s)', usage_item.key, usage_item.value),
        ', ' order by usage_item.key
      ) into usage_summary
      from jsonb_each_text(usage_counts) as usage_item(key, value)
      where usage_item.value::bigint > 0;
      raise exception 'Cannot delete this product; it is referenced by: %. Deactivate it instead.',
        usage_summary using errcode = '23503';
    end if;

    insert into public.product_lifecycle_audit (
      product_id, product_name, action, reason, actor_id, actor_name
    ) values (
      product_row.id, product_row.name, 'delete',
      coalesce(nullif(btrim(reason_value), ''), 'Unused product deleted by Administrator'),
      auth.uid(),
      coalesce((
        select nullif(btrim(profile.full_name), '')
        from public.profiles as profile where profile.id = auth.uid()
      ), auth.uid()::text)
    );
    delete from public.ingredients where id = product_id_value;
    return jsonb_build_object(
      'action', 'delete', 'product_id', product_row.id,
      'product_name', product_row.name, 'is_active', null
    );
  end if;

  if action_value = 'deactivate' then
    reason_text := nullif(btrim(reason_value), '');
    if reason_text is null then
      raise exception 'A reason is required to deactivate a product'
        using errcode = '22023';
    end if;
    if length(reason_text) > 500 then
      raise exception 'The deactivation reason must be 500 characters or fewer'
        using errcode = '22023';
    end if;
    if jsonb_array_length(active_recipes) > 0 then
      select string_agg(active.value ->> 'name', ', ' order by active.value ->> 'name')
        into recipe_summary
      from jsonb_array_elements(active_recipes) as active(value);
      raise exception 'Deactivate or update these active recipes before deactivating this product: %',
        recipe_summary using errcode = '23514';
    end if;
    if not product_row.is_active then
      raise exception 'This product is already inactive';
    end if;

    update public.ingredients
    set is_active = false,
        updated_at = clock_timestamp(),
        updated_by = auth.uid()
    where id = product_id_value;
    select updated_at into saved_updated_at
    from public.ingredients where id = product_id_value;
    insert into public.product_lifecycle_audit (
      product_id, product_name, action, reason, actor_id, actor_name
    ) values (
      product_row.id, product_row.name, 'deactivate', reason_text, auth.uid(),
      coalesce((
        select nullif(btrim(profile.full_name), '')
        from public.profiles as profile where profile.id = auth.uid()
      ), auth.uid()::text)
    );
    return jsonb_build_object(
      'action', 'deactivate', 'product_id', product_row.id,
      'product_name', product_row.name, 'is_active', false,
      'updated_at', saved_updated_at
    );
  end if;

  if product_row.is_active then
    raise exception 'This product is already active';
  end if;
  reason_text := coalesce(
    nullif(btrim(reason_value), ''),
    'Product reactivated by Administrator'
  );
  if length(reason_text) > 500 then
    raise exception 'The reactivation reason must be 500 characters or fewer'
      using errcode = '22023';
  end if;
  update public.ingredients
  set is_active = true,
      updated_at = clock_timestamp(),
      updated_by = auth.uid()
  where id = product_id_value;
  select updated_at into saved_updated_at
  from public.ingredients where id = product_id_value;
  insert into public.product_lifecycle_audit (
    product_id, product_name, action, reason, actor_id, actor_name
  ) values (
    product_row.id, product_row.name, 'reactivate', reason_text, auth.uid(),
    coalesce((
      select nullif(btrim(profile.full_name), '')
      from public.profiles as profile where profile.id = auth.uid()
    ), auth.uid()::text)
  );
  return jsonb_build_object(
    'action', 'reactivate', 'product_id', product_row.id,
    'product_name', product_row.name, 'is_active', true,
    'updated_at', saved_updated_at
  );
end;
$$;
revoke all on function public.costtrack_product_lifecycle(text, text, text)
  from public, anon, authenticated;
grant execute on function public.costtrack_product_lifecycle(text, text, text)
  to authenticated;

create or replace function public.costtrack_require_active_product()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  product_id_value text;
begin
  if tg_table_name = 'dish_recipe_ingredients' then
    product_id_value := new.product_id;
  else
    product_id_value := new.ingredient_id;
  end if;
  if not exists (
    select 1 from public.ingredients
    where id = product_id_value and is_active
  ) then
    raise exception 'The selected product is missing or inactive'
      using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function public.costtrack_require_active_product()
  from public, anon, authenticated;

drop trigger if exists costtrack_recipe_ingredients_require_active_product
  on public.recipe_ingredients;
create trigger costtrack_recipe_ingredients_require_active_product
  before insert or update on public.recipe_ingredients
  for each row execute function public.costtrack_require_active_product();

drop trigger if exists costtrack_dish_recipe_ingredients_require_active_product
  on public.dish_recipe_ingredients;
create trigger costtrack_dish_recipe_ingredients_require_active_product
  before insert or update on public.dish_recipe_ingredients
  for each row execute function public.costtrack_require_active_product();

drop trigger if exists costtrack_inventory_transactions_require_active_product
  on public.inventory_transactions;
create trigger costtrack_inventory_transactions_require_active_product
  before insert or update on public.inventory_transactions
  for each row execute function public.costtrack_require_active_product();

drop trigger if exists costtrack_waste_logs_require_active_product
  on public.waste_logs;
create trigger costtrack_waste_logs_require_active_product
  before insert or update on public.waste_logs
  for each row execute function public.costtrack_require_active_product();

drop trigger if exists costtrack_physical_counts_require_active_product
  on public.physical_counts;
create trigger costtrack_physical_counts_require_active_product
  before insert or update on public.physical_counts
  for each row execute function public.costtrack_require_active_product();

commit;
