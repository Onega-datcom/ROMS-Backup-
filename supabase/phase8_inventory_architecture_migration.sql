-- CostTrack Phase 1: additive inventory and dish/recipe foundation.
-- Back up the project and resolve any reported migration issues before using
-- this migration in production. Existing operational rows are retained.

begin;

do $$
begin
  if to_regclass('public.ingredients') is null
     or to_regclass('public.recipes') is null
     or to_regclass('public.recipe_ingredients') is null
     or to_regclass('public.inventory_transactions') is null
     or to_regclass('public.production_logs') is null
     or to_regclass('public.waste_logs') is null
     or to_regclass('public.profiles') is null then
    raise exception 'Apply supabase-schema.sql before the Phase 1 inventory migration';
  end if;
end;
$$;

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);
create unique index if not exists product_categories_name_lower_uidx
  on public.product_categories (lower(name));

create table if not exists public.units (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  abbreviation text not null,
  dimension text not null check (dimension in ('weight', 'volume', 'count', 'unknown')),
  conversion_to_base numeric(18, 8),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  constraint units_conversion_valid check (
    (dimension = 'unknown' and conversion_to_base is null)
    or (dimension <> 'unknown' and conversion_to_base > 0)
  )
);
create unique index if not exists units_abbreviation_lower_uidx
  on public.units (lower(abbreviation));

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);
create unique index if not exists suppliers_name_lower_uidx
  on public.suppliers (lower(name));

alter table public.ingredients
  add column if not exists category_id uuid references public.product_categories (id) on delete restrict,
  add column if not exists unit_id uuid references public.units (id) on delete restrict,
  add column if not exists expiry_alert_days integer not null default 3 check (expiry_alert_days >= 0),
  add column if not exists preferred_supplier text not null default '',
  add column if not exists track_expiry boolean not null default false,
  add column if not exists notes text not null default '',
  add column if not exists is_active boolean not null default true,
  add column if not exists threshold numeric generated always as (minimum) stored,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists created_by uuid references auth.users (id) on delete set null,
  add column if not exists updated_by uuid references auth.users (id) on delete set null;

create table if not exists public.inventory_migration_issues (
  id uuid primary key default gen_random_uuid(),
  issue_code text not null,
  source_table text not null,
  source_id text not null,
  details jsonb not null default '{}'::jsonb,
  is_resolved boolean not null default false,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users (id) on delete set null,
  unique (issue_code, source_table, source_id)
);

insert into public.product_categories (name)
select distinct on (lower(category_name)) category_name
from (
  select coalesce(nullif(btrim(category), ''), 'Uncategorized') as category_name
  from public.ingredients
) as categories
order by lower(category_name), category_name
on conflict do nothing;

insert into public.product_categories (name)
values
  ('Dairy'), ('Dry Goods'), ('Meat'), ('Produce'),
  ('Sauces'), ('Pantry'), ('Uncategorized')
on conflict do nothing;

insert into public.units (name, abbreviation, dimension, conversion_to_base)
values
  ('Gram', 'g', 'weight', 1),
  ('Kilogram', 'kg', 'weight', 1000),
  ('Milliliter', 'ml', 'volume', 1),
  ('Liter', 'L', 'volume', 1000),
  ('Piece', 'pc', 'count', 1),
  ('Pieces', 'pcs', 'count', 1),
  ('Box', 'box', 'unknown', null)
on conflict do nothing;

insert into public.units (name, abbreviation, dimension, conversion_to_base)
select distinct on (lower(btrim(i.unit)))
  btrim(i.unit),
  btrim(i.unit),
  'unknown',
  null
from public.ingredients as i
where nullif(btrim(i.unit), '') is not null
  and not exists (
    select 1 from public.units as u where lower(u.abbreviation) = lower(btrim(i.unit))
  )
order by lower(btrim(i.unit)), btrim(i.unit)
on conflict do nothing;

update public.ingredients as i
set category_id = c.id
from public.product_categories as c
where lower(c.name) = lower(coalesce(nullif(btrim(i.category), ''), 'Uncategorized'))
  and i.category_id is distinct from c.id;

update public.ingredients as i
set unit_id = u.id
from public.units as u
where lower(u.abbreviation) = lower(btrim(i.unit))
  and i.unit_id is distinct from u.id;

insert into public.inventory_migration_issues (issue_code, source_table, source_id, details)
select 'unit_conversion_unconfigured', 'ingredients', i.id,
       jsonb_build_object('unit', i.unit, 'name', i.name)
from public.ingredients as i
join public.units as u on u.id = i.unit_id
where u.dimension = 'unknown'
on conflict (issue_code, source_table, source_id)
do update set details = excluded.details;

insert into public.inventory_migration_issues (issue_code, source_table, source_id, details)
select 'duplicate_product_name_in_category', 'ingredients', min(i.id),
       jsonb_build_object(
         'name', min(i.name),
         'category_id', i.category_id,
         'product_ids', jsonb_agg(i.id order by i.id)
       )
from public.ingredients as i
where i.category_id is not null
group by i.category_id, lower(btrim(i.name))
having count(*) > 1
on conflict (issue_code, source_table, source_id)
do update set details = excluded.details;

do $$
begin
  if not exists (
    select 1
    from public.ingredients
    group by category_id, lower(btrim(name))
    having count(*) > 1
  ) then
    create unique index if not exists ingredients_category_name_lower_uidx
      on public.ingredients (category_id, lower(btrim(name)));
  end if;
end;
$$;

create table if not exists public.inventory_batches (
  id uuid primary key default gen_random_uuid(),
  batch_code text not null,
  product_id text not null references public.ingredients (id) on delete restrict,
  receiving_id uuid,
  quantity_received numeric(18, 4) not null check (quantity_received > 0),
  quantity_remaining numeric(18, 4) not null check (
    quantity_remaining >= 0 and quantity_remaining <= quantity_received
  ),
  unit_cost numeric(18, 6) not null check (unit_cost >= 0),
  received_date date not null,
  expiration_date date,
  status text not null default 'Active'
    check (status in ('Active', 'Depleted', 'Expired', 'Voided')),
  is_opening_balance boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  constraint inventory_batches_expiration_check
    check (expiration_date is null or expiration_date >= received_date)
);
alter table public.inventory_batches
  drop constraint if exists inventory_batches_batch_code_key;
create unique index if not exists inventory_batches_product_batch_code_uidx
  on public.inventory_batches (product_id, batch_code);
create unique index if not exists inventory_batches_one_opening_balance_uidx
  on public.inventory_batches (product_id)
  where is_opening_balance;
create index if not exists inventory_batches_product_fifo_idx
  on public.inventory_batches (product_id, received_date, id)
  where status = 'Active';
create index if not exists inventory_batches_expiration_idx
  on public.inventory_batches (expiration_date)
  where status = 'Active' and expiration_date is not null;

alter table public.inventory_transactions
  add column if not exists supplier_name text not null default '',
  add column if not exists invoice_number text not null default '',
  add column if not exists invoice_date date,
  add column if not exists batch_code text,
  add column if not exists expiration_date date;

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

alter table public.inventory_batches
  add column if not exists source_transaction_id text
    references public.inventory_transactions (id) on delete restrict;
create unique index if not exists inventory_batches_source_transaction_uidx
  on public.inventory_batches (source_transaction_id)
  where source_transaction_id is not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.inventory_transactions'::regclass
      and conname = 'inventory_transactions_expiration_check'
  ) then
    alter table public.inventory_transactions
      add constraint inventory_transactions_expiration_check
      check (expiration_date is null or expiration_date >= transaction_date);
  end if;
end;
$$;

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id text not null references public.ingredients (id) on delete restrict,
  batch_id uuid not null references public.inventory_batches (id) on delete restrict,
  movement_type text not null check (movement_type in (
    'Opening balance', 'Received', 'Production', 'Waste',
    'Expired write-off', 'Count adjustment', 'Void reversal'
  )),
  quantity numeric(18, 4) not null check (quantity <> 0),
  unit_cost numeric(18, 6) not null check (unit_cost >= 0),
  reference_type text not null,
  reference_id text not null,
  user_id uuid references auth.users (id) on delete set null,
  note text not null default '',
  created_at timestamptz not null default now(),
  unique (movement_type, reference_type, reference_id, batch_id)
);
create index if not exists stock_movements_product_created_idx
  on public.stock_movements (product_id, created_at desc);
create index if not exists stock_movements_batch_created_idx
  on public.stock_movements (batch_id, created_at);

-- Existing on-hand stock becomes one dated opening balance; old movement rows
-- remain untouched and are not replayed into the new batch totals.
insert into public.inventory_batches (
  batch_code, product_id, quantity_received, quantity_remaining, unit_cost,
  received_date, expiration_date, status, is_opening_balance
)
select
  'OPEN-' || substr(md5(i.id), 1, 16),
  i.id,
  i.stock,
  i.stock,
  i.cost,
  current_date,
  null,
  case when i.stock > 0 then 'Active' else 'Depleted' end,
  true
from public.ingredients as i
where i.stock > 0
on conflict (product_id) where is_opening_balance do nothing;

insert into public.stock_movements (
  product_id, batch_id, movement_type, quantity, unit_cost,
  reference_type, reference_id, note
)
select
  b.product_id, b.id, 'Opening balance', b.quantity_received, b.unit_cost,
  'migration', b.product_id, 'Migrated from existing current stock; expiry unknown.'
from public.inventory_batches as b
where b.is_opening_balance
  and not exists (
    select 1 from public.stock_movements as m
    where m.movement_type = 'Opening balance'
      and m.reference_type = 'migration'
      and m.reference_id = b.product_id
      and m.batch_id = b.id
  );

create table if not exists public.inventory_settings (
  id boolean primary key default true check (id),
  consumption_method text not null default 'FIFO'
    check (consumption_method in ('FIFO', 'FEFO')),
  default_expiry_alert_days integer not null default 3
    check (default_expiry_alert_days >= 0),
  allow_production_override boolean not null default false,
  email_notifications boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);
insert into public.inventory_settings (id) values (true)
on conflict (id) do nothing;

create table if not exists public.food_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);
create unique index if not exists food_categories_name_lower_uidx
  on public.food_categories (lower(name));

create table if not exists public.dishes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  food_category_id uuid not null references public.food_categories (id) on delete restrict,
  serving_unit text not null default 'Batch',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);
create unique index if not exists dishes_category_name_lower_uidx
  on public.dishes (food_category_id, lower(name));

create table if not exists public.dish_recipe_versions (
  id uuid primary key default gen_random_uuid(),
  dish_id uuid not null references public.dishes (id) on delete restrict,
  version integer not null check (version > 0),
  yield_per_serving_unit numeric(18, 4) not null default 1
    check (yield_per_serving_unit > 0),
  is_active boolean not null default true,
  legacy_recipe_id text unique references public.recipes (id) on delete restrict,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  unique (dish_id, version)
);
create unique index if not exists dish_recipe_one_active_version_uidx
  on public.dish_recipe_versions (dish_id)
  where is_active;

create table if not exists public.dish_recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_version_id uuid not null references public.dish_recipe_versions (id) on delete restrict,
  product_id text not null references public.ingredients (id) on delete restrict,
  quantity_per_serving_unit numeric(18, 4) not null
    check (quantity_per_serving_unit > 0),
  unit_id uuid not null references public.units (id) on delete restrict,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  unique (recipe_version_id, product_id)
);

create table if not exists public.legacy_recipe_mappings (
  legacy_recipe_id text primary key references public.recipes (id) on delete restrict,
  dish_id uuid not null references public.dishes (id) on delete restrict,
  recipe_version_id uuid not null unique references public.dish_recipe_versions (id) on delete restrict,
  mapping_status text not null default 'mapped',
  note text not null default '',
  created_at timestamptz not null default now()
);

insert into public.food_categories (name)
select distinct on (lower(category_name)) category_name
from (
  select coalesce(nullif(btrim(category), ''), 'Uncategorized') as category_name
  from public.recipes
) as categories
order by lower(category_name), category_name
on conflict do nothing;

insert into public.dishes (name, food_category_id, serving_unit)
select distinct on (fc.id, lower(btrim(r.name)))
  btrim(r.name), fc.id, 'Batch'
from public.recipes as r
join public.food_categories as fc
  on lower(fc.name) = lower(coalesce(nullif(btrim(r.category), ''), 'Uncategorized'))
order by fc.id, lower(btrim(r.name)), r.name
on conflict do nothing;

with unmapped as (
  select r.id as legacy_recipe_id, d.id as dish_id,
         coalesce((select max(v.version) from public.dish_recipe_versions as v where v.dish_id = d.id), 0)
         + row_number() over (
             partition by d.id
             order by r.updated_at, r.id
           ) as next_version,
         row_number() over (
           partition by d.id
           order by r.updated_at desc nulls last, r.id desc
         ) = 1 as is_active,
         r.updated_at
  from public.recipes as r
  join public.food_categories as fc
    on lower(fc.name) = lower(coalesce(nullif(btrim(r.category), ''), 'Uncategorized'))
  join public.dishes as d
    on d.food_category_id = fc.id
   and lower(btrim(d.name)) = lower(btrim(r.name))
  where not exists (
    select 1 from public.dish_recipe_versions as v where v.legacy_recipe_id = r.id
  )
)
insert into public.dish_recipe_versions (
  dish_id, version, yield_per_serving_unit, is_active,
  legacy_recipe_id, created_at
)
select dish_id, next_version, 1, is_active, legacy_recipe_id, coalesce(updated_at, now())
from unmapped
on conflict do nothing;

insert into public.legacy_recipe_mappings (
  legacy_recipe_id, dish_id, recipe_version_id, mapping_status, note
)
select
  v.legacy_recipe_id,
  v.dish_id,
  v.id,
  'mapped',
  'Legacy recipe quantities are interpreted in the existing product stocking units; verify before using for new production.'
from public.dish_recipe_versions as v
where v.legacy_recipe_id is not null
on conflict (legacy_recipe_id) do nothing;

insert into public.dish_recipe_ingredients (
  recipe_version_id, product_id, quantity_per_serving_unit, unit_id
)
select
  m.recipe_version_id, ri.ingredient_id, ri.quantity, i.unit_id
from public.legacy_recipe_mappings as m
join public.recipe_ingredients as ri on ri.recipe_id = m.legacy_recipe_id
join public.ingredients as i on i.id = ri.ingredient_id
where i.unit_id is not null
on conflict (recipe_version_id, product_id) do nothing;

insert into public.inventory_migration_issues (issue_code, source_table, source_id, details)
select
  'recipe_unit_needs_review',
  'recipes',
  r.id,
  jsonb_build_object('recipe', r.name, 'product', i.name, 'unit', i.unit)
from public.recipes as r
join public.recipe_ingredients as ri on ri.recipe_id = r.id
join public.ingredients as i on i.id = ri.ingredient_id
join public.units as u on u.id = i.unit_id
where u.dimension = 'unknown'
on conflict (issue_code, source_table, source_id)
do update set details = excluded.details;

create table if not exists public.legacy_production_mappings (
  production_log_id text primary key references public.production_logs (id) on delete restrict,
  legacy_recipe_id text not null references public.recipes (id) on delete restrict,
  dish_id uuid references public.dishes (id) on delete restrict,
  recipe_version_id uuid references public.dish_recipe_versions (id) on delete restrict,
  mapping_status text not null,
  note text not null default '',
  created_at timestamptz not null default now()
);
insert into public.legacy_production_mappings (
  production_log_id, legacy_recipe_id, dish_id, recipe_version_id, mapping_status, note
)
select
  p.id, p.recipe_id, m.dish_id, m.recipe_version_id,
  case when m.recipe_version_id is null then 'needs_review' else 'mapped_for_reference_only' end,
  'Historical production is read-only. The current recipe mapping is not asserted to be the recipe or cost used on the production date.'
from public.production_logs as p
left join public.legacy_recipe_mappings as m on m.legacy_recipe_id = p.recipe_id
on conflict (production_log_id) do nothing;

insert into public.inventory_migration_issues (issue_code, source_table, source_id, details)
select 'production_recipe_mapping_missing', 'production_logs', p.id,
       jsonb_build_object('legacy_recipe_id', p.recipe_id)
from public.production_logs as p
left join public.legacy_recipe_mappings as m on m.legacy_recipe_id = p.recipe_id
where m.legacy_recipe_id is null
on conflict (issue_code, source_table, source_id)
do update set details = excluded.details;

alter table public.production_logs
  add column if not exists is_legacy boolean not null default true;
alter table public.waste_logs
  add column if not exists is_legacy boolean not null default true;
alter table public.inventory_transactions
  add column if not exists is_legacy boolean not null default true;

create table if not exists public.production_consumption (
  id uuid primary key default gen_random_uuid(),
  production_id text not null references public.production_logs (id) on delete restrict,
  product_id text not null references public.ingredients (id) on delete restrict,
  batch_id uuid not null references public.inventory_batches (id) on delete restrict,
  quantity_used numeric(18, 4) not null check (quantity_used > 0),
  unit_cost numeric(18, 6) not null check (unit_cost >= 0),
  cost numeric(20, 6) not null check (cost >= 0),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null
);
create index if not exists production_consumption_production_idx
  on public.production_consumption (production_id);
create index if not exists production_consumption_product_idx
  on public.production_consumption (product_id, created_at desc);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in (
    'Low stock', 'Out of stock', 'Expiring soon', 'Expired',
    'New product request', 'Missing revenue entry'
  )),
  severity text not null check (severity in ('info', 'warning', 'critical')),
  message text not null,
  target_roles text[] not null,
  reference_type text,
  reference_id text,
  is_read boolean not null default false,
  is_resolved boolean not null default false,
  dedupe_key text not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_by uuid references auth.users (id) on delete set null
);
create unique index if not exists notifications_unresolved_dedupe_uidx
  on public.notifications (dedupe_key) where not is_resolved;
create index if not exists notifications_target_created_idx
  on public.notifications using gin (target_roles);

create or replace function public.costtrack_record_received_batch()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  batch_id_value uuid;
  batch_code_value text;
begin
  if lower(new.transaction_type) not in ('receiving', 'received') then
    return new;
  end if;

  batch_code_value := coalesce(
    nullif(btrim(new.batch_code), ''),
    'RCV-' || upper(substr(md5(new.id), 1, 12))
  );

  insert into public.inventory_batches (
    batch_code, product_id, source_transaction_id, quantity_received,
    quantity_remaining, unit_cost, received_date, expiration_date, status,
    is_opening_balance, created_by, updated_by
  )
  values (
    batch_code_value, new.ingredient_id, new.id, new.quantity,
    new.quantity, new.unit_cost, new.transaction_date, new.expiration_date,
    case when new.expiration_date < current_date then 'Expired' else 'Active' end,
    false, auth.uid(), auth.uid()
  )
  returning id into batch_id_value;

  insert into public.stock_movements (
    product_id, batch_id, movement_type, quantity, unit_cost,
    reference_type, reference_id, user_id, note
  )
  values (
    new.ingredient_id, batch_id_value, 'Received', new.quantity, new.unit_cost,
    'inventory_transaction', new.id, auth.uid(),
    concat_ws(' · ', nullif(new.supplier_name, ''), nullif(new.invoice_number, ''), nullif(new.note, ''))
  );

  return new;
end;
$$;

drop trigger if exists costtrack_record_received_batch on public.inventory_transactions;
create trigger costtrack_record_received_batch
  after insert on public.inventory_transactions
  for each row execute function public.costtrack_record_received_batch();

create or replace function public.costtrack_receive_delivery(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  supplier_value text;
  invoice_value text;
  invoice_date_value date;
  received_date_value date;
  note_value text;
  line jsonb;
  line_id text;
  ingredient_id_value text;
  existing_transaction public.inventory_transactions%rowtype;
  quantity_value numeric;
  unit_cost_value numeric;
  batch_code_value text;
  expiration_date_value date;
  line_count integer := 0;
  invoice_total numeric := 0;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']) then
    raise exception 'Not authorized to receive inventory'
      using errcode = '42501';
  end if;
  if payload is null or jsonb_typeof(payload) is distinct from 'object' then
    raise exception 'Delivery payload must be a JSON object';
  end if;

  supplier_value := nullif(btrim(payload ->> 'supplier_name'), '');
  invoice_value := nullif(btrim(payload ->> 'invoice_number'), '');
  invoice_date_value := nullif(payload ->> 'invoice_date', '')::date;
  received_date_value := nullif(payload ->> 'received_date', '')::date;
  note_value := coalesce(nullif(btrim(payload ->> 'note'), ''), '');

  if supplier_value is null or invoice_value is null
     or invoice_date_value is null or received_date_value is null then
    raise exception 'Supplier, invoice number, invoice date, and received date are required';
  end if;
  if jsonb_typeof(payload -> 'lines') is distinct from 'array' then
    raise exception 'Delivery product lines must be a JSON array';
  end if;
  if jsonb_array_length(payload -> 'lines') < 1
     or jsonb_array_length(payload -> 'lines') > 50 then
    raise exception 'A delivery must contain between 1 and 50 product lines';
  end if;

  for line in select value from jsonb_array_elements(payload -> 'lines')
  loop
    line_id := nullif(btrim(line ->> 'id'), '');
    ingredient_id_value := nullif(btrim(line ->> 'ingredient_id'), '');
    quantity_value := nullif(line ->> 'quantity', '')::numeric;
    unit_cost_value := nullif(line ->> 'unit_cost', '')::numeric;
    batch_code_value := nullif(btrim(line ->> 'batch_code'), '');
    expiration_date_value := nullif(line ->> 'expiration_date', '')::date;

    if jsonb_typeof(line) is distinct from 'object'
       or line_id is null or ingredient_id_value is null
       or quantity_value is null or quantity_value <= 0
       or unit_cost_value is null or unit_cost_value < 0 then
      raise exception 'Each product line requires an id, product, positive quantity, and non-negative unit cost';
    end if;
    if quantity_value::text in ('NaN', 'Infinity', '-Infinity')
       or quantity_value <> round(quantity_value, 4) then
      raise exception 'Product quantities may have no more than 4 decimal places';
    end if;
    if unit_cost_value::text in ('NaN', 'Infinity', '-Infinity')
       or unit_cost_value <> round(unit_cost_value, 6) then
      raise exception 'Unit costs may have no more than 6 decimal places';
    end if;
    if expiration_date_value is not null and expiration_date_value < received_date_value then
      raise exception 'A product expiration date cannot be before its received date';
    end if;
    if not exists (
      select 1 from public.ingredients as i
      where i.id = ingredient_id_value and i.is_active
    ) then
      raise exception 'A selected product is missing or inactive';
    end if;

    select * into existing_transaction
    from public.inventory_transactions as t
    where t.id = line_id;
    if found then
      if existing_transaction.ingredient_id is distinct from ingredient_id_value
         or existing_transaction.quantity is distinct from quantity_value
         or existing_transaction.unit_cost is distinct from unit_cost_value
         or existing_transaction.transaction_date is distinct from received_date_value
         or existing_transaction.transaction_type is distinct from 'Receiving'
         or existing_transaction.note is distinct from note_value
         or existing_transaction.supplier_name is distinct from supplier_value
         or existing_transaction.invoice_number is distinct from invoice_value
         or existing_transaction.invoice_date is distinct from invoice_date_value
         or existing_transaction.batch_code is distinct from batch_code_value
         or existing_transaction.expiration_date is distinct from expiration_date_value then
        raise exception 'A delivery line id was already used for different receipt data';
      end if;
      line_count := line_count + 1;
      invoice_total := invoice_total + (quantity_value * unit_cost_value);
      continue;
    end if;

    insert into public.inventory_transactions (
      id, ingredient_id, quantity, unit_cost, transaction_date,
      transaction_type, note, supplier_name, invoice_number, invoice_date,
      batch_code, expiration_date
    )
    values (
      line_id, ingredient_id_value, quantity_value, unit_cost_value,
      received_date_value, 'Receiving', note_value, supplier_value,
      invoice_value, invoice_date_value, batch_code_value, expiration_date_value
    );

    line_count := line_count + 1;
    invoice_total := invoice_total + (quantity_value * unit_cost_value);
  end loop;

  return jsonb_build_object(
    'invoice_number', invoice_value,
    'line_count', line_count,
    'invoice_total', invoice_total
  );
end;
$$;

alter table public.product_categories enable row level security;
alter table public.units enable row level security;
alter table public.suppliers enable row level security;
alter table public.inventory_batches enable row level security;
alter table public.stock_movements enable row level security;
alter table public.inventory_settings enable row level security;
alter table public.food_categories enable row level security;
alter table public.dishes enable row level security;
alter table public.dish_recipe_versions enable row level security;
alter table public.dish_recipe_ingredients enable row level security;
alter table public.legacy_recipe_mappings enable row level security;
alter table public.legacy_production_mappings enable row level security;
alter table public.inventory_migration_issues enable row level security;
alter table public.production_consumption enable row level security;
alter table public.notifications enable row level security;

drop policy if exists ingredients_read on public.ingredients;
create policy ingredients_read on public.ingredients
  for select to authenticated
  using (public.has_app_role(array[
    'Administrator', 'Manager', 'Inventory Clerk'
  ]));
drop policy if exists ingredients_insert on public.ingredients;
drop policy if exists ingredients_update on public.ingredients;
drop policy if exists ingredients_delete on public.ingredients;

drop policy if exists recipes_read on public.recipes;
create policy recipes_read on public.recipes
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));
drop policy if exists recipes_insert on public.recipes;
drop policy if exists recipes_update on public.recipes;
drop policy if exists recipes_delete on public.recipes;

drop policy if exists recipe_ingredients_read on public.recipe_ingredients;
create policy recipe_ingredients_read on public.recipe_ingredients
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));
drop policy if exists recipe_ingredients_insert on public.recipe_ingredients;
drop policy if exists recipe_ingredients_update on public.recipe_ingredients;
drop policy if exists recipe_ingredients_delete on public.recipe_ingredients;

drop policy if exists waste_logs_read on public.waste_logs;
create policy waste_logs_read on public.waste_logs
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']));
drop policy if exists waste_logs_insert on public.waste_logs;
create policy waste_logs_insert on public.waste_logs
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']));

drop policy if exists physical_counts_insert on public.physical_counts;
create policy physical_counts_insert on public.physical_counts
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Inventory Clerk']));

drop policy if exists product_categories_read on public.product_categories;
create policy product_categories_read on public.product_categories
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk', 'Chef / Kitchen Staff']));
drop policy if exists units_read on public.units;
create policy units_read on public.units
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk', 'Chef / Kitchen Staff']));
drop policy if exists suppliers_read on public.suppliers;
create policy suppliers_read on public.suppliers
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));
drop policy if exists inventory_batches_read on public.inventory_batches;
create policy inventory_batches_read on public.inventory_batches
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));
drop policy if exists stock_movements_read on public.stock_movements;
create policy stock_movements_read on public.stock_movements
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));
drop policy if exists inventory_settings_read on public.inventory_settings;
create policy inventory_settings_read on public.inventory_settings
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));
drop policy if exists food_categories_read on public.food_categories;
create policy food_categories_read on public.food_categories
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']));
drop policy if exists dishes_read on public.dishes;
create policy dishes_read on public.dishes
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']));
drop policy if exists dish_recipe_versions_read on public.dish_recipe_versions;
create policy dish_recipe_versions_read on public.dish_recipe_versions
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));
drop policy if exists dish_recipe_ingredients_read on public.dish_recipe_ingredients;
create policy dish_recipe_ingredients_read on public.dish_recipe_ingredients
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));
drop policy if exists legacy_recipe_mappings_read on public.legacy_recipe_mappings;
create policy legacy_recipe_mappings_read on public.legacy_recipe_mappings
  for select to authenticated using (public.has_app_role(array['Administrator']));
drop policy if exists legacy_production_mappings_read on public.legacy_production_mappings;
create policy legacy_production_mappings_read on public.legacy_production_mappings
  for select to authenticated using (public.has_app_role(array['Administrator']));
drop policy if exists inventory_migration_issues_read on public.inventory_migration_issues;
create policy inventory_migration_issues_read on public.inventory_migration_issues
  for select to authenticated using (public.has_app_role(array['Administrator']));
drop policy if exists production_consumption_read on public.production_consumption;
create policy production_consumption_read on public.production_consumption
  for select to authenticated using (public.has_app_role(array['Administrator', 'Manager']));
drop policy if exists notifications_read on public.notifications;
create policy notifications_read on public.notifications
  for select to authenticated
  using (public.current_app_role() = any (target_roles));

revoke all on table
  public.product_categories, public.units, public.suppliers,
  public.inventory_batches, public.stock_movements, public.inventory_settings,
  public.food_categories, public.dishes, public.dish_recipe_versions,
  public.dish_recipe_ingredients, public.legacy_recipe_mappings,
  public.legacy_production_mappings, public.inventory_migration_issues,
  public.production_consumption, public.notifications
from public, anon, authenticated;
grant select on table
  public.product_categories, public.units, public.suppliers,
  public.inventory_batches, public.stock_movements, public.inventory_settings,
  public.food_categories, public.dishes, public.dish_recipe_versions,
  public.dish_recipe_ingredients, public.legacy_recipe_mappings,
  public.legacy_production_mappings, public.inventory_migration_issues,
  public.production_consumption, public.notifications
to authenticated;
revoke insert, update, delete on table public.ingredients from public, anon, authenticated;
revoke insert, update, delete on table public.recipes from public, anon, authenticated;
revoke insert, update, delete on table public.recipe_ingredients from public, anon, authenticated;
revoke update, delete on table public.inventory_transactions from public, anon, authenticated;
revoke update, delete on table public.production_logs from public, anon, authenticated;
revoke update, delete on table public.waste_logs from public, anon, authenticated;
revoke update, delete on table public.physical_counts from public, anon, authenticated;

drop function if exists public.costtrack_load_products();
create or replace function public.costtrack_load_products()
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
         case when public.current_app_role() = 'Chef / Kitchen Staff' then null::numeric else i.cost end,
         i.stock, i.minimum, i.category_id, i.unit_id, i.threshold,
         i.expiry_alert_days, i.preferred_supplier, i.track_expiry, i.notes,
         i.is_active, i.updated_at
  from public.ingredients as i
  order by i.name;
end;
$$;

create or replace function public.costtrack_load_recipes()
returns table (
  id text, name text, category text, menu_price numeric, wastage numeric,
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
  select r.id, r.name, r.category,
         case when public.current_app_role() = 'Chef / Kitchen Staff' then null::numeric else r.menu_price end,
         case when public.current_app_role() = 'Chef / Kitchen Staff' then null::numeric else r.wastage end,
         r.updated_at,
         coalesce(
           jsonb_agg(jsonb_build_object(
             'ingredient_id', ri.ingredient_id,
             'quantity', ri.quantity
           )) filter (where ri.ingredient_id is not null),
           '[]'::jsonb
         )
  from public.recipes as r
  left join public.recipe_ingredients as ri on ri.recipe_id = r.id
  group by r.id, r.name, r.category, r.menu_price, r.wastage, r.updated_at
  order by r.name;
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
    'is_active', saved.is_active,
    'updated_at', saved.updated_at
  );
end;
$$;

do $$
begin
  if to_regprocedure('public.costtrack_save_recipe_legacy(jsonb,timestamptz)') is null then
    alter function public.save_recipe(jsonb, timestamptz)
      rename to costtrack_save_recipe_legacy;
  end if;
end;
$$;
revoke all on function public.costtrack_save_recipe_legacy(jsonb, timestamptz)
  from public, anon, authenticated;
create or replace function public.save_recipe(
  payload jsonb,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not public.has_app_role(array['Administrator', 'Manager']) then
    raise exception 'Only Administrators and Managers may manage recipes'
      using errcode = '42501';
  end if;
  return public.costtrack_save_recipe_legacy(payload, expected_updated_at);
end;
$$;

do $$
begin
  if to_regprocedure('public.costtrack_report_analytics_legacy(text,date,date,text,boolean)') is null then
    alter function public.report_analytics(text, date, date, text, boolean)
      rename to costtrack_report_analytics_legacy;
  end if;
end;
$$;
revoke all on function public.costtrack_report_analytics_legacy(text, date, date, text, boolean)
  from public, anon, authenticated;
create or replace function public.report_analytics(
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
  if not public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']) then
    raise exception 'Not authorized to read financial or operational reports'
      using errcode = '42501';
  end if;
  return public.costtrack_report_analytics_legacy(
    report_key, start_date, end_date, group_by, include_waste
  );
end;
$$;

revoke all on function public.costtrack_load_products() from public, anon;
revoke all on function public.costtrack_load_recipes() from public, anon;
revoke all on function public.costtrack_save_product(jsonb, timestamptz) from public, anon;
revoke all on function public.costtrack_require_tracked_expiration() from public, anon, authenticated;
revoke all on function public.costtrack_receive_delivery(jsonb) from public, anon;
revoke all on function public.save_recipe(jsonb, timestamptz) from public, anon;
revoke all on function public.report_analytics(text, date, date, text, boolean) from public, anon;
grant execute on function public.costtrack_load_products() to authenticated;
grant execute on function public.costtrack_load_recipes() to authenticated;
grant execute on function public.costtrack_save_product(jsonb, timestamptz) to authenticated;
grant execute on function public.costtrack_receive_delivery(jsonb) to authenticated;
grant execute on function public.save_recipe(jsonb, timestamptz) to authenticated;
grant execute on function public.report_analytics(text, date, date, text, boolean) to authenticated;

commit;
