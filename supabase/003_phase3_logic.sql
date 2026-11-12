-- CostTrack Phase 3 live-data logic migration.
-- Run as a database owner. No existing data is deleted and Phase 2 RLS is
-- preserved.

begin;

-- PHASE 3: table-status values used by lifecycle automation.
update public.restaurant_tables
set status = case lower(status)
  when 'available' then 'Available'
  when 'occupied' then 'Occupied'
  when 'reserved' then 'Reserved'
  else status
end
where lower(status) in ('available', 'occupied', 'reserved');

-- PHASE 3: private public-reservation rate-limit ledger.
create table if not exists public.public_reservation_attempts (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  contact_key text not null,
  ip text not null default 'unknown'
);
alter table public.public_reservation_attempts enable row level security;
revoke all on table public.public_reservation_attempts from public, anon, authenticated;

-- PHASE 3: receiving updates latest ingredient cost only.
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
      cost = case
        when new.transaction_type = 'Receiving' and new.unit_cost > 0
          then new.unit_cost
        else cost
      end
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

-- PHASE 3: lifecycle and revenue validation triggers.
create or replace function public.validate_revenue_record()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.adult_customers = 0
     and new.child_customers = 0
     and new.senior_pwd_customers = 0
     and (new.adult_rate > 0 or new.child_rate > 0 or new.senior_pwd_rate > 0) then
    raise exception 'Revenue records require at least one customer when rates are positive'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.prevent_unauthorized_revenue_void()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not public.has_app_role(array['Administrator'])
     and (
       new.status = 'Voided'
       or (new.status is distinct from old.status and old.status = 'Voided')
       or new.voided_by is distinct from old.voided_by
       or new.void_reason is distinct from old.void_reason
       or new.voided_at is distinct from old.voided_at
     ) then
    raise exception 'Only an Administrator may void revenue records'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_reservation_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  table_is_held boolean;
begin
  if tg_op = 'INSERT' then
    if new.type = 'Walk-in' then
      if new.status not in ('Pending', 'Seated') then
        raise exception 'Walk-ins may start only as Pending or Seated'
          using errcode = '23514';
      end if;
    elsif new.status <> 'Pending' then
      raise exception 'Reservations must start as Pending'
        using errcode = '23514';
    end if;
  elsif new.status is distinct from old.status then
    if not (
      (old.status = 'Pending' and new.status in ('Confirmed', 'Cancelled', 'No-show'))
      or (old.status = 'Confirmed' and new.status in ('Seated', 'Cancelled', 'No-show'))
      or (old.status = 'Seated' and new.status = 'Completed')
    ) then
      raise exception 'Invalid reservation status transition from % to %',
        old.status, new.status using errcode = '23514';
    end if;
  end if;
  if new.status = 'Seated' then
    if coalesce(new.actual_covers, 0) <= 0 then
      raise exception 'actual_covers must be greater than zero when seated'
        using errcode = '23514';
    end if;
    if new.seated_at is null then
      new.seated_at := clock_timestamp();
    end if;
  end if;
  if new.status = 'Completed' and new.completed_at is null then
    new.completed_at := clock_timestamp();
  end if;
  if new.table_id is not null and new.status = 'Seated' then
    update public.restaurant_tables
    set status = 'Occupied', guest = new.name
    where id = new.table_id;
  elsif new.table_id is not null
        and new.status in ('Completed', 'Cancelled', 'No-show') then
    select exists (
      select 1 from public.reservations as r
      where r.id <> new.id
        and r.table_id = new.table_id
        and r.reservation_date = new.reservation_date
        and r.reservation_time = new.reservation_time
        and r.status in ('Pending', 'Confirmed', 'Seated')
    ) into table_is_held;
    if table_is_held then
      update public.restaurant_tables set status = 'Reserved'
      where id = new.table_id;
    else
      update public.restaurant_tables
      set status = 'Available', guest = ''
      where id = new.table_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists validate_revenue_record on public.revenue_records;
create trigger validate_revenue_record
  before insert or update on public.revenue_records
  for each row execute function public.validate_revenue_record();
drop trigger if exists prevent_unauthorized_revenue_void on public.revenue_records;
create trigger prevent_unauthorized_revenue_void
  before update on public.revenue_records
  for each row execute function public.prevent_unauthorized_revenue_void();
drop trigger if exists enforce_reservation_lifecycle on public.reservations;
create trigger enforce_reservation_lifecycle
  before insert or update on public.reservations
  for each row execute function public.enforce_reservation_lifecycle();

-- PHASE 3: public reservation validation with contact/IP rate limits.
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
  contact_key_value text;
  ip_value text;
  contact_attempts integer;
  ip_attempts integer;
  contact_limit constant integer := 3;
  contact_window constant interval := interval '10 minutes';
  ip_limit constant integer := 10;
  ip_window constant interval := interval '1 hour';
begin
  if payload is null or jsonb_typeof(payload) is distinct from 'object' then
    raise exception 'Reservation payload must be a JSON object';
  end if;
  if nullif(btrim(payload ->> 'website'), '') is not null then
    raise exception 'Unable to process reservation request';
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
  if reservation_day is null or reservation_day < current_date then
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
  contact_key_value := md5(coalesce(
    nullif(regexp_replace(reservation_phone, '[^0-9]', '', 'g'), ''),
    lower(reservation_email)
  ));
  ip_value := coalesce(
    nullif(split_part(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
        ->> 'x-forwarded-for', ',', 1), ''),
    nullif(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
        ->> 'x-real-ip', ''), 'unknown');
  delete from public.public_reservation_attempts
  where created_at < clock_timestamp() - ip_window;
  select count(*) into contact_attempts
  from public.public_reservation_attempts
  where contact_key = contact_key_value
    and created_at >= clock_timestamp() - contact_window;
  select count(*) into ip_attempts
  from public.public_reservation_attempts
  where ip = ip_value
    and created_at >= clock_timestamp() - ip_window;
  if contact_attempts >= contact_limit or ip_attempts >= ip_limit then
    raise exception 'Unable to process reservation request';
  end if;
  insert into public.public_reservation_attempts (contact_key, ip)
  values (contact_key_value, ip_value);
  new_reference := 'RSV-' || upper(replace(gen_random_uuid()::text, '-', ''));
  begin
    insert into public.reservations (
      id, name, email, phone, reservation_date, reservation_time,
      guests, type, adults, children, occasion, status, preference, request, created_by
    ) values (
      new_reference, reservation_name, reservation_email, reservation_phone,
      reservation_day, reservation_time_value, guest_count, 'Reservation',
      adult_count, child_count, occasion_value, 'Pending',
      preference_value, request_value, auth.uid()
    );
  exception when unique_violation then
    raise exception 'Reservation reference or table/time slot is already in use'
      using errcode = '23P01';
  end;
  return new_reference;
end;
$$;

-- PHASE 3: revenue draft and confirmation RPCs.
create or replace function public.create_revenue_draft(reservation_id_value text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  reservation_row public.reservations%rowtype;
  rate_row public.buffet_rates%rowtype;
  revenue_id_value text;
  day_type_value text;
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Receptionist']) then
    raise exception 'Not authorized to create revenue drafts' using errcode = '42501';
  end if;
  if nullif(btrim(reservation_id_value), '') is null then
    raise exception 'A reservation id is required';
  end if;
  perform pg_advisory_xact_lock(hashtext(reservation_id_value));
  select * into reservation_row from public.reservations
  where id = btrim(reservation_id_value);
  if not found then raise exception 'Reservation not found'; end if;
  if reservation_row.status <> 'Seated' then
    raise exception 'Revenue drafts require a Seated reservation';
  end if;
  if coalesce(reservation_row.actual_covers, 0) <= 0 then
    raise exception 'A Seated reservation must have actual_covers greater than zero';
  end if;
  select id into revenue_id_value
  from public.revenue_records
  where reservation_id = reservation_row.id and status = 'Draft'
  order by recorded_at limit 1;
  if revenue_id_value is not null then
    return jsonb_build_object('id', revenue_id_value, 'status', 'Draft');
  end if;
  day_type_value := case
    when extract(isodow from reservation_row.reservation_date) between 1 and 5
      then 'weekday' else 'weekend' end;
  select * into rate_row from public.buffet_rates
  where meal_period = 'All Day' and day_type = day_type_value and is_active
    and effective_from <= reservation_row.reservation_date
    and (effective_to is null or effective_to >= reservation_row.reservation_date)
  order by effective_from desc limit 1;
  if not found then
    raise exception 'No active buffet rate exists for All Day/% on %',
      day_type_value, reservation_row.reservation_date;
  end if;
  revenue_id_value := 'REV-' || upper(replace(gen_random_uuid()::text, '-', ''));
  insert into public.revenue_records (
    id, business_date, meal_period, adult_customers, adult_rate,
    child_customers, child_rate, senior_pwd_customers, senior_pwd_rate,
    status, reservation_id, rate_id, recorded_by
  ) values (
    revenue_id_value, reservation_row.reservation_date, 'All Day',
    reservation_row.adults, rate_row.adult_rate,
    reservation_row.children, rate_row.child_rate, 0, rate_row.senior_pwd_rate,
    'Draft', reservation_row.id, rate_row.id, coalesce(auth.uid()::text, '')
  );
  return jsonb_build_object('id', revenue_id_value, 'status', 'Draft');
end;
$$;

create or replace function public.confirm_revenue(
  revenue_id_value text, adjustments jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  adult_count_value integer;
  child_count_value integer;
  senior_count_value integer;
begin
  if not public.has_app_role(array['Administrator', 'Manager']) then
    raise exception 'Not authorized to confirm revenue' using errcode = '42501';
  end if;
  if adjustments is null or jsonb_typeof(adjustments) is distinct from 'object' then
    raise exception 'Revenue adjustments must be a JSON object';
  end if;
  select adult_customers, child_customers, senior_pwd_customers
  into adult_count_value, child_count_value, senior_count_value
  from public.revenue_records
  where id = btrim(revenue_id_value) and status = 'Draft'
  for update;
  if not found then raise exception 'Draft revenue record not found'; end if;
  if adjustments ? 'adult_customers' then
    adult_count_value := (adjustments ->> 'adult_customers')::integer;
  end if;
  if adjustments ? 'child_customers' then
    child_count_value := (adjustments ->> 'child_customers')::integer;
  end if;
  if adjustments ? 'senior_pwd_customers' then
    senior_count_value := (adjustments ->> 'senior_pwd_customers')::integer;
  end if;
  if adult_count_value < 0 or child_count_value < 0 or senior_count_value < 0 then
    raise exception 'Customer counts must be non-negative';
  end if;
  update public.revenue_records
  set adult_customers = adult_count_value,
      child_customers = child_count_value,
      senior_pwd_customers = senior_count_value,
      status = 'Confirmed',
      last_edited_by = coalesce(auth.uid()::text, ''),
      last_edited_at = clock_timestamp(),
      edit_reason = 'Confirmed revenue draft'
  where id = btrim(revenue_id_value);
  return jsonb_build_object('id', btrim(revenue_id_value), 'status', 'Confirmed');
end;
$$;

-- PHASE 3: functions are callable only through their intended grants.
revoke all on function public.create_revenue_draft(text) from public, anon;
grant execute on function public.create_revenue_draft(text) to authenticated;
revoke all on function public.confirm_revenue(text, jsonb) from public, anon;
grant execute on function public.confirm_revenue(text, jsonb) to authenticated;

commit;

-- Verification examples:
-- Receiving: insert a Receiving transaction with unit_cost > 0 and verify
-- ingredients.cost equals it; insert Adjustment/Waste and verify cost unchanged.
-- Lifecycle: as Receptionist, Pending -> Confirmed -> Seated with actual_covers
-- > 0; verify timestamps/table status; attempt Seated -> Pending and expect denial.
-- Draft: as Receptionist call create_revenue_draft('RSV-...') twice; both calls
-- return the same id/status and never expose amounts.
-- Confirm: as Manager call confirm_revenue('REV-...', '{}'::jsonb); as
-- Receptionist call it and expect an authorization error.
-- Void: as Manager update status='Voided' and expect denial; as Administrator
-- perform the same update and expect success.
-- Rate limit: submit four valid public requests with the same contact in ten
-- minutes and expect the fourth to return the generic error.
