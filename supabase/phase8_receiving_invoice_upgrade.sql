-- Upgrade for projects that already applied an earlier Phase 8 migration.
-- Adds invoice metadata and atomically creates receipt batches and movements.
-- Safe to rerun; this does not replay or alter existing inventory transactions.

begin;

do $$
begin
  if to_regclass('public.ingredients') is null
     or to_regclass('public.inventory_transactions') is null
     or to_regclass('public.inventory_batches') is null
     or to_regclass('public.stock_movements') is null then
    raise exception
      'Apply supabase-schema.sql and the earlier Phase 8 migration before this receiving upgrade';
  end if;
  if to_regprocedure('public.has_app_role(text[])') is null then
    raise exception 'Required role-check function public.has_app_role(text[]) is missing';
  end if;
end;
$$;

alter table public.inventory_transactions
  add column if not exists supplier_name text not null default '',
  add column if not exists invoice_number text not null default '',
  add column if not exists invoice_date date,
  add column if not exists batch_code text,
  add column if not exists expiration_date date;

alter table public.inventory_batches
  add column if not exists source_transaction_id text
    references public.inventory_transactions (id) on delete restrict;

-- A supplier's lot code may recur across products and deliveries. The source
-- transaction id, rather than a lot-code uniqueness rule, identifies each batch.
alter table public.inventory_batches
  drop constraint if exists inventory_batches_batch_code_key;
drop index if exists public.inventory_batches_product_batch_code_uidx;

create unique index if not exists inventory_batches_source_transaction_uidx
  on public.inventory_batches (source_transaction_id)
  where source_transaction_id is not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.inventory_transactions'::regclass
      and conname = 'inventory_transactions_expiration_check'
  ) then
    alter table public.inventory_transactions
      add constraint inventory_transactions_expiration_check
      check (expiration_date is null or expiration_date >= transaction_date);
  end if;
end;
$$;

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
    batch_code,
    product_id,
    source_transaction_id,
    quantity_received,
    quantity_remaining,
    unit_cost,
    received_date,
    expiration_date,
    status,
    is_opening_balance,
    created_by,
    updated_by
  )
  values (
    batch_code_value,
    new.ingredient_id,
    new.id,
    new.quantity,
    new.quantity,
    new.unit_cost,
    new.transaction_date,
    new.expiration_date,
    case when new.expiration_date < current_date then 'Expired' else 'Active' end,
    false,
    auth.uid(),
    auth.uid()
  )
  returning id into batch_id_value;

  insert into public.stock_movements (
    product_id,
    batch_id,
    movement_type,
    quantity,
    unit_cost,
    reference_type,
    reference_id,
    user_id,
    note
  )
  values (
    new.ingredient_id,
    batch_id_value,
    'Received',
    new.quantity,
    new.unit_cost,
    'inventory_transaction',
    new.id,
    auth.uid(),
    concat_ws(
      ' · ',
      nullif(new.supplier_name, ''),
      nullif(new.invoice_number, ''),
      nullif(new.note, '')
    )
  );

  return new;
end;
$$;

drop trigger if exists costtrack_record_received_batch
  on public.inventory_transactions;
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
  if not public.has_app_role(array[
    'Administrator', 'Manager', 'Inventory Clerk'
  ]) then
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
    raise exception
      'Supplier, invoice number, invoice date, and received date are required';
  end if;
  if length(supplier_value) > 200 or length(invoice_value) > 100
     or length(note_value) > 500 then
    raise exception 'Supplier, invoice number, or note is too long';
  end if;
  if jsonb_typeof(payload -> 'lines') is distinct from 'array' then
    raise exception 'Delivery product lines must be a JSON array';
  end if;
  if jsonb_array_length(payload -> 'lines') < 1
     or jsonb_array_length(payload -> 'lines') > 50 then
    raise exception 'A delivery must contain between 1 and 50 product lines';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(payload -> 'lines') as item(value)
    group by item.value ->> 'id'
    having count(*) > 1
  ) then
    raise exception 'Each product line must have a unique id';
  end if;

  for line in select value from jsonb_array_elements(payload -> 'lines')
  loop
    if jsonb_typeof(line) is distinct from 'object' then
      raise exception 'Each delivery line must be a JSON object';
    end if;

    line_id := nullif(btrim(line ->> 'id'), '');
    ingredient_id_value := nullif(btrim(line ->> 'ingredient_id'), '');
    quantity_value := nullif(line ->> 'quantity', '')::numeric;
    unit_cost_value := nullif(line ->> 'unit_cost', '')::numeric;
    batch_code_value := nullif(btrim(line ->> 'batch_code'), '');
    expiration_date_value := nullif(line ->> 'expiration_date', '')::date;

    if line_id is null or ingredient_id_value is null
       or quantity_value is null or quantity_value <= 0
       or unit_cost_value is null or unit_cost_value < 0 then
      raise exception
        'Each product line requires an id, product, positive quantity, and non-negative unit cost';
    end if;
    if quantity_value::text in ('NaN', 'Infinity', '-Infinity')
       or quantity_value <> round(quantity_value, 4) then
      raise exception 'Product quantities may have no more than 4 decimal places';
    end if;
    if unit_cost_value::text in ('NaN', 'Infinity', '-Infinity')
       or unit_cost_value <> round(unit_cost_value, 6) then
      raise exception 'Unit costs may have no more than 6 decimal places';
    end if;
    if length(line_id) > 100
       or (batch_code_value is not null and length(batch_code_value) > 100) then
      raise exception 'Delivery line id or lot number is too long';
    end if;
    if expiration_date_value is not null
       and expiration_date_value < received_date_value then
      raise exception 'A product expiration date cannot be before its received date';
    end if;
    if not exists (
      select 1
      from public.ingredients as i
      where i.id = ingredient_id_value and i.is_active
    ) then
      raise exception 'A selected product is missing or inactive';
    end if;

    select *
    into existing_transaction
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
      id,
      ingredient_id,
      quantity,
      unit_cost,
      transaction_date,
      transaction_type,
      note,
      supplier_name,
      invoice_number,
      invoice_date,
      batch_code,
      expiration_date
    )
    values (
      line_id,
      ingredient_id_value,
      quantity_value,
      unit_cost_value,
      received_date_value,
      'Receiving',
      note_value,
      supplier_value,
      invoice_value,
      invoice_date_value,
      batch_code_value,
      expiration_date_value
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

revoke all on function public.costtrack_record_received_batch()
  from public, anon, authenticated;
revoke all on function public.costtrack_receive_delivery(jsonb)
  from public, anon, authenticated;
grant execute on function public.costtrack_receive_delivery(jsonb)
  to authenticated;

commit;
