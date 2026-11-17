begin;

alter table public.waste_logs
  add column if not exists recorded_at timestamptz,
  add column if not exists recorded_by uuid references auth.users (id) on delete set null,
  add column if not exists notes text not null default '';

alter table public.waste_logs
  alter column recorded_at set default now();

create index if not exists waste_logs_recorded_at_idx
  on public.waste_logs (recorded_at desc)
  where recorded_at is not null;
create index if not exists waste_logs_recorded_by_idx
  on public.waste_logs (recorded_by);

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

  new.recorded_at := coalesce(new.recorded_at, now());
  new.recorded_by := auth.uid();

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

create or replace function public.costtrack_log_waste(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  waste_id text;
  ingredient_id_value text;
  quantity_value numeric;
  reason_value text;
  waste_date_value date;
  recorded_at_value timestamptz;
  production_log_id_value text;
  notes_value text;
  existing_waste public.waste_logs%rowtype;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']) then
    raise exception 'Not authorized to record kitchen waste'
      using errcode = '42501';
  end if;
  if jsonb_typeof(payload) is distinct from 'object' then
    raise exception 'A waste entry payload is required';
  end if;

  waste_id := nullif(btrim(payload ->> 'id'), '');
  ingredient_id_value := nullif(btrim(payload ->> 'ingredient_id'), '');
  if waste_id is null or ingredient_id_value is null
     or coalesce(payload ->> 'quantity', '') !~ '^[0-9]+([.][0-9]{1,4})?$'
     or nullif(btrim(payload ->> 'reason'), '') is null
     or nullif(btrim(payload ->> 'waste_date'), '') is null then
    raise exception 'Enter an ingredient, positive quantity, reason, and date';
  end if;

  quantity_value := (payload ->> 'quantity')::numeric;
  if quantity_value <= 0 or quantity_value > 1000000 then
    raise exception 'Waste quantity must be greater than zero and no more than 1,000,000';
  end if;
  reason_value := left(btrim(payload ->> 'reason'), 250);
  waste_date_value := (payload ->> 'waste_date')::date;
  recorded_at_value := coalesce(nullif(payload ->> 'recorded_at', '')::timestamptz, now());
  production_log_id_value := nullif(btrim(payload ->> 'production_log_id'), '');
  notes_value := left(coalesce(payload ->> 'notes', ''), 500);

  perform pg_advisory_xact_lock(hashtextextended(waste_id, 0));
  select * into existing_waste
  from public.waste_logs as waste
  where waste.id = waste_id
  for update;
  if found then
    if existing_waste.ingredient_id <> ingredient_id_value
       or existing_waste.quantity <> quantity_value
       or existing_waste.reason <> reason_value
       or existing_waste.waste_date <> waste_date_value
       or existing_waste.recorded_at <> recorded_at_value
       or existing_waste.production_log_id is distinct from production_log_id_value
       or existing_waste.notes <> notes_value then
      raise exception 'This waste request ID was already used for a different entry';
    end if;
    return to_jsonb(existing_waste);
  end if;

  insert into public.waste_logs (
    id, ingredient_id, quantity, reason, waste_date, production_log_id,
    recorded_at, notes
  ) values (
    waste_id, ingredient_id_value, quantity_value, reason_value, waste_date_value,
    production_log_id_value, recorded_at_value, notes_value
  )
  returning * into existing_waste;

  return to_jsonb(existing_waste);
end;
$$;

revoke all on function public.apply_waste_stock() from public, anon, authenticated;
revoke all on function public.costtrack_log_waste(jsonb) from public, anon, authenticated;
grant execute on function public.costtrack_log_waste(jsonb) to authenticated;

commit;
