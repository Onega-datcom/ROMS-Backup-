-- CostTrack typed Supabase schema.
-- Run this script as a database owner in the Supabase SQL editor. It is
-- intentionally rerunnable and backfills supported app_records collections;
-- demo users are excluded and the original JSON rows remain archived/locked.
-- Provision staff manually: create/confirm the user in Supabase Auth, copy its
-- Auth user UUID, then insert the matching profile as an administrator:
--   insert into public.profiles (id, email, full_name, role)
--   values ('<AUTH_USER_UUID>'::uuid, '<EMAIL>', '<FULL_NAME>', 'Administrator');
-- Repeat with an allowed role for each real user; never insert demo credentials.

-- Lock the old JSON endpoint before making any schema changes. The rows remain
-- available to this migration as the database owner, but not through the API.
do $$
declare
  policy_row record;
begin
  if to_regclass('public.app_records') is not null then
    alter table public.app_records enable row level security;
    for policy_row in
      select policyname
      from pg_policies
      where schemaname = 'public' and tablename = 'app_records'
    loop
      execute format('drop policy if exists %I on public.app_records', policy_row.policyname);
    end loop;
    revoke all on table public.app_records from public, anon, authenticated;
  end if;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text not null default '',
  role text not null check (role in (
    'Administrator',
    'Manager',
    'Chef / Kitchen Staff',
    'Receptionist',
    'Inventory Clerk'
  )),
  updated_at timestamptz not null default now()
);

create unique index if not exists profiles_email_lower_uidx
  on public.profiles (lower(email));

create table if not exists public.ingredients (
  id text primary key,
  name text not null,
  category text not null default '',
  unit text not null,
  cost numeric not null default 0 check (cost >= 0),
  stock numeric not null default 0 check (stock >= 0),
  minimum numeric not null default 0 check (minimum >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.recipes (
  id text primary key,
  name text not null,
  category text not null default '',
  price numeric not null default 0 check (price >= 0),
  wastage numeric not null default 0 check (wastage >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.recipe_ingredients (
  recipe_id text not null references public.recipes (id) on delete cascade,
  ingredient_id text not null references public.ingredients (id) on delete restrict,
  quantity numeric not null check (quantity > 0),
  updated_at timestamptz not null default now(),
  primary key (recipe_id, ingredient_id)
);

create table if not exists public.inventory_transactions (
  id text primary key,
  ingredient_id text not null references public.ingredients (id) on delete restrict,
  quantity numeric not null check (quantity <> 0),
  unit_cost numeric not null default 0 check (unit_cost >= 0),
  transaction_date date not null default current_date,
  transaction_type text not null,
  note text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.production_logs (
  id text primary key,
  recipe_id text not null references public.recipes (id) on delete restrict,
  quantity numeric not null check (quantity > 0),
  production_date date not null default current_date,
  mode text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.waste_logs (
  id text primary key,
  ingredient_id text not null references public.ingredients (id) on delete restrict,
  quantity numeric not null check (quantity > 0),
  reason text not null default '',
  waste_date date not null default current_date,
  updated_at timestamptz not null default now()
);

create table if not exists public.physical_counts (
  id text primary key,
  ingredient_id text not null references public.ingredients (id) on delete restrict,
  expected numeric not null check (expected >= 0),
  actual numeric not null check (actual >= 0),
  count_date date not null default current_date,
  updated_at timestamptz not null default now()
);

create table if not exists public.revenue_records (
  id text primary key,
  business_date date not null,
  meal_period text not null,
  adult_customers integer not null default 0 check (adult_customers >= 0),
  adult_rate numeric not null default 0 check (adult_rate >= 0),
  child_customers integer not null default 0 check (child_customers >= 0),
  child_rate numeric not null default 0 check (child_rate >= 0),
  senior_pwd_customers integer not null default 0 check (senior_pwd_customers >= 0),
  senior_pwd_rate numeric not null default 0 check (senior_pwd_rate >= 0),
  status text not null default 'Active' check (status in ('Active', 'Voided')),
  remarks text not null default '',
  recorded_by text not null default '',
  recorded_at timestamptz not null default now(),
  last_edited_by text not null default '',
  last_edited_at timestamptz,
  edit_reason text not null default '',
  voided_by text not null default '',
  void_reason text not null default '',
  voided_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.reservations (
  id text primary key,
  name text not null,
  email text,
  phone text,
  reservation_date date not null,
  reservation_time text not null,
  guests integer not null check (guests > 0),
  adults integer not null default 0 check (adults >= 0),
  children integer not null default 0 check (children >= 0),
  occasion text not null default '',
  status text not null default 'Pending',
  preference text not null default '',
  request text not null default '',
  table_id text,
  estimated_revenue numeric check (estimated_revenue is null or estimated_revenue >= 0),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reservations_contact_check check (
    nullif(btrim(coalesce(email, '')), '') is not null
    or nullif(btrim(coalesce(phone, '')), '') is not null
  )
);
-- Older iterations enforced a split count equal to guests; legacy records may
-- intentionally have only the total, so retain independent nonnegative counts.
alter table public.reservations
  drop constraint if exists reservations_guest_count_check;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.reservations'::regclass
      and conname = 'reservations_guest_count_check'
  ) then
    alter table public.reservations
      add constraint reservations_guest_count_check
      check (guests = adults + children) not valid;
  end if;
end;
$$;

-- A negative inventory movement is valid for issues/adjustments, but zero is not.
alter table public.inventory_transactions
  drop constraint if exists inventory_transactions_quantity_check;
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.inventory_transactions'::regclass
      and conname = 'inventory_transactions_quantity_nonzero_check'
  ) then
    alter table public.inventory_transactions
      add constraint inventory_transactions_quantity_nonzero_check check (quantity <> 0);
  end if;
end;
$$;

create table if not exists public.restaurant_tables (
  id text primary key,
  seats integer not null check (seats > 0),
  status text not null default 'Available',
  x numeric not null default 0,
  y numeric not null default 0,
  guest text not null default '',
  updated_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.reservations'::regclass
      and conname = 'reservations_table_id_fkey'
  ) then
    alter table public.reservations
      add constraint reservations_table_id_fkey
      foreign key (table_id) references public.restaurant_tables (id)
      on update cascade on delete set null not valid;
  end if;
end;
$$;

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users (id) on delete set null,
  table_name text not null,
  record_id text not null,
  action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  old_data jsonb,
  new_data jsonb,
  occurred_at timestamptz not null default clock_timestamp()
);

create table if not exists public.app_records_migrations (
  migration_key text primary key,
  applied_at timestamptz not null default clock_timestamp()
);
alter table public.app_records_migrations enable row level security;
revoke all on table public.app_records_migrations from public, anon, authenticated;

create table if not exists public.app_records_migration_errors (
  migration_key text primary key,
  error_text text not null,
  detected_at timestamptz not null default clock_timestamp()
);
alter table public.app_records_migration_errors enable row level security;
revoke all on table public.app_records_migration_errors from public, anon, authenticated;

create index if not exists recipe_ingredients_ingredient_idx
  on public.recipe_ingredients (ingredient_id);
create index if not exists inventory_transactions_ingredient_date_idx
  on public.inventory_transactions (ingredient_id, transaction_date desc);
create index if not exists production_logs_recipe_date_idx
  on public.production_logs (recipe_id, production_date desc);
create index if not exists waste_logs_ingredient_date_idx
  on public.waste_logs (ingredient_id, waste_date desc);
create index if not exists physical_counts_ingredient_date_idx
  on public.physical_counts (ingredient_id, count_date desc);
create index if not exists revenue_records_business_date_idx
  on public.revenue_records (business_date desc);
create unique index if not exists revenue_records_active_period_uidx
  on public.revenue_records (business_date, meal_period)
  where status = 'Active';
create index if not exists reservations_date_status_idx
  on public.reservations (reservation_date, status);
create index if not exists reservations_created_by_idx
  on public.reservations (created_by);
create unique index if not exists reservations_active_assigned_table_uidx
  on public.reservations (table_id, reservation_date, reservation_time)
  where table_id is not null and status not in ('Cancelled', 'Completed');
create index if not exists audit_logs_table_record_time_idx
  on public.audit_logs (table_name, record_id, occurred_at desc);
create index if not exists audit_logs_actor_time_idx
  on public.audit_logs (actor_id, occurred_at desc);

-- Backfill the legacy JSON store as one atomic, repeat-safe migration. Any
-- malformed row, unsupported value, FK failure, or conflicting typed id aborts
-- the whole block and leaves every app_records row untouched for resolution.
-- The marker makes subsequent schema reruns skip an already completed import.
do $$
declare
  source_row record;
  ingredient_row jsonb;
  ingredient_key text;
  ingredient_quantity numeric;
  migration_key_value constant text := 'typed_app_records_backfill_v1';
begin
  if to_regclass('public.app_records') is null then
    return;
  end if;

  if exists (
    select 1 from public.app_records_migrations
    where migration_key = migration_key_value
  ) then
    return;
  end if;

  begin
  -- Collections and mappings:
  -- ingredients -> ingredients
  -- recipes (+ ingredients[].ingredientId/ingredient_id) -> recipes and recipe_ingredients
  -- inventoryTransactions -> inventory_transactions
  -- productionLogs -> production_logs
  -- wasteLogs -> waste_logs
  -- physicalCounts -> physical_counts
  -- revenueRecords -> revenue_records
  -- reservations -> reservations
  -- restaurantTables -> restaurant_tables
  -- users are deliberately excluded (demo identities are not Auth users).

  for source_row in
    select record_id, data
    from public.app_records
    where collection = 'ingredients'
    order by record_id
  loop
    begin
      if jsonb_typeof(source_row.data) is distinct from 'object'
         or nullif(source_row.record_id, '') is null
         or (source_row.data ? 'id' and source_row.data ->> 'id' is distinct from source_row.record_id)
         or nullif(source_row.data ->> 'name', '') is null
         or source_row.data ->> 'category' is null
         or nullif(source_row.data ->> 'unit', '') is null
         or source_row.data ->> 'cost' is null
         or source_row.data ->> 'stock' is null
         or source_row.data ->> 'minimum' is null then
        raise exception 'missing or inconsistent required ingredient fields';
      end if;
      if exists (select 1 from public.ingredients where id = source_row.record_id) then
        raise exception 'typed ingredients id already exists; resolve the collision before backfill';
      end if;
      insert into public.ingredients (id, name, category, unit, cost, stock, minimum)
      values (
        source_row.record_id, source_row.data ->> 'name', source_row.data ->> 'category',
        source_row.data ->> 'unit', (source_row.data ->> 'cost')::numeric,
        (source_row.data ->> 'stock')::numeric, (source_row.data ->> 'minimum')::numeric
      );
    exception when others then
      raise exception 'Cannot backfill app_records ingredients/%: %', source_row.record_id, sqlerrm;
    end;
  end loop;

  for source_row in
    select record_id, data
    from public.app_records
    where collection = 'recipes'
    order by record_id
  loop
    begin
      if jsonb_typeof(source_row.data) is distinct from 'object'
         or nullif(source_row.record_id, '') is null
         or (source_row.data ? 'id' and source_row.data ->> 'id' is distinct from source_row.record_id)
         or nullif(source_row.data ->> 'name', '') is null
         or source_row.data ->> 'category' is null
         or source_row.data ->> 'price' is null
         or source_row.data ->> 'wastage' is null
         or jsonb_typeof(source_row.data -> 'ingredients') is distinct from 'array' then
        raise exception 'missing or inconsistent required recipe fields';
      end if;
      if exists (select 1 from public.recipes where id = source_row.record_id) then
        raise exception 'typed recipes id already exists; resolve the collision before backfill';
      end if;
      insert into public.recipes (id, name, category, price, wastage)
      values (
        source_row.record_id, source_row.data ->> 'name', source_row.data ->> 'category',
        (source_row.data ->> 'price')::numeric, (source_row.data ->> 'wastage')::numeric
      );

      for ingredient_row in
        select value from jsonb_array_elements(source_row.data -> 'ingredients')
      loop
        if jsonb_typeof(ingredient_row) is distinct from 'object'
           or nullif(coalesce(ingredient_row ->> 'ingredientId', ingredient_row ->> 'ingredient_id'), '') is null
           or ingredient_row ->> 'quantity' is null then
          raise exception 'recipe ingredient is missing ingredientId/ingredient_id or quantity';
        end if;
        ingredient_key := coalesce(ingredient_row ->> 'ingredientId', ingredient_row ->> 'ingredient_id');
        ingredient_quantity := (ingredient_row ->> 'quantity')::numeric;
        insert into public.recipe_ingredients (recipe_id, ingredient_id, quantity)
        values (source_row.record_id, ingredient_key, ingredient_quantity);
      end loop;
    exception when others then
      raise exception 'Cannot backfill app_records recipes/%: %', source_row.record_id, sqlerrm;
    end;
  end loop;

  for source_row in
    select record_id, data
    from public.app_records
    where collection = 'inventoryTransactions'
    order by record_id
  loop
    begin
      if jsonb_typeof(source_row.data) is distinct from 'object'
         or nullif(source_row.record_id, '') is null
         or (source_row.data ? 'id' and source_row.data ->> 'id' is distinct from source_row.record_id)
         or nullif(source_row.data ->> 'ingredientId', '') is null
         or source_row.data ->> 'quantity' is null
         or source_row.data ->> 'unitCost' is null
         or coalesce(source_row.data ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$'
         or nullif(source_row.data ->> 'type', '') is null then
        raise exception 'missing or inconsistent required inventory transaction fields';
      end if;
      if exists (select 1 from public.inventory_transactions where id = source_row.record_id) then
        raise exception 'typed inventory_transactions id already exists; resolve the collision before backfill';
      end if;
      insert into public.inventory_transactions (
        id, ingredient_id, quantity, unit_cost, transaction_date, transaction_type, note
      ) values (
        source_row.record_id, source_row.data ->> 'ingredientId',
        (source_row.data ->> 'quantity')::numeric, (source_row.data ->> 'unitCost')::numeric,
        (source_row.data ->> 'date')::date, source_row.data ->> 'type',
        coalesce(source_row.data ->> 'note', '')
      );
    exception when others then
      raise exception 'Cannot backfill app_records inventoryTransactions/%: %', source_row.record_id, sqlerrm;
    end;
  end loop;

  for source_row in
    select record_id, data
    from public.app_records
    where collection = 'productionLogs'
    order by record_id
  loop
    begin
      if jsonb_typeof(source_row.data) is distinct from 'object'
         or nullif(source_row.record_id, '') is null
         or (source_row.data ? 'id' and source_row.data ->> 'id' is distinct from source_row.record_id)
         or nullif(source_row.data ->> 'recipeId', '') is null
         or source_row.data ->> 'quantity' is null
         or coalesce(source_row.data ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$'
         or source_row.data ->> 'mode' is null then
        raise exception 'missing or inconsistent required production log fields';
      end if;
      if exists (select 1 from public.production_logs where id = source_row.record_id) then
        raise exception 'typed production_logs id already exists; resolve the collision before backfill';
      end if;
      insert into public.production_logs (id, recipe_id, quantity, production_date, mode)
      values (
        source_row.record_id, source_row.data ->> 'recipeId',
        (source_row.data ->> 'quantity')::numeric, (source_row.data ->> 'date')::date,
        source_row.data ->> 'mode'
      );
    exception when others then
      raise exception 'Cannot backfill app_records productionLogs/%: %', source_row.record_id, sqlerrm;
    end;
  end loop;

  for source_row in
    select record_id, data
    from public.app_records
    where collection = 'wasteLogs'
    order by record_id
  loop
    begin
      if jsonb_typeof(source_row.data) is distinct from 'object'
         or nullif(source_row.record_id, '') is null
         or (source_row.data ? 'id' and source_row.data ->> 'id' is distinct from source_row.record_id)
         or nullif(source_row.data ->> 'ingredientId', '') is null
         or source_row.data ->> 'quantity' is null
         or source_row.data ->> 'reason' is null
         or coalesce(source_row.data ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'missing or inconsistent required waste log fields';
      end if;
      if exists (select 1 from public.waste_logs where id = source_row.record_id) then
        raise exception 'typed waste_logs id already exists; resolve the collision before backfill';
      end if;
      insert into public.waste_logs (id, ingredient_id, quantity, reason, waste_date)
      values (
        source_row.record_id, source_row.data ->> 'ingredientId',
        (source_row.data ->> 'quantity')::numeric, source_row.data ->> 'reason',
        (source_row.data ->> 'date')::date
      );
    exception when others then
      raise exception 'Cannot backfill app_records wasteLogs/%: %', source_row.record_id, sqlerrm;
    end;
  end loop;

  for source_row in
    select record_id, data
    from public.app_records
    where collection = 'physicalCounts'
    order by record_id
  loop
    begin
      if jsonb_typeof(source_row.data) is distinct from 'object'
         or nullif(source_row.record_id, '') is null
         or (source_row.data ? 'id' and source_row.data ->> 'id' is distinct from source_row.record_id)
         or nullif(source_row.data ->> 'ingredientId', '') is null
         or source_row.data ->> 'expected' is null
         or source_row.data ->> 'actual' is null
         or coalesce(source_row.data ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'missing or inconsistent required physical count fields';
      end if;
      if exists (select 1 from public.physical_counts where id = source_row.record_id) then
        raise exception 'typed physical_counts id already exists; resolve the collision before backfill';
      end if;
      insert into public.physical_counts (id, ingredient_id, expected, actual, count_date)
      values (
        source_row.record_id, source_row.data ->> 'ingredientId',
        (source_row.data ->> 'expected')::numeric, (source_row.data ->> 'actual')::numeric,
        (source_row.data ->> 'date')::date
      );
    exception when others then
      raise exception 'Cannot backfill app_records physicalCounts/%: %', source_row.record_id, sqlerrm;
    end;
  end loop;

  for source_row in
    select record_id, data
    from public.app_records
    where collection = 'revenueRecords'
    order by record_id
  loop
    begin
      if jsonb_typeof(source_row.data) is distinct from 'object'
         or nullif(source_row.record_id, '') is null
         or (source_row.data ? 'id' and source_row.data ->> 'id' is distinct from source_row.record_id)
         or coalesce(source_row.data ->> 'business_date', '') !~ '^\d{4}-\d{2}-\d{2}$'
         or nullif(source_row.data ->> 'meal_period', '') is null
         or source_row.data ->> 'adult_customers' is null
         or source_row.data ->> 'adult_rate' is null
         or source_row.data ->> 'child_customers' is null
         or source_row.data ->> 'child_rate' is null
         or source_row.data ->> 'senior_pwd_customers' is null
         or source_row.data ->> 'senior_pwd_rate' is null
         or nullif(source_row.data ->> 'status', '') is null then
        raise exception 'missing or inconsistent required revenue fields';
      end if;
      if exists (select 1 from public.revenue_records where id = source_row.record_id) then
        raise exception 'typed revenue_records id already exists; resolve the collision before backfill';
      end if;
      insert into public.revenue_records (
        id, business_date, meal_period, adult_customers, adult_rate,
        child_customers, child_rate, senior_pwd_customers, senior_pwd_rate,
        status, remarks, recorded_by, recorded_at, last_edited_by,
        last_edited_at, edit_reason, voided_by, void_reason, voided_at
      ) values (
        source_row.record_id, (source_row.data ->> 'business_date')::date,
        source_row.data ->> 'meal_period', (source_row.data ->> 'adult_customers')::integer,
        (source_row.data ->> 'adult_rate')::numeric, (source_row.data ->> 'child_customers')::integer,
        (source_row.data ->> 'child_rate')::numeric, (source_row.data ->> 'senior_pwd_customers')::integer,
        (source_row.data ->> 'senior_pwd_rate')::numeric, source_row.data ->> 'status',
        coalesce(source_row.data ->> 'remarks', ''), coalesce(source_row.data ->> 'recorded_by', ''),
        coalesce((source_row.data ->> 'recorded_at')::timestamptz, now()),
        coalesce(source_row.data ->> 'last_edited_by', ''),
        (source_row.data ->> 'last_edited_at')::timestamptz,
        coalesce(source_row.data ->> 'edit_reason', ''), coalesce(source_row.data ->> 'voided_by', ''),
        coalesce(source_row.data ->> 'void_reason', ''), (source_row.data ->> 'voided_at')::timestamptz
      );
    exception when others then
      raise exception 'Cannot backfill app_records revenueRecords/%: %', source_row.record_id, sqlerrm;
    end;
  end loop;

  for source_row in
    select record_id, data
    from public.app_records
    where collection = 'restaurantTables'
    order by record_id
  loop
    begin
      if jsonb_typeof(source_row.data) is distinct from 'object'
         or nullif(source_row.record_id, '') is null
         or (source_row.data ? 'id' and source_row.data ->> 'id' is distinct from source_row.record_id)
         or source_row.data ->> 'seats' is null
         or source_row.data ->> 'status' is null
         or source_row.data ->> 'x' is null
         or source_row.data ->> 'y' is null then
        raise exception 'missing or inconsistent required restaurant table fields';
      end if;
      if exists (select 1 from public.restaurant_tables where id = source_row.record_id) then
        raise exception 'typed restaurant_tables id already exists; resolve the collision before backfill';
      end if;
      insert into public.restaurant_tables (id, seats, status, x, y, guest)
      values (
        source_row.record_id, (source_row.data ->> 'seats')::integer,
        source_row.data ->> 'status', (source_row.data ->> 'x')::numeric,
        (source_row.data ->> 'y')::numeric, coalesce(source_row.data ->> 'guest', '')
      );
    exception when others then
      raise exception 'Cannot backfill app_records restaurantTables/%: %', source_row.record_id, sqlerrm;
    end;
  end loop;

  for source_row in
    select record_id, data
    from public.app_records
    where collection = 'reservations'
    order by record_id
  loop
    begin
      if jsonb_typeof(source_row.data) is distinct from 'object'
         or nullif(source_row.record_id, '') is null
         or (source_row.data ? 'id' and source_row.data ->> 'id' is distinct from source_row.record_id)
         or nullif(source_row.data ->> 'name', '') is null
         or coalesce(source_row.data ->> 'date', '') !~ '^\d{4}-\d{2}-\d{2}$'
         or nullif(source_row.data ->> 'time', '') is null
         or source_row.data ->> 'guests' is null then
        raise exception 'missing or inconsistent required reservation fields';
      end if;
      if exists (select 1 from public.reservations where id = source_row.record_id) then
        raise exception 'typed reservations id already exists; resolve the collision before backfill';
      end if;
      insert into public.reservations (
        id, name, email, phone, reservation_date, reservation_time, guests,
        adults, children, occasion, status, preference, request, table_id,
        estimated_revenue, created_by, created_at
      ) values (
        source_row.record_id, source_row.data ->> 'name',
        nullif(source_row.data ->> 'email', ''), nullif(source_row.data ->> 'phone', ''),
        (source_row.data ->> 'date')::date, source_row.data ->> 'time',
        (source_row.data ->> 'guests')::integer,
        coalesce(nullif(source_row.data ->> 'adults', '')::integer, (source_row.data ->> 'guests')::integer),
        coalesce(nullif(source_row.data ->> 'children', '')::integer, 0),
        coalesce(source_row.data ->> 'occasion', ''), coalesce(source_row.data ->> 'status', 'Pending'),
        coalesce(source_row.data ->> 'preference', ''),
        coalesce(source_row.data ->> 'request', source_row.data ->> 'requests', ''),
        nullif(coalesce(source_row.data ->> 'table', source_row.data ->> 'table_id'), ''),
        coalesce(nullif(source_row.data ->> 'estimatedRevenue', '')::numeric, 0),
        null,
        coalesce((source_row.data ->> 'created_at')::timestamptz, now())
      );
    exception when others then
      raise exception 'Cannot backfill app_records reservations/%: %', source_row.record_id, sqlerrm;
    end;
  end loop;

  -- Mark completion only after every supported collection has imported. The
  -- source JSON remains intact and locked; users and unknown collections are
  -- deliberately not copied into typed business tables.
  insert into public.app_records_migrations (migration_key)
  values (migration_key_value);
  delete from public.app_records_migration_errors
  where migration_key = migration_key_value;
  exception when others then
    -- This exception rolls back every typed insert above, but records a
    -- precise failure while allowing the rest of the schema to finish locking
    -- app_records. The source rows remain intact for repair and safe retry.
    insert into public.app_records_migration_errors (migration_key, error_text)
    values (migration_key_value, sqlerrm)
    on conflict (migration_key) do update
      set error_text = excluded.error_text,
          detected_at = clock_timestamp();
  end;
end;
$$;

-- Timestamp values are returned by PostgREST and can be used as the
-- optimistic-concurrency token in .update/.delete(...).eq('updated_at', token).
-- Apply the exact returned token as an additional equality filter per typed row;
-- zero affected rows means the cached version is stale and should be reloaded.
-- Stock balances are ledger-maintained: insert movement/count records rather
-- than updating ingredients.stock directly.
do $$
begin
  begin
    alter table public.reservations
      validate constraint reservations_guest_count_check;
    delete from public.app_records_migration_errors
    where migration_key = 'typed_app_records_backfill_v1'
      and error_text like 'Typed reservations contain guest counts%';
  exception when check_violation then
    insert into public.app_records_migration_errors (migration_key, error_text)
    values (
      'typed_app_records_backfill_v1',
      'Typed reservations contain guest counts where guests does not equal adults + children; correct those rows to validate reservations_guest_count_check.'
    )
    on conflict (migration_key) do update
      set error_text = excluded.error_text, detected_at = clock_timestamp();
  end;
  begin
    alter table public.reservations
      validate constraint reservations_table_id_fkey;
    delete from public.app_records_migration_errors
    where migration_key = 'typed_app_records_backfill_v1'
      and error_text like 'Typed reservations reference missing restaurant_tables%';
  exception when foreign_key_violation then
    insert into public.app_records_migration_errors (migration_key, error_text)
    values (
      'typed_app_records_backfill_v1',
      'Typed reservations reference missing restaurant_tables rows; correct the table assignments to validate reservations_table_id_fkey.'
    )
    on conflict (migration_key) do update
      set error_text = excluded.error_text, detected_at = clock_timestamp();
  end;
end;
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := greatest(clock_timestamp(), old.updated_at + interval '1 microsecond');
  return new;
end;
$$;

-- The trigger is installed on every mutable typed table (not the append-only audit log).
do $$
declare
  relation_name text;
begin
  foreach relation_name in array array[
    'profiles',
    'ingredients',
    'recipes',
    'recipe_ingredients',
    'inventory_transactions',
    'production_logs',
    'waste_logs',
    'physical_counts',
    'revenue_records',
    'reservations',
    'restaurant_tables'
  ] loop
    execute format('drop trigger if exists touch_updated_at on public.%I', relation_name);
    execute format(
      'create trigger touch_updated_at before update on public.%I for each row execute function public.touch_updated_at()',
      relation_name
    );
  end loop;
end;
$$;

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select p.role
  from public.profiles as p
  where p.id = auth.uid()
$$;

create or replace function public.has_app_role(allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.profiles as p
    where p.id = auth.uid()
      and p.role = any (allowed_roles)
  )
$$;

create or replace function public.apply_inventory_transaction_stock()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  prior_stock_permission text;
  stock_updated boolean;
begin
  if tg_op <> 'INSERT' then
    raise exception 'Inventory transactions are append-only' using errcode = '55000';
  end if;

  prior_stock_permission := current_setting('costtrack.stock_movement', true);
  perform set_config('costtrack.stock_movement', 'on', true);
  update public.ingredients
  set stock = stock + new.quantity,
      cost = case when new.quantity > 0 then new.unit_cost else cost end
  where id = new.ingredient_id
    and stock + new.quantity >= 0;
  stock_updated := found;
  perform set_config('costtrack.stock_movement', coalesce(prior_stock_permission, ''), true);
  if not stock_updated then
    raise exception 'Inventory movement would make stock negative or ingredient is missing'
      using errcode = '23514';
  end if;
  return new;
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
begin
  if tg_op <> 'INSERT' then
    raise exception 'Production logs are append-only' using errcode = '55000';
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
    set stock = stock - (recipe_line.quantity * new.quantity)
    where id = recipe_line.ingredient_id
      and stock >= recipe_line.quantity * new.quantity;
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

create or replace function public.apply_waste_stock()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  prior_stock_permission text;
  stock_updated boolean;
begin
  if tg_op <> 'INSERT' then
    raise exception 'Waste logs are append-only' using errcode = '55000';
  end if;

  prior_stock_permission := current_setting('costtrack.stock_movement', true);
  perform set_config('costtrack.stock_movement', 'on', true);
  update public.ingredients
  set stock = stock - new.quantity
  where id = new.ingredient_id
    and stock >= new.quantity;
  stock_updated := found;
  perform set_config('costtrack.stock_movement', coalesce(prior_stock_permission, ''), true);
  if not stock_updated then
    raise exception 'Waste entry would make stock negative or ingredient is missing'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.apply_physical_count_stock()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  prior_stock_permission text;
  stock_updated boolean;
begin
  if tg_op <> 'INSERT' then
    raise exception 'Physical counts are append-only' using errcode = '55000';
  end if;

  prior_stock_permission := current_setting('costtrack.stock_movement', true);
  perform set_config('costtrack.stock_movement', 'on', true);
  update public.ingredients
  set stock = new.actual
  where id = new.ingredient_id;
  stock_updated := found;
  perform set_config('costtrack.stock_movement', coalesce(prior_stock_permission, ''), true);
  if not stock_updated then
    raise exception 'Physical count ingredient does not exist' using errcode = '23503';
  end if;
  return new;
end;
$$;

create or replace function public.prevent_direct_stock_change()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.stock is distinct from old.stock
     and current_setting('costtrack.stock_movement', true) is distinct from 'on' then
    raise exception 'Stock changes must be recorded through inventory transactions, production, waste, or physical counts'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_reservation_date()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if auth.uid() is not null
     and public.has_app_role(array['Administrator', 'Manager', 'Receptionist'])
     and new.reservation_date < current_date
     and (
       tg_op = 'INSERT'
       or new.reservation_date is distinct from old.reservation_date
     ) then
    raise exception 'Reservations cannot be created or moved to a past date'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.prevent_self_role_change()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if auth.uid() = old.id and new.role is distinct from old.role then
    raise exception 'Users cannot change their own role';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_self_role_change on public.profiles;
create trigger prevent_self_role_change
  before update on public.profiles
  for each row execute function public.prevent_self_role_change();

drop trigger if exists prevent_direct_stock_change on public.ingredients;
create trigger prevent_direct_stock_change
  before update of stock on public.ingredients
  for each row execute function public.prevent_direct_stock_change();

drop trigger if exists enforce_reservation_date on public.reservations;
create trigger enforce_reservation_date
  before insert or update on public.reservations
  for each row execute function public.enforce_reservation_date();

drop trigger if exists apply_inventory_transaction_stock on public.inventory_transactions;
create trigger apply_inventory_transaction_stock
  before insert or update or delete on public.inventory_transactions
  for each row execute function public.apply_inventory_transaction_stock();
drop trigger if exists apply_production_stock on public.production_logs;
create trigger apply_production_stock
  before insert or update or delete on public.production_logs
  for each row execute function public.apply_production_stock();
drop trigger if exists apply_waste_stock on public.waste_logs;
create trigger apply_waste_stock
  before insert or update or delete on public.waste_logs
  for each row execute function public.apply_waste_stock();
drop trigger if exists apply_physical_count_stock on public.physical_counts;
create trigger apply_physical_count_stock
  before insert or update or delete on public.physical_counts
  for each row execute function public.apply_physical_count_stock();

create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  prior_row jsonb;
  next_row jsonb;
  row_id text;
begin
  if tg_op = 'INSERT' then
    next_row := to_jsonb(new);
    row_id := coalesce(
      next_row ->> 'id',
      (next_row ->> 'recipe_id') || ':' || (next_row ->> 'ingredient_id')
    );
  elsif tg_op = 'UPDATE' then
    prior_row := to_jsonb(old);
    next_row := to_jsonb(new);
    row_id := coalesce(
      next_row ->> 'id',
      (next_row ->> 'recipe_id') || ':' || (next_row ->> 'ingredient_id')
    );
  else
    prior_row := to_jsonb(old);
    row_id := coalesce(
      prior_row ->> 'id',
      (prior_row ->> 'recipe_id') || ':' || (prior_row ->> 'ingredient_id')
    );
  end if;

  insert into public.audit_logs (
    actor_id, table_name, record_id, action, old_data, new_data, occurred_at
  ) values (
    auth.uid(), tg_table_name, row_id, tg_op, prior_row, next_row, clock_timestamp()
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

do $$
declare
  relation_name text;
begin
  foreach relation_name in array array[
    'profiles',
    'ingredients',
    'recipes',
    'recipe_ingredients',
    'inventory_transactions',
    'production_logs',
    'waste_logs',
    'physical_counts',
    'revenue_records',
    'reservations',
    'restaurant_tables'
  ] loop
    execute format('drop trigger if exists write_audit_log on public.%I', relation_name);
    execute format(
      'create trigger write_audit_log after insert or update or delete on public.%I for each row execute function public.write_audit_log()',
      relation_name
    );
  end loop;
end;
$$;

alter table public.profiles enable row level security;
alter table public.ingredients enable row level security;
alter table public.recipes enable row level security;
alter table public.recipe_ingredients enable row level security;
alter table public.inventory_transactions enable row level security;
alter table public.production_logs enable row level security;
alter table public.waste_logs enable row level security;
alter table public.physical_counts enable row level security;
alter table public.revenue_records enable row level security;
alter table public.reservations enable row level security;
alter table public.restaurant_tables enable row level security;
alter table public.audit_logs enable row level security;

-- Remove old policies on these tables before defining the restrictive policy set.
do $$
declare
  policy_row record;
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = any (array[
        'profiles',
        'ingredients',
        'recipes',
        'recipe_ingredients',
        'inventory_transactions',
        'production_logs',
        'waste_logs',
        'physical_counts',
        'revenue_records',
        'reservations',
        'restaurant_tables',
        'audit_logs'
      ])
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_row.policyname,
      policy_row.schemaname,
      policy_row.tablename
    );
  end loop;
end;
$$;

create policy profiles_self_read
  on public.profiles for select to authenticated
  using (id = auth.uid());
create policy profiles_admin_read
  on public.profiles for select to authenticated
  using (public.has_app_role(array['Administrator']));
create policy profiles_admin_insert
  on public.profiles for insert to authenticated
  with check (public.has_app_role(array['Administrator']));
create policy profiles_admin_update
  on public.profiles for update to authenticated
  using (public.has_app_role(array['Administrator']))
  with check (public.has_app_role(array['Administrator']));
create policy profiles_admin_delete
  on public.profiles for delete to authenticated
  using (public.has_app_role(array['Administrator']));

create policy ingredients_read
  on public.ingredients for select to authenticated
  using (public.has_app_role(array[
    'Administrator', 'Manager', 'Chef / Kitchen Staff', 'Receptionist', 'Inventory Clerk'
  ]));
create policy ingredients_insert
  on public.ingredients for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));
create policy ingredients_update
  on public.ingredients for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']))
  with check (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));
create policy ingredients_delete
  on public.ingredients for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));

create policy recipes_read
  on public.recipes for select to authenticated
  using (public.has_app_role(array[
    'Administrator', 'Manager', 'Chef / Kitchen Staff', 'Receptionist', 'Inventory Clerk'
  ]));
create policy recipes_delete
  on public.recipes for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']));

create policy recipe_ingredients_read
  on public.recipe_ingredients for select to authenticated
  using (public.has_app_role(array[
    'Administrator', 'Manager', 'Chef / Kitchen Staff', 'Receptionist', 'Inventory Clerk'
  ]));

create policy inventory_transactions_read
  on public.inventory_transactions for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));
create policy inventory_transactions_insert
  on public.inventory_transactions for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));

create policy production_logs_read
  on public.production_logs for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff', 'Receptionist']));
create policy production_logs_insert
  on public.production_logs for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']));

create policy waste_logs_read
  on public.waste_logs for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff', 'Inventory Clerk', 'Receptionist']));
create policy waste_logs_insert
  on public.waste_logs for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff', 'Inventory Clerk']));

create policy physical_counts_read
  on public.physical_counts for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk', 'Receptionist']));
create policy physical_counts_insert
  on public.physical_counts for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));

create policy revenue_records_read
  on public.revenue_records for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));
create policy revenue_records_insert
  on public.revenue_records for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy revenue_records_update
  on public.revenue_records for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']))
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy revenue_records_delete
  on public.revenue_records for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));

create policy reservations_read
  on public.reservations for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy reservations_insert
  on public.reservations for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy reservations_update
  on public.reservations for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']))
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy reservations_delete
  on public.reservations for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));

create policy restaurant_tables_read
  on public.restaurant_tables for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy restaurant_tables_insert
  on public.restaurant_tables for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy restaurant_tables_update
  on public.restaurant_tables for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']))
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy restaurant_tables_delete
  on public.restaurant_tables for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));

create policy audit_logs_admin_read
  on public.audit_logs for select to authenticated
  using (public.has_app_role(array['Administrator']));

-- Atomically save a recipe and replace its ingredients.
-- Payload shape: {id,name,category,price,wastage,ingredients:[{ingredient_id,quantity}]}.
-- The adapter must pass null expected_updated_at for inserts and the selected
-- row's exact updated_at for edits; direct recipe saves are intentionally denied.
drop function if exists public.save_recipe(jsonb);
create or replace function public.save_recipe(
  payload jsonb,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  recipe_id_value text;
  ingredient_item jsonb;
  saved_recipe public.recipes%rowtype;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']) then
    raise exception 'Not authorized to save recipes' using errcode = '42501';
  end if;
  if payload is null or jsonb_typeof(payload) is distinct from 'object' then
    raise exception 'Recipe payload must be a JSON object';
  end if;
  if jsonb_typeof(payload -> 'ingredients') is distinct from 'array' then
    raise exception 'Recipe ingredients must be a JSON array';
  end if;

  recipe_id_value := nullif(btrim(payload ->> 'id'), '');
  if recipe_id_value is null
     or nullif(btrim(payload ->> 'name'), '') is null
     or nullif(btrim(payload ->> 'category'), '') is null
     or payload ->> 'price' is null
     or payload ->> 'wastage' is null then
    raise exception 'Recipe id, name, category, price, and wastage are required';
  end if;

  for ingredient_item in
    select value from jsonb_array_elements(payload -> 'ingredients')
  loop
    if jsonb_typeof(ingredient_item) is distinct from 'object'
       or nullif(btrim(ingredient_item ->> 'ingredient_id'), '') is null
       or ingredient_item ->> 'quantity' is null
       or (ingredient_item ->> 'quantity')::numeric <= 0 then
      raise exception 'Each recipe ingredient needs an id and positive quantity';
    end if;
    if not exists (
      select 1
      from public.ingredients as i
      where i.id = ingredient_item ->> 'ingredient_id'
    ) then
      raise exception 'Unknown ingredient id: %', ingredient_item ->> 'ingredient_id';
    end if;
  end loop;

  if exists (
    select 1
    from jsonb_to_recordset(payload -> 'ingredients')
      as ingredient_rows(ingredient_id text, quantity numeric)
    group by ingredient_rows.ingredient_id
    having count(*) > 1
  ) then
    raise exception 'Recipe ingredient ids must be unique';
  end if;

  select * into saved_recipe
  from public.recipes
  where id = recipe_id_value
  for update;

  if found then
    if expected_updated_at is null
       or saved_recipe.updated_at is distinct from expected_updated_at then
      raise exception 'Recipe was changed by another user; reload before saving'
        using errcode = '40001';
    end if;
    update public.recipes
    set name = btrim(payload ->> 'name'),
        category = btrim(payload ->> 'category'),
        price = (payload ->> 'price')::numeric,
        wastage = (payload ->> 'wastage')::numeric
    where id = recipe_id_value
    returning * into saved_recipe;
  else
    if expected_updated_at is not null then
      raise exception 'Recipe no longer exists; reload before saving'
        using errcode = '40001';
    end if;
    begin
      insert into public.recipes (id, name, category, price, wastage)
      values (
        recipe_id_value,
        btrim(payload ->> 'name'),
        btrim(payload ->> 'category'),
        (payload ->> 'price')::numeric,
        (payload ->> 'wastage')::numeric
      )
      returning * into saved_recipe;
    exception when unique_violation then
      raise exception 'Recipe was concurrently inserted; reload before saving'
        using errcode = '40001';
    end;
  end if;

  delete from public.recipe_ingredients
  where recipe_id = recipe_id_value;

  insert into public.recipe_ingredients (recipe_id, ingredient_id, quantity)
  select recipe_id_value, rows.ingredient_id, rows.quantity
  from jsonb_to_recordset(payload -> 'ingredients')
    as rows(ingredient_id text, quantity numeric);

  return to_jsonb(saved_recipe);
end;
$$;

-- Public callers can create reservations through this validator, but cannot
-- query or mutate the reservations table directly.
create or replace function public.public_create_reservation(payload jsonb)
returns text
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  new_reference text;
  reservation_name text;
  reservation_email text;
  reservation_phone text;
  reservation_day date;
  reservation_time_value text;
  guest_count integer;
  adult_count integer;
  child_count integer;
  occasion_value text;
  preference_value text;
  request_value text;
begin
  if payload is null or jsonb_typeof(payload) is distinct from 'object' then
    raise exception 'Reservation payload must be a JSON object';
  end if;

  reservation_name := nullif(btrim(payload ->> 'name'), '');
  reservation_email := nullif(btrim(payload ->> 'email'), '');
  reservation_phone := nullif(btrim(payload ->> 'phone'), '');
  if reservation_name is null or length(reservation_name) > 160 then
    raise exception 'A valid reservation name is required';
  end if;
  if reservation_email is not null
     and (length(reservation_email) > 254
       or reservation_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$') then
    raise exception 'A valid email address is required';
  end if;
  if reservation_phone is not null then
    if length(reservation_phone) > 40
       or length(regexp_replace(reservation_phone, '[^0-9]', '', 'g')) not between 7 and 15 then
      raise exception 'A valid phone number is required';
    end if;
  end if;
  if reservation_email is null and reservation_phone is null then
    raise exception 'An email address or phone number is required';
  end if;

  reservation_day := (payload ->> 'reservation_date')::date;
  if reservation_day is null then
    raise exception 'A reservation date is required';
  end if;
  if reservation_day < current_date then
    raise exception 'Reservation date cannot be in the past';
  end if;
  reservation_time_value := nullif(btrim(payload ->> 'reservation_time'), '');
  if reservation_time_value is null or length(reservation_time_value) > 40 then
    raise exception 'A reservation time is required';
  end if;

  guest_count := (payload ->> 'guests')::integer;
  adult_count := coalesce(nullif(payload ->> 'adults', '')::integer, guest_count);
  child_count := coalesce(nullif(payload ->> 'children', '')::integer, 0);
  if guest_count < 1 or guest_count > 1000
     or adult_count < 0 or child_count < 0
     or adult_count + child_count <> guest_count then
    raise exception 'Guest counts are invalid';
  end if;

  occasion_value := coalesce(nullif(btrim(payload ->> 'occasion'), ''), '');
  preference_value := coalesce(nullif(btrim(payload ->> 'preference'), ''), '');
  request_value := coalesce(nullif(btrim(payload ->> 'request'), ''), '');
  if length(occasion_value) > 120 or length(preference_value) > 500
     or length(request_value) > 2000 then
    raise exception 'Reservation details exceed the allowed length';
  end if;

  new_reference := 'RSV-' || upper(replace(gen_random_uuid()::text, '-', ''));
  begin
    insert into public.reservations (
      id, name, email, phone, reservation_date, reservation_time,
      guests, adults, children, occasion, status, preference, request, created_by
    ) values (
      new_reference, reservation_name, reservation_email, reservation_phone,
      reservation_day, reservation_time_value, guest_count, adult_count, child_count,
      occasion_value, 'Pending', preference_value, request_value, auth.uid()
    );
  exception when unique_violation then
    raise exception 'Reservation reference or table/time slot is already in use'
      using errcode = '23P01';
  end;

  return new_reference;
end;
$$;

-- No row is returned unless the supplied email OR phone matches the record.
-- The result intentionally omits guest contact details, notes, and table assignment.
create or replace function public.public_get_reservation_status(reference text, contact text)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'reference', r.id,
    'status', r.status,
    'reservation_date', r.reservation_date,
    'reservation_time', r.reservation_time,
    'guests', r.guests
  )
  from public.reservations as r
  where nullif(btrim($1), '') is not null
    and nullif(btrim($2), '') is not null
    and r.id = btrim($1)
    and (
      (r.email is not null and lower(btrim(r.email)) = lower(btrim($2)))
      or (
        r.phone is not null
        and length(regexp_replace($2, '[^0-9]', '', 'g')) > 0
        and regexp_replace(r.phone, '[^0-9]', '', 'g')
            = regexp_replace($2, '[^0-9]', '', 'g')
      )
    )
$$;

-- Keep app_records as a locked archive after backfill. Demo users and unknown
-- collections remain there for explicit review; they are not exposed through
-- the API or copied into Auth profiles.
do $$
declare
  policy_row record;
begin
  if to_regclass('public.app_records') is not null then
    alter table public.app_records enable row level security;
    for policy_row in
      select policyname
      from pg_policies
      where schemaname = 'public' and tablename = 'app_records'
    loop
      execute format('drop policy if exists %I on public.app_records', policy_row.policyname);
    end loop;
    revoke all on table public.app_records from public, anon, authenticated;
  end if;
end;
$$;

-- Do not inherit broad Supabase defaults on these application tables.
grant usage on schema public to anon, authenticated;

revoke all on table
  public.profiles,
  public.ingredients,
  public.recipes,
  public.recipe_ingredients,
  public.inventory_transactions,
  public.production_logs,
  public.waste_logs,
  public.physical_counts,
  public.revenue_records,
  public.reservations,
  public.restaurant_tables,
  public.audit_logs,
  public.app_records_migrations,
  public.app_records_migration_errors
from public, anon, authenticated;

grant select, insert, update, delete on table
  public.profiles,
  public.ingredients,
  public.recipes,
  public.recipe_ingredients,
  public.inventory_transactions,
  public.production_logs,
  public.waste_logs,
  public.physical_counts,
  public.revenue_records,
  public.reservations,
  public.restaurant_tables
to authenticated;
revoke update, delete on table
  public.inventory_transactions,
  public.production_logs,
  public.waste_logs,
  public.physical_counts
from public, anon, authenticated;
revoke insert, update on table public.recipes from public, anon, authenticated;
revoke insert, update, delete on table public.recipe_ingredients from public, anon, authenticated;
grant select on table public.audit_logs to authenticated;

revoke all on function public.current_app_role() from public, anon;
revoke all on function public.has_app_role(text[]) from public, anon;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.has_app_role(text[]) to authenticated;
revoke all on function public.touch_updated_at() from public, anon, authenticated;
revoke all on function public.apply_inventory_transaction_stock() from public, anon, authenticated;
revoke all on function public.apply_production_stock() from public, anon, authenticated;
revoke all on function public.apply_waste_stock() from public, anon, authenticated;
revoke all on function public.apply_physical_count_stock() from public, anon, authenticated;
revoke all on function public.prevent_direct_stock_change() from public, anon, authenticated;
revoke all on function public.enforce_reservation_date() from public, anon, authenticated;
revoke all on function public.prevent_self_role_change() from public, anon, authenticated;
revoke all on function public.write_audit_log() from public, anon, authenticated;

revoke all on function public.save_recipe(jsonb, timestamptz) from public, anon;
grant execute on function public.save_recipe(jsonb, timestamptz) to authenticated;
revoke all on function public.public_create_reservation(jsonb) from public;
grant execute on function public.public_create_reservation(jsonb) to anon, authenticated;
revoke all on function public.public_get_reservation_status(text, text) from public;
grant execute on function public.public_get_reservation_status(text, text) to anon, authenticated;

comment on table public.profiles is
  'Auth-linked app profiles. Provision Auth users in Supabase Auth first, then insert their matching id/email/full_name/role here as an administrator or through the SQL editor; do not copy demo users.';
do $$
begin
  if to_regclass('public.app_records') is not null then
    comment on table public.app_records is
          'Locked legacy archive. Supported collections are backfilled atomically; inspect app_records_migration_errors if the retryable backfill stopped. Demo users and unknown collections are excluded.';
  end if;
end;
$$;
comment on function public.save_recipe(jsonb, timestamptz) is
  'Authorized atomic recipe save; inserts only without an expected version and updates only when expected_updated_at matches; replaces recipe_ingredients and returns updated_at.';
comment on function public.public_create_reservation(jsonb) is
  'Validated public reservation entry point; direct public table access is not granted.';
comment on function public.public_get_reservation_status(text, text) is
  'Returns minimal status fields only when reservation reference and email or phone match.';
comment on table public.app_records_migrations is
  'Private completion marker for the atomic typed app_records backfill.';
comment on table public.app_records_migration_errors is
  'Private SQL-owner report for a rolled-back app_records backfill; repair the named row and rerun the schema.';
comment on table public.inventory_transactions is
  'Append-only stock movement ledger; inserts atomically apply quantity delta and positive-movement unit cost to ingredients.';
comment on table public.production_logs is
  'Append-only production ledger; inserts atomically consume recipe ingredient quantities from stock.';
comment on table public.waste_logs is
  'Append-only waste ledger; inserts atomically consume ingredient stock.';
comment on table public.physical_counts is
  'Append-only physical count ledger; inserts atomically set ingredient stock to actual.';
comment on column public.ingredients.stock is
  'Nonnegative on-hand balance maintained by stock ledger insert triggers; direct stock updates are rejected.';
