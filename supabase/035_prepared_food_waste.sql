begin;

create table if not exists public.prepared_food_waste_logs (
  id text primary key,
  dish_name text not null check (char_length(btrim(dish_name)) between 1 and 200),
  production_batch_id text references public.production_batches (id) on delete set null,
  production_batch_label text not null default '',
  quantity numeric not null check (quantity > 0 and quantity <= 1000000),
  reason text not null check (reason in (
    'Leftover after service', 'Unsold prepared food', 'Over-production',
    'Expired prepared food', 'Burned', 'Contaminated', 'Other'
  )),
  waste_date date not null,
  recorded_at timestamptz not null default clock_timestamp(),
  recorded_by uuid references auth.users (id) on delete set null,
  notes text not null default '',
  updated_at timestamptz not null default now()
);

create index if not exists prepared_food_waste_logs_date_idx
  on public.prepared_food_waste_logs (waste_date desc, recorded_at desc);
create index if not exists prepared_food_waste_logs_dish_idx
  on public.prepared_food_waste_logs (lower(btrim(dish_name)));
create index if not exists prepared_food_waste_logs_batch_idx
  on public.prepared_food_waste_logs (production_batch_id)
  where production_batch_id is not null;

alter table public.prepared_food_waste_logs enable row level security;
revoke all on table public.prepared_food_waste_logs from public, anon, authenticated;
grant select on table public.prepared_food_waste_logs to authenticated;

drop policy if exists prepared_food_waste_logs_read on public.prepared_food_waste_logs;
create policy prepared_food_waste_logs_read
  on public.prepared_food_waste_logs for select to authenticated
  using (public.has_app_role(array[
    'Administrator', 'Manager', 'Chef / Kitchen Staff', 'Inventory Clerk'
  ]));

create or replace function public.prevent_prepared_food_waste_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'Prepared-food waste logs are append-only'
    using errcode = '55000';
end;
$$;

drop trigger if exists prevent_prepared_food_waste_mutation on public.prepared_food_waste_logs;
create trigger prevent_prepared_food_waste_mutation
  before update or delete on public.prepared_food_waste_logs
  for each row execute function public.prevent_prepared_food_waste_mutation();

drop trigger if exists write_audit_log on public.prepared_food_waste_logs;
create trigger write_audit_log
  after insert on public.prepared_food_waste_logs
  for each row execute function public.write_audit_log();

create or replace function public.costtrack_log_prepared_food_waste(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  waste_id text;
  dish_name_value text;
  production_batch_id_value text;
  production_batch_label_value text := '';
  quantity_value numeric;
  reason_value text;
  waste_date_value date;
  notes_value text;
  existing_waste public.prepared_food_waste_logs%rowtype;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']) then
    raise exception 'Not authorized to record prepared-food waste'
      using errcode = '42501';
  end if;
  if jsonb_typeof(payload) is distinct from 'object' then
    raise exception 'A prepared-food waste entry payload is required';
  end if;

  waste_id := nullif(btrim(payload ->> 'id'), '');
  dish_name_value := nullif(btrim(payload ->> 'dish_name'), '');
  production_batch_id_value := nullif(btrim(payload ->> 'production_batch_id'), '');
  reason_value := left(btrim(coalesce(payload ->> 'reason', '')), 250);
  notes_value := left(btrim(coalesce(payload ->> 'notes', '')), 500);
  if waste_id is null or char_length(waste_id) > 120
     or dish_name_value is null or char_length(dish_name_value) > 200
     or coalesce(payload ->> 'quantity', '') !~ '^[0-9]+([.][0-9]{1,4})?$'
     or coalesce(payload ->> 'waste_date', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception 'Enter a dish, positive portions, and a valid waste date';
  end if;

  quantity_value := (payload ->> 'quantity')::numeric;
  waste_date_value := (payload ->> 'waste_date')::date;
  if quantity_value <= 0 or quantity_value > 1000000 then
    raise exception 'Wasted portions must be greater than zero and no more than 1,000,000';
  end if;
  if waste_date_value > (pg_catalog.clock_timestamp() at time zone 'Asia/Manila')::date then
    raise exception 'Waste date cannot be in the future';
  end if;
  if reason_value not in (
    'Leftover after service', 'Unsold prepared food', 'Over-production',
    'Expired prepared food', 'Burned', 'Contaminated', 'Other'
  ) then
    raise exception 'Choose a valid prepared-food waste reason'
      using errcode = '22023';
  end if;
  if reason_value = 'Other' and notes_value = '' then
    raise exception 'Add a short explanation for the Other reason'
      using errcode = '22023';
  end if;

  if production_batch_id_value is not null then
    select format('%s · #%s · %s', recipe.name, batch.batch_number, batch.service_date)
      into production_batch_label_value
    from public.production_batches as batch
    join public.recipes as recipe on recipe.id = batch.recipe_id
    where batch.id = production_batch_id_value
      and batch.status = 'Ready';
    if not found then
      raise exception 'Choose a ready production batch'
        using errcode = '22023';
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(waste_id, 0));
  select * into existing_waste
  from public.prepared_food_waste_logs as waste
  where waste.id = waste_id
  for update;
  if found then
    if existing_waste.dish_name <> dish_name_value
       or existing_waste.production_batch_id is distinct from production_batch_id_value
       or existing_waste.quantity <> quantity_value
       or existing_waste.reason <> reason_value
       or existing_waste.waste_date <> waste_date_value
       or existing_waste.notes <> notes_value then
      raise exception 'This prepared-food waste request ID was already used for a different entry';
    end if;
    return to_jsonb(existing_waste);
  end if;

  insert into public.prepared_food_waste_logs (
    id, dish_name, production_batch_id, production_batch_label, quantity,
    reason, waste_date, recorded_at, recorded_by, notes
  ) values (
    waste_id, dish_name_value, production_batch_id_value,
    production_batch_label_value, quantity_value, reason_value,
    waste_date_value, pg_catalog.clock_timestamp(), auth.uid(), notes_value
  )
  returning * into existing_waste;

  return to_jsonb(existing_waste);
end;
$$;

revoke all on function public.prevent_prepared_food_waste_mutation()
  from public, anon, authenticated;
revoke all on function public.costtrack_log_prepared_food_waste(jsonb)
  from public, anon, authenticated;
grant execute on function public.costtrack_log_prepared_food_waste(jsonb)
  to authenticated;

do $$
begin
  if exists (select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_catalog.pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'prepared_food_waste_logs'
     ) then
    execute 'alter publication supabase_realtime add table public.prepared_food_waste_logs';
  end if;
end;
$$;

commit;
