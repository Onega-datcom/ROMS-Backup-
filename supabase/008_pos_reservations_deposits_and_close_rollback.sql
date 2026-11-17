-- Roll back migration 008 after stopping/reverting the Phase 3 application.
-- This refuses to downgrade live Phase 3 deposit/package activity. Additive
-- columns and audit rows are preserved rather than silently discarded.

begin;

do $$
begin
  if exists (
    select 1 from public.pos_reservation_deposits
    where idempotency_key is not null or parent_deposit_id is not null
  ) or exists (
    select 1 from public.pos_deposit_actions
  ) or exists (
    select 1 from public.reservations
    where package_charge_item_id is not null
      or package_tier_id is not null
      or package_pax_count is not null
  ) or exists (
    select 1 from public.pos_bills
    where shift_id is not null or table_id is not null
  ) or exists (
    select 1 from public.pos_bill_payments
    where shift_id is not null or reservation_deposit_id is not null
  ) or exists (
    select 1 from public.pos_cash_movements
    where movement_type in ('paid_in', 'paid_out', 'cash_refund')
  ) then
    raise exception 'Rollback stopped: Phase 3 deposit, package, shift, or bill activity exists. Export/resolve that data before rollback.';
  end if;
end;
$$;

drop function if exists public.pos_decide_bill_approval_phase3(text, text, text);
drop function if exists public.pos_request_bill_void_phase3(text, text);
drop function if exists public.pos_close_bill_phase3(text, numeric, text);
drop function if exists public.pos_save_bill_phase3(text, text, text, text, integer, integer, integer, integer, text, text, jsonb, text, text, boolean);
drop function if exists public.pos_bill_close_preview(text);
drop function if exists public.pos_reservation_deposit_decision(text, text, text);
drop function if exists public.pos_record_reservation_deposit(text, numeric, text, text);
drop table if exists public.pos_deposit_actions;

update public.pos_reservation_deposits
set status = case status
  when 'Held' then 'Outstanding'
  when 'Forfeited' then 'Voided'
  else status
end;
alter table public.pos_reservation_deposits
  drop constraint if exists pos_reservation_deposits_status_phase3_check;
alter table public.pos_reservation_deposits
  alter column status set default 'Outstanding';
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.pos_reservation_deposits'::regclass
      and conname = 'pos_reservation_deposits_status_check'
  ) then
    alter table public.pos_reservation_deposits
      add constraint pos_reservation_deposits_status_check
      check (status in ('Outstanding', 'Applied', 'Refunded', 'Voided'));
  end if;
end;
$$;

alter table public.reservations
  drop constraint if exists reservations_package_booking_check;
alter table public.pos_cash_movements
  drop constraint if exists pos_cash_movements_movement_type_phase3_check;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.pos_cash_movements'::regclass
      and conname = 'pos_cash_movements_movement_type_check'
  ) then
    alter table public.pos_cash_movements
      add constraint pos_cash_movements_movement_type_check
      check (movement_type in ('opening_float', 'cash_sale', 'refund', 'payout', 'deposit', 'adjustment'));
  end if;
end;
$$;

alter table public.reservations
  drop constraint if exists reservations_package_charge_item_id_fkey;
alter table public.reservations
  drop constraint if exists reservations_package_tier_id_fkey;
alter table public.pos_reservation_deposits
  drop constraint if exists pos_reservation_deposits_parent_deposit_id_fkey;
alter table public.pos_bill_payments
  drop constraint if exists pos_bill_payments_reservation_deposit_id_fkey;

drop index if exists public.pos_bills_one_open_per_reservation_uidx;
drop index if exists public.pos_reservation_deposits_idempotency_uidx;

drop policy if exists pos_reservation_deposits_phase3_read on public.pos_reservation_deposits;
drop policy if exists pos_reservation_deposits_admin_full on public.pos_reservation_deposits;
drop policy if exists pos_reservation_deposits_receptionist_ops on public.pos_reservation_deposits;
drop policy if exists pos_reservation_deposits_receptionist_update on public.pos_reservation_deposits;
drop policy if exists pos_reservation_deposits_receptionist_select on public.pos_reservation_deposits;

create policy pos_reservation_deposits_admin_full on public.pos_reservation_deposits
  for all to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']))
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy pos_reservation_deposits_receptionist_ops on public.pos_reservation_deposits
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy pos_reservation_deposits_receptionist_update on public.pos_reservation_deposits
  for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']))
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy pos_reservation_deposits_receptionist_select on public.pos_reservation_deposits
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
grant select, insert, update, delete on public.pos_reservation_deposits to authenticated;

-- Restore the Phase 2 calculator exactly; package-tier lines are no longer part
-- of the bill calculation after this downgrade.
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
begin
  select * into bill_row
  from public.pos_bills where id = p_bill_id for update;
  if not found then raise exception 'Bill not found.' using errcode = 'P0002'; end if;

  meal_total := round(
    bill_row.adult_count * bill_row.adult_rate_snapshot
    + bill_row.senior_count * bill_row.senior_rate_snapshot
    + bill_row.kids_count * bill_row.kids_rate_snapshot, 2
  );
  select coalesce(sum(quantity * unit_price), 0),
    coalesce(sum(food_revenue_amount), 0),
    coalesce(sum(non_food_revenue_amount), 0)
  into extra_total, extra_food, extra_non_food
  from public.pos_bill_lines
  where bill_id = bill_row.id and line_type = 'charge_item' and not is_voided;

  subtotal_value := round(meal_total + extra_total, 2);
  food_value := round(meal_total + extra_food, 2);
  non_food_value := round(extra_non_food, 2);
  select setting_value into service_mode from public.pos_settings
  where setting_key = 'pos_service_charge_mode';
  service_mode := coalesce(service_mode, 'none');

  if service_mode = 'percent' then
    select coalesce(nullif(setting_value, '')::numeric, 0) into service_percent
    from public.pos_settings where setting_key = 'pos_service_charge_percent';
    if coalesce(service_percent, 0) < 0 or coalesce(service_percent, 0) > 100 then
      raise exception 'Service-charge percent must be between 0 and 100.' using errcode = '22023';
    end if;
    service_value := round(subtotal_value * coalesce(service_percent, 0) / 100, 2);
  elsif service_mode = 'per_head' then
    select coalesce(nullif(setting_value, '')::numeric, 0) into service_per_head
    from public.pos_settings where setting_key = 'pos_service_charge_per_head';
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

  select coalesce(sum(amount) filter (where payment_method = 'deposit'), 0),
    coalesce(sum(amount) filter (where payment_method <> 'deposit'), 0)
  into deposit_value, paid_value
  from public.pos_bill_payments where bill_id = bill_row.id;
  update public.pos_bills
  set subtotal = subtotal_value, service_charge = service_value,
      discount_total = discount_value, deposit_total = deposit_value,
      paid_total = paid_value,
      balance_due = greatest(0, subtotal_value + service_value - discount_value - deposit_value - paid_value),
      food_revenue_total = food_value, non_food_revenue_total = non_food_value + service_value,
      customers_served = adult_count + senior_count + kids_count + comped_count
  where id = bill_row.id returning * into bill_row;
  return to_jsonb(bill_row);
end;
$$;

revoke all on function public.pos_recalculate_bill(text) from public, anon, authenticated;
grant execute on function public.pos_save_bill(text, text, text, text, integer, integer, integer, integer, text, text, jsonb, numeric, text) to authenticated;
grant execute on function public.pos_close_bill(text, numeric, text) to authenticated;
grant execute on function public.pos_request_bill_void(text, text) to authenticated;
grant execute on function public.pos_decide_bill_approval(text, text, text) to authenticated;

commit;
