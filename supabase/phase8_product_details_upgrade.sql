-- Adds supplier, expiry-tracking, and notes fields to existing products.
-- Run after the full Phase 8 migration or the receiving invoice upgrade.

begin;

do $$
begin
  if to_regclass('public.ingredients') is null
     or to_regclass('public.product_categories') is null
     or to_regclass('public.units') is null
     or to_regclass('public.suppliers') is null
     or to_regclass('public.inventory_transactions') is null then
    raise exception
      'Apply the full Phase 8 migration and receiving invoice upgrade before this product details upgrade';
  end if;
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'inventory_transactions'
      and column_name = 'expiration_date'
  ) then
    raise exception
      'Run phase8_receiving_invoice_upgrade.sql before this product details upgrade';
  end if;
  if to_regprocedure('public.has_app_role(text[])') is null then
    raise exception 'Required role-check function public.has_app_role(text[]) is missing';
  end if;
end;
$$;

alter table public.ingredients
  add column if not exists preferred_supplier text not null default '',
  add column if not exists track_expiry boolean not null default false,
  add column if not exists notes text not null default '';

create or replace function public.costtrack_require_tracked_expiration()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if lower(new.transaction_type) in ('receiving', 'received')
     and new.expiration_date is null
     and exists (
       select 1
       from public.ingredients as i
       where i.id = new.ingredient_id and i.track_expiry
     ) then
    raise exception 'An expiration date is required for this product';
  end if;
  return new;
end;
$$;

drop trigger if exists costtrack_require_tracked_expiration
  on public.inventory_transactions;
create trigger costtrack_require_tracked_expiration
  before insert or update on public.inventory_transactions
  for each row execute function public.costtrack_require_tracked_expiration();

drop function if exists public.costtrack_load_products();
create function public.costtrack_load_products()
returns table (
  id text, name text, category text, unit text, cost numeric, stock numeric,
  minimum numeric, category_id uuid, unit_id uuid, threshold numeric,
  expiry_alert_days integer, preferred_supplier text, track_expiry boolean,
  notes text, is_active boolean, updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not public.has_app_role(array[
    'Administrator', 'Manager', 'Inventory Clerk', 'Chef / Kitchen Staff'
  ]) then
    raise exception 'Not authorized to read products' using errcode = '42501';
  end if;
  return query
  select i.id, i.name, i.category, i.unit,
         case when public.current_app_role() = 'Chef / Kitchen Staff'
              then null::numeric else i.cost end,
         i.stock, i.minimum, i.category_id, i.unit_id, i.threshold,
         i.expiry_alert_days, i.preferred_supplier, i.track_expiry, i.notes,
         i.is_active, i.updated_at
  from public.ingredients as i
  order by i.name;
end;
$$;

create or replace function public.costtrack_save_product(
  payload jsonb,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  product_id text;
  product_name text;
  category_name text;
  unit_name text;
  threshold_value numeric;
  preferred_supplier_value text;
  track_expiry_value boolean;
  notes_value text;
  category_key uuid;
  unit_key uuid;
  saved public.ingredients%rowtype;
begin
  if not public.has_app_role(array['Administrator']) then
    raise exception 'Only Administrators may manage products' using errcode = '42501';
  end if;
  if payload is null or jsonb_typeof(payload) is distinct from 'object' then
    raise exception 'Product payload must be a JSON object';
  end if;

  product_id := nullif(btrim(payload ->> 'id'), '');
  product_name := nullif(btrim(payload ->> 'name'), '');
  category_name := nullif(btrim(payload ->> 'category'), '');
  unit_name := nullif(btrim(payload ->> 'unit'), '');
  threshold_value := (payload ->> 'minimum')::numeric;
  preferred_supplier_value := coalesce(nullif(btrim(payload ->> 'preferred_supplier'), ''), '');
  track_expiry_value := coalesce((payload ->> 'track_expiry')::boolean, false);
  notes_value := coalesce(btrim(payload ->> 'notes'), '');
  if product_id is null or product_name is null or category_name is null
     or unit_name is null or threshold_value is null or threshold_value < 0 then
    raise exception 'Product id, name, category, unit, and a non-negative threshold are required';
  end if;
  if length(product_name) > 200 or length(preferred_supplier_value) > 200
     or length(notes_value) > 1000 then
    raise exception 'Product name, supplier, or notes are too long';
  end if;

  select c.id into category_key
  from public.product_categories as c
  where lower(c.name) = lower(category_name) and c.is_active;
  if category_key is null then
    raise exception 'Select an active product category';
  end if;

  select u.id into unit_key
  from public.units as u
  where lower(u.abbreviation) = lower(unit_name) and u.is_active;
  if unit_key is null then
    raise exception 'Select an active stocking unit';
  end if;

  if exists (
    select 1 from public.ingredients as i
    where i.id <> product_id
      and i.category_id = category_key
      and lower(btrim(i.name)) = lower(product_name)
  ) then
    raise exception 'A product with this name already exists in the selected category'
      using errcode = '23505';
  end if;

  if expected_updated_at is null then
    insert into public.ingredients (
      id, name, category, unit, cost, stock, minimum,
      category_id, unit_id, preferred_supplier, track_expiry, notes,
      created_by, updated_by
    )
    values (
      product_id, product_name, category_name, unit_name, 0, 0, threshold_value,
      category_key, unit_key, preferred_supplier_value, track_expiry_value,
      notes_value, auth.uid(), auth.uid()
    )
    returning * into saved;
  else
    update public.ingredients as i
    set name = product_name,
        category = category_name,
        unit = unit_name,
        minimum = threshold_value,
        category_id = category_key,
        unit_id = unit_key,
        preferred_supplier = case when payload ? 'preferred_supplier'
                                  then preferred_supplier_value else i.preferred_supplier end,
        track_expiry = case when payload ? 'track_expiry'
                            then track_expiry_value else i.track_expiry end,
        notes = case when payload ? 'notes' then notes_value else i.notes end,
        updated_at = clock_timestamp(),
        updated_by = auth.uid()
    where i.id = product_id and i.updated_at = expected_updated_at
    returning * into saved;
    if not found then
      raise exception 'This product changed in another session. Reload before saving.'
        using errcode = '40001';
    end if;
  end if;

  return jsonb_build_object(
    'id', saved.id, 'name', saved.name, 'category', saved.category,
    'unit', saved.unit, 'cost', saved.cost, 'stock', saved.stock,
    'minimum', saved.minimum, 'category_id', saved.category_id,
    'unit_id', saved.unit_id, 'threshold', saved.threshold,
    'expiry_alert_days', saved.expiry_alert_days,
    'preferred_supplier', saved.preferred_supplier,
    'track_expiry', saved.track_expiry, 'notes', saved.notes,
    'is_active', saved.is_active, 'updated_at', saved.updated_at
  );
end;
$$;

revoke all on function public.costtrack_require_tracked_expiration()
  from public, anon, authenticated;
revoke all on function public.costtrack_load_products()
  from public, anon;
revoke all on function public.costtrack_save_product(jsonb, timestamptz)
  from public, anon;
grant execute on function public.costtrack_load_products() to authenticated;
grant execute on function public.costtrack_save_product(jsonb, timestamptz)
  to authenticated;

commit;
