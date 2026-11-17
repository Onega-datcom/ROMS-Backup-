-- Phase B/C: atomic Walk-in seating and bill creation, plus billing safeguards.
-- Run after 012_reservation_guest_count_constraint.sql.

begin;

create table if not exists public.pos_walkin_bill_requests (
  idempotency_key text not null,
  cashier_id uuid not null,
  reservation_id text not null references public.reservations(id) on delete restrict,
  bill_id text not null references public.pos_bills(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (cashier_id, idempotency_key),
  unique (reservation_id),
  unique (bill_id)
);
alter table public.pos_walkin_bill_requests enable row level security;
revoke all on public.pos_walkin_bill_requests from public, anon, authenticated;

create table if not exists public.pos_walkin_package_overrides (
  id bigint generated always as identity primary key,
  reservation_id text not null references public.reservations(id) on delete restrict,
  package_charge_item_id text not null references public.pos_charge_items(id) on delete restrict,
  package_tier_id text not null references public.pos_package_tiers(id) on delete restrict,
  package_pax_count integer not null check (package_pax_count > 0),
  overridden_by uuid not null,
  reason text not null check (length(btrim(reason)) between 10 and 500),
  created_at timestamptz not null default now()
);
do $$
begin
  if exists (
    select 1
    from public.reservations r
    where r.type = 'Walk-in'
      and r.package_charge_item_id is not null
      and not exists (
        select 1
        from public.pos_walkin_package_overrides o
        where o.reservation_id = r.id
          and o.package_charge_item_id = r.package_charge_item_id
          and o.package_tier_id = r.package_tier_id
          and o.package_pax_count = r.package_pax_count
      )
  ) then
    raise exception 'Migration 013 stopped: existing Walk-in package bookings have no Manager/Administrator override audit. Review them before rerunning; no rows were changed.'
      using errcode = '55000';
  end if;
end;
$$;
create index if not exists pos_walkin_package_overrides_reservation_idx
  on public.pos_walkin_package_overrides (reservation_id, created_at desc);
alter table public.pos_walkin_package_overrides enable row level security;
drop policy if exists pos_walkin_package_overrides_manager_admin_select
  on public.pos_walkin_package_overrides;
create policy pos_walkin_package_overrides_manager_admin_select
  on public.pos_walkin_package_overrides for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));
revoke all on public.pos_walkin_package_overrides from public, anon, authenticated;
grant select on public.pos_walkin_package_overrides to authenticated;

alter table public.reservations
  add column if not exists package_override_reason text not null default '';

create or replace function public.guard_walkin_reservation_package()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  package_changed boolean;
  walkin_related boolean;
  override_reason text;
begin
  if tg_op = 'INSERT' then
    package_changed := new.package_charge_item_id is not null
      or new.package_tier_id is not null
      or new.package_pax_count is not null;
    walkin_related := new.type = 'Walk-in';
  else
    package_changed := row(new.package_charge_item_id, new.package_tier_id, new.package_pax_count)
      is distinct from row(old.package_charge_item_id, old.package_tier_id, old.package_pax_count)
      or (
        new.type is distinct from old.type
        and (new.package_charge_item_id is not null or old.package_charge_item_id is not null)
      );
    walkin_related := new.type = 'Walk-in' or old.type = 'Walk-in';
  end if;

  if package_changed and walkin_related then
    if auth.uid() is null
      or not public.has_app_role(array['Administrator', 'Manager']) then
      raise exception 'Walk-ins cannot have event packages without a Manager or Administrator override.'
        using errcode = '42501';
    end if;
    if new.type = 'Walk-in' and new.package_charge_item_id is not null then
      override_reason := btrim(coalesce(new.package_override_reason, ''));
      if length(override_reason) not between 10 and 500 then
        raise exception 'A package override reason between 10 and 500 characters is required.'
          using errcode = '22023';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.audit_walkin_reservation_package_override()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  package_changed boolean;
begin
  if tg_op = 'INSERT' then
    package_changed := true;
  else
    package_changed := new.type is distinct from old.type
      or row(new.package_charge_item_id, new.package_tier_id, new.package_pax_count)
        is distinct from row(old.package_charge_item_id, old.package_tier_id, old.package_pax_count);
  end if;

  if new.type = 'Walk-in'
    and new.package_charge_item_id is not null
    and package_changed then
    insert into public.pos_walkin_package_overrides (
      reservation_id, package_charge_item_id, package_tier_id,
      package_pax_count, overridden_by, reason
    ) values (
      new.id, new.package_charge_item_id, new.package_tier_id,
      new.package_pax_count, auth.uid(), btrim(new.package_override_reason)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists guard_walkin_reservation_package on public.reservations;
create trigger guard_walkin_reservation_package
  before insert or update on public.reservations
  for each row execute function public.guard_walkin_reservation_package();
drop trigger if exists audit_walkin_reservation_package_override on public.reservations;
create trigger audit_walkin_reservation_package_override
  after insert or update on public.reservations
  for each row execute function public.audit_walkin_reservation_package_override();

create or replace function public.guard_walkin_bill_package_line()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  reservation_row public.reservations%rowtype;
  reservation_id_value text;
begin
  if new.line_type <> 'package' or new.is_voided then
    return new;
  end if;

  select b.reservation_id into reservation_id_value
  from public.pos_bills b where b.id = new.bill_id;
  if reservation_id_value is null then
    raise exception 'Package lines require a reservation with an approved package booking.'
      using errcode = '42501';
  end if;

  select * into reservation_row
  from public.reservations r where r.id = reservation_id_value;
  if reservation_row.type = 'Walk-in'
    and (
      reservation_row.package_charge_item_id is distinct from new.charge_item_id
      or reservation_row.package_tier_id is distinct from new.package_tier_id
      or not exists (
      select 1
      from public.pos_walkin_package_overrides o
      where o.reservation_id = reservation_row.id
        and o.package_charge_item_id = new.charge_item_id
        and o.package_tier_id = new.package_tier_id
      )
    ) then
    raise exception 'A package line on a Walk-in requires a Manager or Administrator override with a recorded reason.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_walkin_bill_package_line on public.pos_bill_lines;
create trigger guard_walkin_bill_package_line
  before insert or update of bill_id, charge_item_id, package_tier_id, line_type, is_voided
  on public.pos_bill_lines
  for each row execute function public.guard_walkin_bill_package_line();

create or replace function public.pos_seat_and_open_walkin(
  p_customer_name text,
  p_phone text,
  p_email text,
  p_reservation_date date,
  p_reservation_time text,
  p_table_id text,
  p_adult_count integer,
  p_senior_count integer,
  p_kids_count integer,
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
  table_row public.restaurant_tables%rowtype;
  reservation_row public.reservations%rowtype;
  bill_result jsonb;
  bill_row public.pos_bills%rowtype;
  existing_request public.pos_walkin_bill_requests%rowtype;
  total_covers bigint;
  reservation_id_value text;
  bill_id_value text;
  bill_key text;
  customer_name_value text;
begin
  if auth.uid() is null
    or not public.has_app_role(array['Administrator', 'Manager', 'Receptionist']) then
    raise exception 'Your role cannot seat Walk-ins or create POS bills.'
      using errcode = '42501';
  end if;
  if p_idempotency_key is null
    or length(btrim(p_idempotency_key)) = 0
    or length(p_idempotency_key) > 150 then
    raise exception 'A valid Walk-in idempotency key is required.'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || ':' || p_idempotency_key, 0));
  select * into existing_request
  from public.pos_walkin_bill_requests
  where cashier_id = auth.uid() and idempotency_key = p_idempotency_key;
  if found then
    select * into reservation_row
    from public.reservations where id = existing_request.reservation_id;
    select * into bill_row
    from public.pos_bills where id = existing_request.bill_id;
    if not found or reservation_row.id is null then
      raise exception 'The previous Walk-in request exists but its reservation or bill is missing.'
        using errcode = '55000';
    end if;
    return jsonb_build_object(
      'reservation', to_jsonb(reservation_row),
      'bill', to_jsonb(bill_row),
      'lines', coalesce((
        select jsonb_agg(to_jsonb(line_row) order by line_row.created_at)
        from public.pos_bill_lines line_row where line_row.bill_id = bill_row.id
      ), '[]'::jsonb),
      'already_created', true
    );
  end if;

  if p_adult_count is null or p_senior_count is null or p_kids_count is null
    or p_adult_count < 0 or p_senior_count < 0 or p_kids_count < 0 then
    raise exception 'Walk-in counts must be non-negative whole numbers.'
      using errcode = '22023';
  end if;
  total_covers := p_adult_count::bigint + p_senior_count::bigint + p_kids_count::bigint;
  if total_covers < 1 or total_covers > 1000 then
    raise exception 'A Walk-in must include between 1 and 1,000 guests.'
      using errcode = '22023';
  end if;
  customer_name_value := coalesce(nullif(btrim(p_customer_name), ''), 'Walk-in guest');
  if length(customer_name_value) > 160 or length(coalesce(p_notes, '')) > 2000 then
    raise exception 'Walk-in guest name or notes exceed the allowed length.'
      using errcode = '22023';
  end if;
  if nullif(btrim(p_email), '') is not null
    and (length(p_email) > 254
      or p_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$') then
    raise exception 'Enter a valid email address.'
      using errcode = '22023';
  end if;
  if nullif(btrim(p_phone), '') is not null
    and (length(p_phone) > 40
      or length(regexp_replace(p_phone, '[^0-9]', '', 'g')) not between 7 and 15) then
    raise exception 'Enter a valid phone number.'
      using errcode = '22023';
  end if;
  if p_reservation_date is null
    or p_reservation_date not between current_date - 1 and current_date + 1
    or not public.reservation_time_within_open_hours(p_reservation_time) then
    raise exception 'Walk-ins must be seated within the current date and the restaurant two-hour seating hours.'
      using errcode = '23514';
  end if;
  if nullif(btrim(p_table_id), '') is null then
    raise exception 'Choose a table for the Walk-in.'
      using errcode = '22023';
  end if;

  select * into shift_row from public.pos_shifts
  where opened_by = auth.uid() and status = 'Open'
  for update;
  if not found then
    raise exception 'Open your cashier shift before seating a Walk-in and opening its bill.'
      using errcode = '55000';
  end if;
  select * into table_row from public.restaurant_tables
  where id = p_table_id for update;
  if not found then
    raise exception 'The selected table does not exist.'
      using errcode = '23503';
  end if;
  if table_row.status = 'Needs cleaning' then
    raise exception 'The selected table needs cleaning before it can be used.'
      using errcode = '55000';
  end if;
  if total_covers > table_row.seats then
    raise exception 'The selected table does not have enough seats for this Walk-in.'
      using errcode = '23514';
  end if;

  reservation_id_value := 'WI-' || gen_random_uuid()::text;
  insert into public.reservations (
    id, name, email, phone, reservation_date, reservation_time, guests,
    type, adults, senior_pwd_count, children, status, seated_at,
    actual_covers, table_id, source, request, created_by
  ) values (
    reservation_id_value, customer_name_value, nullif(btrim(p_email), ''),
    nullif(btrim(p_phone), ''), p_reservation_date, p_reservation_time,
    total_covers::integer, 'Walk-in', p_adult_count, p_senior_count, p_kids_count,
    'Seated', clock_timestamp(), total_covers::integer, p_table_id,
    'Walk-in', coalesce(p_notes, ''), auth.uid()
  ) returning * into reservation_row;

  bill_key := 'WALKIN:' || auth.uid()::text || ':' || p_idempotency_key;
  bill_result := public.pos_save_bill_phase3(
    p_bill_id => null,
    p_customer_name => customer_name_value,
    p_notes => coalesce(p_notes, ''),
    p_reservation_id => reservation_row.id,
    p_adult_count => p_adult_count,
    p_senior_count => p_senior_count,
    p_kids_count => p_kids_count,
    p_comped_count => 0,
    p_discount_id => null,
    p_discount_reason => '',
    p_extra_lines => '[]'::jsonb,
    p_idempotency_key => bill_key,
    p_table_id => p_table_id,
    p_charge_extra_pax => false
  );
  bill_id_value := bill_result->'bill'->>'id';
  if bill_id_value is null then
    raise exception 'The bill service did not return the new Walk-in bill.'
      using errcode = '55000';
  end if;

  insert into public.pos_walkin_bill_requests (
    cashier_id, idempotency_key, reservation_id, bill_id
  ) values (
    auth.uid(), p_idempotency_key, reservation_row.id, bill_id_value
  );
  select * into bill_row from public.pos_bills where id = bill_id_value;

  return jsonb_build_object(
    'reservation', to_jsonb(reservation_row),
    'bill', to_jsonb(bill_row),
    'lines', coalesce(bill_result->'lines', '[]'::jsonb),
    'already_created', false
  );
end;
$$;

revoke all on function public.guard_walkin_reservation_package() from public, anon, authenticated;
revoke all on function public.audit_walkin_reservation_package_override() from public, anon, authenticated;
revoke all on function public.guard_walkin_bill_package_line() from public, anon, authenticated;
revoke all on function public.pos_seat_and_open_walkin(text, text, text, date, text, text, integer, integer, integer, text, text)
  from public, anon;
grant execute on function public.pos_seat_and_open_walkin(text, text, text, date, text, text, integer, integer, integer, text, text)
  to authenticated;

commit;
