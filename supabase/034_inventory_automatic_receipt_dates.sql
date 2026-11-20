-- Automatic inventory identifiers and product shelf-life duration.
-- Safe to rerun.

alter table public.ingredients
  add column if not exists shelf_life_days integer;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ingredients_shelf_life_days_check'
      and conrelid = 'public.ingredients'::regclass
  ) then
    alter table public.ingredients
      add constraint ingredients_shelf_life_days_check
      check (shelf_life_days is null or (shelf_life_days between 1 and 3650));
  end if;
end;
$$;

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
  shelf_life_days_value integer;
  line_count integer := 0;
  invoice_total numeric := 0;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']) then
    raise exception 'Not authorized to receive inventory';
  end if;

  supplier_value := nullif(btrim(payload ->> 'supplier_name'), '');
  invoice_value := nullif(btrim(payload ->> 'invoice_number'), '');
  invoice_date_value := nullif(payload ->> 'invoice_date', '')::date;
  received_date_value := nullif(payload ->> 'received_date', '')::date;
  note_value := coalesce(nullif(btrim(payload ->> 'note'), ''), '');

  if supplier_value is null or invoice_date_value is null or received_date_value is null then
    raise exception 'Supplier, invoice number, invoice date, and received date are required';
  end if;
  if invoice_value is null then
    invoice_value := 'INV-' || to_char(received_date_value, 'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  end if;
  if invoice_date_value > current_date or received_date_value > current_date
     or received_date_value > invoice_date_value then
    raise exception 'Invoice and received dates cannot be in the future or before the invoice date';
  end if;
  if jsonb_typeof(payload -> 'lines') is distinct from 'array'
     or jsonb_array_length(payload -> 'lines') < 1
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

    if line_id is null or ingredient_id_value is null
       or quantity_value is null or quantity_value <= 0
       or unit_cost_value is null or unit_cost_value < 0 then
      raise exception 'Each product line requires an id, product, positive quantity, and non-negative unit cost';
    end if;
    if not exists (
      select 1 from public.ingredients as i
      where i.id = ingredient_id_value and i.is_active
    ) then
      raise exception 'A selected product is missing or inactive';
    end if;

    select i.shelf_life_days
    into shelf_life_days_value
    from public.ingredients as i
    where i.id = ingredient_id_value;

    if shelf_life_days_value is not null then
      expiration_date_value := received_date_value + shelf_life_days_value;
    end if;

    if expiration_date_value is not null
       and expiration_date_value < received_date_value then
      raise exception 'A product expiration date cannot be before its received date';
    end if;

    if batch_code_value is null then
      batch_code_value := 'LOT-' || to_char(received_date_value, 'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    end if;

    select * into existing_transaction
    from public.inventory_transactions as t
    where t.id = line_id;
    if found then
      if existing_transaction.ingredient_id is distinct from ingredient_id_value
         or existing_transaction.quantity is distinct from quantity_value
         or existing_transaction.unit_cost is distinct from unit_cost_value
         or existing_transaction.transaction_date is distinct from received_date_value
         or existing_transaction.batch_code is distinct from batch_code_value
         or existing_transaction.expiration_date is distinct from expiration_date_value then
        raise exception 'A delivery line id was already used for different receipt data';
      end if;
    else
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
    end if;
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

grant execute on function public.costtrack_receive_delivery(jsonb) to authenticated;
