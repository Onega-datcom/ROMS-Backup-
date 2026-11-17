-- POS Phase 3 (part 2): reservation package booking, deposits, bill/shift
-- workflow, approval handling, and atomic bill close.
-- Run after 007_pos_shifts_and_notifications.sql.

begin;

alter table public.reservations
  add column if not exists package_charge_item_id text,
  add column if not exists package_tier_id text,
  add column if not exists package_pax_count integer;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reservations'::regclass
      and conname = 'reservations_package_charge_item_id_fkey'
  ) then
    alter table public.reservations
      add constraint reservations_package_charge_item_id_fkey
      foreign key (package_charge_item_id)
      references public.pos_charge_items(id) on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reservations'::regclass
      and conname = 'reservations_package_tier_id_fkey'
  ) then
    alter table public.reservations
      add constraint reservations_package_tier_id_fkey
      foreign key (package_tier_id)
      references public.pos_package_tiers(id) on delete restrict;
  end if;
end;
$$;

alter table public.reservations
  drop constraint if exists reservations_package_booking_check;
alter table public.reservations
  add constraint reservations_package_booking_check check (
    (package_charge_item_id is null and package_tier_id is null and package_pax_count is null)
    or (package_charge_item_id is not null and package_tier_id is not null
      and package_pax_count is not null and package_pax_count > 0)
  );

alter table public.pos_bill_payments
  add column if not exists reservation_deposit_id text;
alter table public.pos_reservation_deposits
  add column if not exists parent_deposit_id text,
  add column if not exists idempotency_key text;

do $$
declare
  constraint_row record;
begin
  for constraint_row in
    select conname
    from pg_constraint
    where conrelid = 'public.pos_reservation_deposits'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.pos_reservation_deposits drop constraint %I',
      constraint_row.conname);
  end loop;
end;
$$;

update public.pos_reservation_deposits
set status = case status
  when 'Outstanding' then 'Held'
  when 'Voided' then 'Forfeited'
  else status
end;

alter table public.pos_reservation_deposits
  alter column status set default 'Held';
alter table public.pos_reservation_deposits
  add constraint pos_reservation_deposits_status_phase3_check
  check (status in ('Held', 'Applied', 'Refunded', 'Forfeited'));

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.pos_reservation_deposits'::regclass
      and conname = 'pos_reservation_deposits_parent_deposit_id_fkey'
  ) then
    alter table public.pos_reservation_deposits
      add constraint pos_reservation_deposits_parent_deposit_id_fkey
      foreign key (parent_deposit_id)
      references public.pos_reservation_deposits(id) on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.pos_bill_payments'::regclass
      and conname = 'pos_bill_payments_reservation_deposit_id_fkey'
  ) then
    alter table public.pos_bill_payments
      add constraint pos_bill_payments_reservation_deposit_id_fkey
      foreign key (reservation_deposit_id)
      references public.pos_reservation_deposits(id) on delete restrict;
  end if;
end;
$$;

create unique index if not exists pos_reservation_deposits_idempotency_uidx
  on public.pos_reservation_deposits (idempotency_key)
  where idempotency_key is not null;
create unique index if not exists pos_bills_one_open_per_reservation_uidx
  on public.pos_bills (reservation_id)
  where reservation_id is not null and status = 'Open';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.pos_cash_movements'::regclass
      and conname = 'pos_cash_movements_movement_type_phase3_check'
  ) then
    alter table public.pos_cash_movements
      drop constraint if exists pos_cash_movements_movement_type_check;
    alter table public.pos_cash_movements
      add constraint pos_cash_movements_movement_type_phase3_check
      check (movement_type in (
        'opening_float', 'cash_sale', 'refund', 'payout', 'deposit', 'adjustment',
        'paid_in', 'paid_out', 'cash_refund'
      ));
  end if;
end;
$$;

insert into public.pos_settings
  (id, setting_key, setting_value, setting_type, description, is_system)
values
  ('pos-setting-extra-pax-rate', 'pos_extra_pax_rate', '0', 'number',
   'Cashier charge per guest above the reservation package tier; zero means not configured.', true)
on conflict (setting_key) do nothing;

create table if not exists public.pos_deposit_actions (
  id text primary key default gen_random_uuid()::text,
  deposit_id text not null references public.pos_reservation_deposits(id) on delete restrict,
  action_type text not null check (action_type in ('received', 'applied', 'refunded', 'forfeited', 'restored')),
  amount numeric(12,2) not null check (amount > 0),
  bill_id text references public.pos_bills(id) on delete set null,
  reason text not null default '',
  acted_by uuid not null,
  acted_at timestamptz not null default now()
);
create index if not exists pos_deposit_actions_deposit_idx
  on public.pos_deposit_actions (deposit_id, acted_at);
alter table public.pos_deposit_actions enable row level security;
drop policy if exists pos_deposit_actions_role_read on public.pos_deposit_actions;
create policy pos_deposit_actions_role_read on public.pos_deposit_actions
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
revoke all on public.pos_deposit_actions from public, anon, authenticated;
grant select on public.pos_deposit_actions to authenticated;

-- A package replaces standard meal pricing for a booked reservation. Add-on
-- lines continue to use the Phase 2 charge catalog and its food flag.
create or replace function public.pos_recalculate_bill(p_bill_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  bill_row public.pos_bills%rowtype;
  extra_total numeric(12,2);
  extra_food numeric(12,2);
  extra_non_food numeric(12,2);
  meal_total numeric(12,2);
  subtotal_value numeric(12,2);
  service_value numeric(12,2);
  discount_value numeric(12,2);
  deposit_value numeric(12,2);
  paid_value numeric(12,2);
  food_value numeric(12,2);
  non_food_value numeric(12,2);
  service_mode text;
  service_percent numeric(12,4);
  service_per_head numeric(12,2);
  has_package boolean;
begin
  select * into bill_row
  from public.pos_bills where id = p_bill_id for update;
  if not found then
    raise exception 'Bill not found.' using errcode = 'P0002';
  end if;

  select exists (
    select 1 from public.pos_bill_lines
    where bill_id = bill_row.id and line_type = 'package' and not is_voided
  ) into has_package;

  meal_total := case when has_package then 0 else round(
    bill_row.adult_count * bill_row.adult_rate_snapshot
    + bill_row.senior_count * bill_row.senior_rate_snapshot
    + bill_row.kids_count * bill_row.kids_rate_snapshot,
    2
  ) end;

  select
    coalesce(sum(quantity * unit_price), 0),
    coalesce(sum(food_revenue_amount), 0),
    coalesce(sum(non_food_revenue_amount), 0)
  into extra_total, extra_food, extra_non_food
  from public.pos_bill_lines
  where bill_id = bill_row.id
    and line_type in ('charge_item', 'package')
    and not is_voided;

  subtotal_value := round(meal_total + extra_total, 2);
  food_value := round(meal_total + extra_food, 2);
  non_food_value := round(extra_non_food, 2);

  select setting_value into service_mode
  from public.pos_settings where setting_key = 'pos_service_charge_mode';
  service_mode := coalesce(service_mode, 'none');

  if service_mode = 'percent' then
    select coalesce(nullif(setting_value, '')::numeric, 0)
    into service_percent from public.pos_settings
    where setting_key = 'pos_service_charge_percent';
    if coalesce(service_percent, 0) < 0 or coalesce(service_percent, 0) > 100 then
      raise exception 'Service-charge percent must be between 0 and 100.' using errcode = '22023';
    end if;
    service_value := round(subtotal_value * coalesce(service_percent, 0) / 100, 2);
  elsif service_mode = 'per_head' then
    select coalesce(nullif(setting_value, '')::numeric, 0)
    into service_per_head from public.pos_settings
    where setting_key = 'pos_service_charge_per_head';
    if coalesce(service_per_head, 0) < 0 or coalesce(service_per_head, 0) > 10000 then
      raise exception 'Per-head service charge must be between 0 and 10,000.' using errcode = '22023';
    end if;
    service_value := round(
      (bill_row.adult_count + bill_row.senior_count + bill_row.kids_count)
      * coalesce(service_per_head, 0), 2
    );
  elsif service_mode = 'none' then
    service_value := 0;
  else
    raise exception 'Invalid POS service-charge mode: %.', service_mode using errcode = '22023';
  end if;

  if bill_row.discount_id is null then
    discount_value := 0;
  elsif subtotal_value < coalesce(bill_row.discount_minimum_snapshot, 0) then
    discount_value := 0;
  elsif bill_row.discount_type_snapshot = 'percent' then
    if coalesce(bill_row.discount_value_snapshot, 0) > 100 then
      raise exception 'Percent discounts cannot exceed 100%%.' using errcode = '22023';
    end if;
    discount_value := round(subtotal_value * coalesce(bill_row.discount_value_snapshot, 0) / 100, 2);
  elsif bill_row.discount_type_snapshot = 'fixed' then
    discount_value := least(subtotal_value, coalesce(bill_row.discount_value_snapshot, 0));
  elsif bill_row.discount_type_snapshot = 'waive' then
    discount_value := subtotal_value;
  else
    raise exception 'The selected discount has an invalid snapshot.' using errcode = '22023';
  end if;

  select
    coalesce(sum(amount) filter (where payment_method = 'deposit'), 0),
    coalesce(sum(amount) filter (where payment_method <> 'deposit'), 0)
  into deposit_value, paid_value
  from public.pos_bill_payments where bill_id = bill_row.id;

  update public.pos_bills
  set subtotal = subtotal_value,
      service_charge = service_value,
      discount_total = discount_value,
      deposit_total = deposit_value,
      paid_total = paid_value,
      balance_due = greatest(0, subtotal_value + service_value - discount_value - deposit_value - paid_value),
      food_revenue_total = food_value,
      non_food_revenue_total = non_food_value + service_value,
      customers_served = adult_count + senior_count + kids_count + comped_count
  where id = bill_row.id returning * into bill_row;
  return to_jsonb(bill_row);
end;
$$;

create or replace function public.pos_record_reservation_deposit(
  p_reservation_id text,
  p_amount numeric,
  p_notes text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  shift_row public.pos_shifts%rowtype;
  reservation_row public.reservations%rowtype;
  deposit_row public.pos_reservation_deposits%rowtype;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Receptionist'])
    or auth.uid() is null then
    raise exception 'Your role cannot record reservation deposits.' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then
    raise exception 'Deposit amount must be greater than zero with at most two decimals.'
      using errcode = '22023';
  end if;
  if length(trim(coalesce(p_notes, ''))) > 500
    or length(trim(coalesce(p_idempotency_key, ''))) = 0
    or length(p_idempotency_key) > 200 then
    raise exception 'Enter a valid reason/note and idempotency key.' using errcode = '22023';
  end if;

  select * into shift_row from public.pos_shifts
  where opened_by = auth.uid() and status = 'Open' for update;
  if not found then
    raise exception 'Open your cashier shift before recording a deposit.' using errcode = '55000';
  end if;
  select * into reservation_row from public.reservations
  where id = p_reservation_id for update;
  if not found then
    raise exception 'Reservation not found.' using errcode = 'P0002';
  end if;

  select * into deposit_row from public.pos_reservation_deposits
  where idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('deposit', to_jsonb(deposit_row), 'already_recorded', true);
  end if;

  insert into public.pos_reservation_deposits (
    id, reservation_id, amount, payment_method, status, notes, created_by,
    received_shift_id, receipt_amount, idempotency_key
  ) values (
    gen_random_uuid()::text, reservation_row.id, p_amount, 'cash', 'Held',
    nullif(trim(p_notes), ''), auth.uid(), shift_row.id, p_amount, p_idempotency_key
  ) returning * into deposit_row;

  insert into public.pos_deposit_actions (
    deposit_id, action_type, amount, reason, acted_by
  ) values (deposit_row.id, 'received', p_amount, coalesce(nullif(trim(p_notes), ''), 'Cash deposit received'), auth.uid());

  return jsonb_build_object('deposit', to_jsonb(deposit_row), 'already_recorded', false);
end;
$$;

create or replace function public.pos_reservation_deposit_decision(
  p_deposit_id text,
  p_decision text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  deposit_row public.pos_reservation_deposits%rowtype;
  shift_row public.pos_shifts%rowtype;
  decision_value text := lower(trim(coalesce(p_decision, '')));
  movement_type_value text;
begin
  if not public.has_app_role(array['Administrator', 'Manager']) then
    raise exception 'Only a Manager or Administrator can refund or forfeit deposits.'
      using errcode = '42501';
  end if;
  if decision_value not in ('refund', 'forfeit')
    or length(trim(coalesce(p_reason, ''))) = 0
    or length(trim(p_reason)) > 500 then
    raise exception 'Choose refund or forfeit and provide a reason of 1 to 500 characters.'
      using errcode = '22023';
  end if;

  select * into deposit_row from public.pos_reservation_deposits
  where id = p_deposit_id for update;
  if not found then
    raise exception 'Deposit not found.' using errcode = 'P0002';
  end if;
  if deposit_row.status <> 'Held' or deposit_row.bill_id is not null then
    raise exception 'Only an unapplied Held deposit can be refunded or forfeited.'
      using errcode = '55000';
  end if;

  if decision_value = 'refund' then
    select * into shift_row from public.pos_shifts
    where opened_by = auth.uid() and status = 'Open' for update;
    if not found then
      raise exception 'An open Manager shift is required to refund cash.' using errcode = '55000';
    end if;
    insert into public.pos_cash_movements (
      id, shift_id, movement_type, amount, reason, created_by
    ) values (
      gen_random_uuid()::text, shift_row.id, 'cash_refund', deposit_row.amount,
      trim(p_reason), auth.uid()
    );
    update public.pos_reservation_deposits
    set status = 'Refunded'
    where id = deposit_row.id returning * into deposit_row;
    movement_type_value := 'refunded';
  else
    update public.pos_reservation_deposits
    set status = 'Forfeited'
    where id = deposit_row.id returning * into deposit_row;
    movement_type_value := 'forfeited';
  end if;

  insert into public.pos_deposit_actions (
    deposit_id, action_type, amount, reason, acted_by
  ) values (
    deposit_row.id, movement_type_value, deposit_row.amount, trim(p_reason), auth.uid()
  );
  return jsonb_build_object('deposit', to_jsonb(deposit_row));
end;
$$;

create or replace function public.pos_bill_close_preview(p_bill_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  bill_row public.pos_bills%rowtype;
  held_total numeric(12,2) := 0;
  apply_total numeric(12,2) := 0;
  remainder_total numeric(12,2) := 0;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Receptionist']) then
    raise exception 'Your role cannot view bill-close details.' using errcode = '42501';
  end if;
  select * into bill_row from public.pos_bills where id = p_bill_id;
  if not found then raise exception 'Bill not found.' using errcode = 'P0002'; end if;
  if public.current_app_role() = 'Receptionist'
    and bill_row.created_by is distinct from auth.uid() then
    raise exception 'Receptionists can view close details only for bills they created.'
      using errcode = '42501';
  end if;
  if bill_row.reservation_id is not null then
    select coalesce(sum(amount), 0) into held_total
    from public.pos_reservation_deposits
    where reservation_id = bill_row.reservation_id and status = 'Held' and bill_id is null;
  end if;
  apply_total := least(held_total, bill_row.balance_due);
  remainder_total := greatest(0, held_total - apply_total);
  return jsonb_build_object(
    'balance_due', bill_row.balance_due,
    'held_deposits', held_total,
    'deposit_to_apply', apply_total,
    'deposit_remainder', remainder_total,
    'balance_after_deposit', greatest(0, bill_row.balance_due - apply_total)
  );
end;
$$;

create or replace function public.pos_save_bill_phase3(
  p_bill_id text,
  p_customer_name text,
  p_notes text,
  p_reservation_id text,
  p_adult_count integer,
  p_senior_count integer,
  p_kids_count integer,
  p_comped_count integer,
  p_discount_id text,
  p_discount_reason text,
  p_extra_lines jsonb,
  p_idempotency_key text,
  p_table_id text,
  p_charge_extra_pax boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  shift_row public.pos_shifts%rowtype;
  reservation_row public.reservations%rowtype;
  bill_row public.pos_bills%rowtype;
  existing_reservation_id text;
  package_item public.pos_charge_items%rowtype;
  tier_row public.pos_package_tiers%rowtype;
  extra_rate numeric(12,2);
  actual_pax integer;
  extra_pax integer;
  bill_result jsonb;
  line_id text;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Receptionist'])
    or auth.uid() is null then
    raise exception 'Your role cannot create or edit POS bills.' using errcode = '42501';
  end if;

  select * into shift_row from public.pos_shifts
  where opened_by = auth.uid() and status = 'Open' for update;
  if not found then
    raise exception 'Open your cashier shift before creating or editing a bill.'
      using errcode = '55000';
  end if;

  if p_reservation_id is not null then
    select * into reservation_row from public.reservations
    where id = p_reservation_id for update;
    if not found then raise exception 'Reservation not found.' using errcode = 'P0002'; end if;
    if reservation_row.status <> 'Seated' and reservation_row.status <> 'Completed' then
      raise exception 'A POS bill can be opened only for a seated reservation.'
        using errcode = '55000';
    end if;
  end if;
  if p_bill_id is not null then
    select reservation_id into existing_reservation_id
    from public.pos_bills
    where id = p_bill_id
    for update;
    if not found then raise exception 'Bill not found.' using errcode = 'P0002'; end if;
    if existing_reservation_id is distinct from p_reservation_id then
      raise exception 'A saved bill cannot be reassigned to a different reservation.'
        using errcode = '22023';
    end if;
  end if;

  bill_result := public.pos_save_bill(
    p_bill_id => p_bill_id,
    p_customer_name => p_customer_name,
    p_notes => p_notes,
    p_reservation_id => p_reservation_id,
    p_adult_count => p_adult_count,
    p_senior_count => p_senior_count,
    p_kids_count => p_kids_count,
    p_comped_count => p_comped_count,
    p_discount_id => p_discount_id,
    p_discount_reason => p_discount_reason,
    p_extra_lines => coalesce(p_extra_lines, '[]'::jsonb),
    p_initial_deposit => 0,
    p_idempotency_key => p_idempotency_key
  );
  select * into bill_row from public.pos_bills
  where id = bill_result->'bill'->>'id' for update;

  if bill_row.shift_id is not null and bill_row.shift_id <> shift_row.id then
    raise exception 'This bill belongs to a different cashier shift.' using errcode = '42501';
  end if;
  if bill_row.shift_id is null then
    update public.pos_bills
    set shift_id = shift_row.id,
        table_id = coalesce(p_table_id, reservation_row.table_id)
    where id = bill_row.id returning * into bill_row;
  elsif p_table_id is not null and bill_row.table_id is distinct from p_table_id then
    update public.pos_bills set table_id = p_table_id
    where id = bill_row.id returning * into bill_row;
  end if;

  if p_reservation_id is not null and reservation_row.package_charge_item_id is not null
    and not exists (
      select 1 from public.pos_bill_lines
      where bill_id = bill_row.id and line_type = 'package' and not is_voided
    ) then
    select * into package_item from public.pos_charge_items
    where id = reservation_row.package_charge_item_id
      and type = 'package' and is_package and is_active;
    if not found then raise exception 'The reservation package is no longer active.' using errcode = '55000'; end if;
    select * into tier_row from public.pos_package_tiers
    where id = reservation_row.package_tier_id and is_active;
    if not found then raise exception 'The reservation package tier is no longer active.' using errcode = '55000'; end if;

    insert into public.pos_bill_lines (
      id, bill_id, charge_item_id, package_tier_id, description, quantity, unit_price,
      line_type, food_revenue_amount, non_food_revenue_amount,
      is_food_revenue_snapshot, created_by
    ) values (
      gen_random_uuid()::text, bill_row.id, package_item.id, tier_row.id,
      package_item.name || ' · ' || tier_row.name,
      reservation_row.package_pax_count, tier_row.base_price, 'package',
      round(reservation_row.package_pax_count * tier_row.base_price, 2), 0, true, auth.uid()
    );

    actual_pax := coalesce(
      nullif(reservation_row.actual_covers, 0),
      reservation_row.guests
    );
    extra_pax := greatest(0, actual_pax - reservation_row.package_pax_count);
    if extra_pax > 0 and coalesce(p_charge_extra_pax, false) then
      select coalesce(nullif(setting_value, '')::numeric, 0)
      into extra_rate from public.pos_settings where setting_key = 'pos_extra_pax_rate';
      if coalesce(extra_rate, 0) <= 0 then
        raise exception 'No extra-pax rate is configured; save without the extra-pax charge or ask an Administrator to set one.'
          using errcode = '55000';
      end if;
      insert into public.pos_bill_lines (
        id, bill_id, charge_item_id, package_tier_id, description, quantity, unit_price,
        line_type, food_revenue_amount, non_food_revenue_amount,
        is_food_revenue_snapshot, created_by
      ) values (
        gen_random_uuid()::text, bill_row.id, package_item.id, tier_row.id,
        'Extra pax · ' || package_item.name, extra_pax, extra_rate, 'package',
        round(extra_pax * extra_rate, 2), 0, true, auth.uid()
      );
    end if;
  end if;

  bill_result := jsonb_build_object(
    'bill', public.pos_recalculate_bill(bill_row.id),
    'lines', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at)
      from public.pos_bill_lines x where x.bill_id = bill_row.id
    ), '[]'::jsonb),
    'already_created', coalesce((bill_result->>'already_created')::boolean, false)
  );
  return bill_result;
end;
$$;

create or replace function public.pos_close_bill_phase3(
  p_bill_id text,
  p_tendered_amount numeric,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  bill_row public.pos_bills%rowtype;
  deposit_row public.pos_reservation_deposits%rowtype;
  applied_row public.pos_reservation_deposits%rowtype;
  payment_row public.pos_bill_payments%rowtype;
  reservation_row public.reservations%rowtype;
  close_result jsonb;
  due_before numeric(12,2);
  apply_amount numeric(12,2);
  remaining_due numeric(12,2);
  deposit_applied numeric(12,2) := 0;
  cash_refund numeric(12,2);
  shift_row public.pos_shifts%rowtype;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Receptionist']) then
    raise exception 'Your role cannot close POS bills.' using errcode = '42501';
  end if;

  select * into bill_row from public.pos_bills
  where id = p_bill_id for update;
  if not found then raise exception 'Bill not found.' using errcode = 'P0002'; end if;
  if public.current_app_role() = 'Receptionist'
    and bill_row.created_by is distinct from auth.uid() then
    raise exception 'Receptionists can close only bills they created.' using errcode = '42501';
  end if;
  if bill_row.status = 'Closed' then
    select * into payment_row from public.pos_bill_payments
    where bill_id = bill_row.id and payment_method = 'cash'
    order by paid_at desc limit 1;
    return jsonb_build_object(
      'bill', to_jsonb(bill_row), 'payment', to_jsonb(payment_row), 'already_closed', true
    );
  end if;
  if bill_row.status <> 'Open' then
    raise exception 'A voided bill cannot be closed.' using errcode = '55000';
  end if;
  if bill_row.shift_id is null then
    select * into shift_row from public.pos_shifts
    where opened_by = auth.uid() and status = 'Open' for update;
    if not found then
      raise exception 'Open your cashier shift before closing this legacy bill.'
        using errcode = '55000';
    end if;
    update public.pos_bills b
    set shift_id = shift_row.id,
        table_id = coalesce(b.table_id, (
          select r.table_id from public.reservations r where r.id = b.reservation_id
        ))
    where b.id = bill_row.id returning b.* into bill_row;
  end if;
  select * into shift_row from public.pos_shifts
  where id = bill_row.shift_id for update;
  if not found or shift_row.status <> 'Open' then
    raise exception 'The bill’s cashier shift is not open.' using errcode = '55000';
  end if;

  perform public.pos_recalculate_bill(bill_row.id);
  select * into bill_row from public.pos_bills where id = bill_row.id;
  due_before := bill_row.balance_due;
  remaining_due := due_before;

  if bill_row.reservation_id is not null then
    select * into reservation_row from public.reservations
    where id = bill_row.reservation_id for update;
    for deposit_row in
      select * from public.pos_reservation_deposits
      where reservation_id = bill_row.reservation_id and status = 'Held' and bill_id is null
      order by created_at, id for update
    loop
      exit when remaining_due <= 0;
      apply_amount := least(deposit_row.amount, remaining_due);
      if apply_amount = deposit_row.amount then
        update public.pos_reservation_deposits
        set status = 'Applied', bill_id = bill_row.id
        where id = deposit_row.id returning * into applied_row;
      else
        update public.pos_reservation_deposits
        set amount = deposit_row.amount - apply_amount
        where id = deposit_row.id;
        insert into public.pos_reservation_deposits (
          id, reservation_id, bill_id, amount, payment_method, status, notes,
          created_by, received_shift_id, receipt_amount, parent_deposit_id
        ) values (
          gen_random_uuid()::text, deposit_row.reservation_id, bill_row.id,
          apply_amount, 'cash', 'Applied', deposit_row.notes, deposit_row.created_by,
          deposit_row.received_shift_id, 0, deposit_row.id
        ) returning * into applied_row;
      end if;

      insert into public.pos_bill_payments (
        id, bill_id, payment_method, amount, tendered_amount, change_amount,
        paid_by, idempotency_key, reservation_deposit_id
      ) values (
        gen_random_uuid()::text, bill_row.id, 'deposit', apply_amount,
        apply_amount, 0, auth.uid(), 'deposit:' || applied_row.id, applied_row.id
      ) on conflict (bill_id, idempotency_key) where idempotency_key is not null do nothing;

      insert into public.pos_deposit_actions (
        deposit_id, action_type, amount, bill_id, reason, acted_by
      ) values (
        applied_row.id, 'applied', apply_amount, bill_row.id,
        'Applied to bill at close', auth.uid()
      );
      deposit_applied := deposit_applied + apply_amount;
      remaining_due := remaining_due - apply_amount;
    end loop;
  end if;

  if remaining_due > 0 and (p_tendered_amount is null or p_tendered_amount < remaining_due) then
    raise exception 'Tendered cash is less than the balance after deposits (%).', remaining_due
      using errcode = '22023';
  end if;
  if remaining_due = 0 and coalesce(p_tendered_amount, 0) <> 0 then
    raise exception 'No cash is due after applying deposits; tendered cash must be zero.'
      using errcode = '22023';
  end if;

  close_result := public.pos_close_bill(bill_row.id, coalesce(p_tendered_amount, 0), p_idempotency_key);

  update public.pos_bill_payments
  set shift_id = bill_row.shift_id
  where bill_id = bill_row.id and payment_method = 'cash'
    and idempotency_key = p_idempotency_key;

  if bill_row.reservation_id is not null then
    update public.reservations
    set status = 'Completed',
        completed_at = coalesce(completed_at, now()),
        actual_covers = bill_row.adult_count + bill_row.senior_count
          + bill_row.kids_count + bill_row.comped_count
    where id = bill_row.reservation_id;
  end if;
  if bill_row.table_id is not null then
    update public.restaurant_tables set status = 'Needs cleaning'
    where id = bill_row.table_id;
  end if;

  return close_result || jsonb_build_object('deposit_applied', deposit_applied);
end;
$$;

create or replace function public.pos_request_bill_void_phase3(
  p_bill_id text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  bill_row public.pos_bills%rowtype;
  approval_row public.pos_bill_approvals%rowtype;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Receptionist']) then
    raise exception 'Your role cannot request a bill void.' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_reason, ''))) = 0 or length(trim(p_reason)) > 500 then
    raise exception 'Enter a void reason of 1 to 500 characters.' using errcode = '22023';
  end if;
  select * into bill_row from public.pos_bills where id = p_bill_id for update;
  if not found then raise exception 'Bill not found.' using errcode = 'P0002'; end if;
  if bill_row.status = 'Voided' then
    raise exception 'This bill is already voided.' using errcode = '55000';
  end if;
  if public.current_app_role() = 'Receptionist' and bill_row.created_by is distinct from auth.uid() then
    raise exception 'Receptionists can request voids only for bills they created.' using errcode = '42501';
  end if;
  select * into approval_row from public.pos_bill_approvals
  where bill_id = bill_row.id and request_type = 'void' and status = 'Pending'
  order by requested_at desc limit 1;
  if not found then
    insert into public.pos_bill_approvals (
      id, bill_id, request_type, status, request_reason, requested_by
    ) values (
      gen_random_uuid()::text, bill_row.id, 'void', 'Pending', trim(p_reason), auth.uid()
    ) returning * into approval_row;
  end if;
  return jsonb_build_object('approval', to_jsonb(approval_row), 'bill', to_jsonb(bill_row));
end;
$$;

create or replace function public.pos_decide_bill_approval_phase3(
  p_approval_id text,
  p_decision text,
  p_decision_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  approval_row public.pos_bill_approvals%rowtype;
  bill_row public.pos_bills%rowtype;
  shift_row public.pos_shifts%rowtype;
  cash_refund numeric(12,2);
  decision_value text := lower(trim(coalesce(p_decision, '')));
begin
  if not public.has_app_role(array['Administrator', 'Manager']) then
    raise exception 'Only a Manager or Administrator can decide POS approvals.' using errcode = '42501';
  end if;
  if decision_value not in ('approve', 'reject') then
    raise exception 'Choose approve or reject.' using errcode = '22023';
  end if;

  select * into approval_row from public.pos_bill_approvals
  where id = p_approval_id for update;
  if not found then raise exception 'Approval request not found.' using errcode = 'P0002'; end if;
  if approval_row.requested_by = auth.uid() then
    raise exception 'You cannot approve or reject your own request.' using errcode = '42501';
  end if;
  if approval_row.status <> 'Pending' then
    if (approval_row.status = 'Approved' and decision_value = 'approve')
      or (approval_row.status = 'Rejected' and decision_value = 'reject') then
      return jsonb_build_object('approval', to_jsonb(approval_row), 'already_decided', true);
    end if;
    raise exception 'This approval request has already been decided.' using errcode = '55000';
  end if;
  if decision_value = 'reject' and length(trim(coalesce(p_decision_reason, ''))) = 0 then
    raise exception 'A rejection reason is required.' using errcode = '22023';
  end if;

  select * into bill_row from public.pos_bills
  where id = approval_row.bill_id for update;
  if not found then raise exception 'Bill not found.' using errcode = 'P0002'; end if;

  if approval_row.request_type = 'full_discount'
    or (approval_row.request_type = 'void' and bill_row.status = 'Open'
      and bill_row.deposit_total = 0 and bill_row.paid_total = 0) then
    return public.pos_decide_bill_approval(
      p_approval_id, decision_value, coalesce(p_decision_reason, '')
    );
  end if;
  if approval_row.request_type <> 'void' or bill_row.status <> 'Closed' then
    raise exception 'This approval no longer applies to the bill.' using errcode = '55000';
  end if;

  if decision_value = 'approve' then
    select coalesce(sum(amount), 0) into cash_refund
    from public.pos_bill_payments
    where bill_id = bill_row.id and payment_method = 'cash';
    if cash_refund > 0 then
      select * into shift_row from public.pos_shifts
      where opened_by = auth.uid() and status = 'Open' for update;
      if not found then
        raise exception 'An open Manager shift is required to refund cash for this bill.'
          using errcode = '55000';
      end if;
      insert into public.pos_cash_movements (
        id, shift_id, movement_type, amount, reason, created_by, reference
      ) values (
        gen_random_uuid()::text, shift_row.id, 'cash_refund', cash_refund,
        trim(approval_row.request_reason), auth.uid(), bill_row.bill_number
      );
    end if;

    insert into public.pos_deposit_actions (
      deposit_id, action_type, amount, bill_id, reason, acted_by
    )
    select id, 'restored', amount, bill_row.id, approval_row.request_reason, auth.uid()
    from public.pos_reservation_deposits
    where bill_id = bill_row.id and status = 'Applied';
    update public.pos_reservation_deposits
    set status = 'Held', bill_id = null
    where bill_id = bill_row.id and status = 'Applied';

    update public.pos_bills
    set status = 'Voided', voided_by = auth.uid(),
        voided_at = now(), void_reason = approval_row.request_reason
    where id = bill_row.id returning * into bill_row;
    update public.pos_bill_approvals
    set status = 'Cancelled', decided_by = auth.uid(), decided_at = now(),
        decision_reason = 'Bill was voided.'
    where bill_id = bill_row.id and status = 'Pending' and id <> approval_row.id;
  end if;

  update public.pos_bill_approvals
  set status = case when decision_value = 'approve' then 'Approved' else 'Rejected' end,
      decided_by = auth.uid(), decided_at = now(),
      decision_reason = case when decision_value = 'approve'
        then coalesce(nullif(trim(p_decision_reason), ''), 'Approved')
        else trim(p_decision_reason) end
  where id = approval_row.id returning * into approval_row;
  return jsonb_build_object('approval', to_jsonb(approval_row), 'bill', to_jsonb(bill_row));
end;
$$;

-- Restrict table writes and all money/state changes to validated RPCs.
alter table public.pos_reservation_deposits enable row level security;
do $$
declare
  policy_row record;
begin
  for policy_row in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'pos_reservation_deposits'
  loop
    execute format('drop policy if exists %I on public.pos_reservation_deposits', policy_row.policyname);
  end loop;
end;
$$;
create policy pos_reservation_deposits_phase3_read
  on public.pos_reservation_deposits for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
revoke all on public.pos_reservation_deposits from public, anon, authenticated;
grant select on public.pos_reservation_deposits to authenticated;

revoke all on function public.pos_recalculate_bill(text) from public, anon, authenticated;
revoke all on function public.pos_save_bill(text, text, text, text, integer, integer, integer, integer, text, text, jsonb, numeric, text) from public, anon, authenticated;
revoke all on function public.pos_close_bill(text, numeric, text) from public, anon, authenticated;
revoke all on function public.pos_request_bill_void(text, text) from public, anon, authenticated;
revoke all on function public.pos_decide_bill_approval(text, text, text) from public, anon, authenticated;

revoke all on function public.pos_record_reservation_deposit(text, numeric, text, text) from public, anon;
revoke all on function public.pos_reservation_deposit_decision(text, text, text) from public, anon;
revoke all on function public.pos_bill_close_preview(text) from public, anon;
revoke all on function public.pos_save_bill_phase3(text, text, text, text, integer, integer, integer, integer, text, text, jsonb, text, text, boolean) from public, anon;
revoke all on function public.pos_close_bill_phase3(text, numeric, text) from public, anon;
revoke all on function public.pos_request_bill_void_phase3(text, text) from public, anon;
revoke all on function public.pos_decide_bill_approval_phase3(text, text, text) from public, anon;

grant execute on function public.pos_record_reservation_deposit(text, numeric, text, text) to authenticated;
grant execute on function public.pos_reservation_deposit_decision(text, text, text) to authenticated;
grant execute on function public.pos_bill_close_preview(text) to authenticated;
grant execute on function public.pos_save_bill_phase3(text, text, text, text, integer, integer, integer, integer, text, text, jsonb, text, text, boolean) to authenticated;
grant execute on function public.pos_close_bill_phase3(text, numeric, text) to authenticated;
grant execute on function public.pos_request_bill_void_phase3(text, text) to authenticated;
grant execute on function public.pos_decide_bill_approval_phase3(text, text, text) to authenticated;

commit;
