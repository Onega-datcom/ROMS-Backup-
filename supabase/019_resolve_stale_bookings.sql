-- Phase D1: audited, atomic resolution of past reservations and Walk-ins.
-- Run after 018_restore_stale_walkin_history_guard.sql.

begin;

create or replace function public.pos_business_date()
returns date
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select timezone('Asia/Manila', statement_timestamp())::date;
$$;

revoke all on function public.pos_business_date() from public, anon, authenticated;

create or replace function public.public_create_reservation(payload jsonb)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
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
  if reservation_day is null or reservation_day < public.pos_business_date() then
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
    or p_reservation_date not between public.pos_business_date() - 1
      and public.pos_business_date() + 1
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

create or replace function public.enforce_reservation_date()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is not null
     and public.has_app_role(array['Administrator', 'Manager', 'Receptionist'])
     and new.reservation_date < public.pos_business_date()
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

create or replace function public.prevent_historical_reservation_phase_a_changes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if old.reservation_date < public.pos_business_date()
     and (new.senior_pwd_count is distinct from old.senior_pwd_count
       or new.source is distinct from old.source) then
    raise exception 'Historical corrections cannot change Senior/PWD count or reservation source'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_restaurant_table_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'Table identifiers cannot be changed after creation'
      using errcode = '23514';
  end if;
  if new.seats is distinct from old.seats
     and exists (
       select 1
       from public.reservations
       where table_id = old.id
         and reservation_date >= public.pos_business_date()
         and status in ('Pending', 'Confirmed', 'Seated')
         and coalesce(actual_covers, guests) > new.seats
     ) then
    raise exception 'Table capacity cannot be reduced below an assigned active party'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_reservation_table_overlap()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  new_start integer;
begin
  if new.table_id is null or new.status not in ('Pending', 'Confirmed', 'Seated') then
    return new;
  end if;

  if not public.reservation_time_within_open_hours(new.reservation_time) then
    raise exception 'The two-hour reservation window must fit between 10:00 AM and 9:00 PM'
      using errcode = '23514';
  end if;
  new_start := public.reservation_time_to_minutes(new.reservation_time);

  perform pg_advisory_xact_lock(hashtext(new.table_id), hashtext(new.reservation_date::text));

  if exists (
    select 1
    from public.reservations existing
    where existing.table_id = new.table_id
      and existing.id <> new.id
      and existing.status in ('Pending', 'Confirmed', 'Seated')
      and (
        (existing.status = 'Seated'
          and existing.reservation_date < new.reservation_date
          and new.reservation_date = public.pos_business_date())
        or (
          existing.reservation_date = new.reservation_date
          and new_start < public.reservation_time_to_minutes(existing.reservation_time) + 120
          and public.reservation_time_to_minutes(existing.reservation_time) < new_start + 120
        )
      )
  ) then
    raise exception 'The selected table already has an overlapping two-hour reservation'
      using errcode = '23505';
  end if;

  return new;
end;
$$;

create or replace function public.enforce_reservation_start_not_past()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  business_now timestamp without time zone :=
    timezone('Asia/Manila', statement_timestamp());
  now_minutes numeric;
  start_minutes integer;
  schedule_changed boolean;
begin
  if new.type = 'Walk-in' then
    return new;
  end if;

  schedule_changed := tg_op = 'INSERT'
    or new.reservation_date is distinct from old.reservation_date
    or new.reservation_time is distinct from old.reservation_time
    or new.type is distinct from old.type;

  if schedule_changed and new.reservation_date = public.pos_business_date() then
    start_minutes := public.reservation_time_to_minutes(new.reservation_time);
    now_minutes :=
      extract(hour from business_now) * 60
      + extract(minute from business_now)
      + extract(second from business_now) / 60;

    if start_minutes is not null and start_minutes < now_minutes then
      raise exception 'Reservation start time has already passed'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_reservation_date()
  from public, anon, authenticated;
revoke all on function public.prevent_historical_reservation_phase_a_changes()
  from public, anon, authenticated;
revoke all on function public.enforce_restaurant_table_update()
  from public, anon, authenticated;
revoke all on function public.enforce_reservation_table_overlap()
  from public, anon, authenticated;
revoke all on function public.enforce_reservation_start_not_past()
  from public, anon, authenticated;

create table if not exists public.pos_stale_booking_resolutions (
  id text primary key default gen_random_uuid()::text,
  reservation_id text not null references public.reservations(id) on delete restrict,
  idempotency_key text not null unique,
  actor_id uuid not null references auth.users(id) on delete restrict,
  prior_status text not null check (prior_status in ('Seated', 'Pending', 'Confirmed')),
  outcome text not null check (outcome in ('close_without_charge', 'no_show', 'cancel')),
  resolution_status text not null check (resolution_status in ('Completed', 'No-show', 'Cancelled')),
  resolution_reason text not null check (length(btrim(resolution_reason)) between 10 and 500),
  confirmed_no_meal boolean not null default false,
  deposit_action text check (deposit_action is null or deposit_action in ('refund', 'forfeit')),
  deposit_action_reason text not null default '',
  deposit_total numeric(12,2) not null default 0 check (deposit_total >= 0),
  deposit_ids text[] not null default '{}'::text[],
  bill_ids text[] not null default '{}'::text[],
  cash_movement_ids text[] not null default '{}'::text[],
  table_id text,
  created_at timestamptz not null default clock_timestamp(),
  constraint pos_stale_booking_resolution_shape_check check (
    (outcome = 'close_without_charge'
      and prior_status = 'Seated'
      and resolution_status = 'Completed'
      and confirmed_no_meal)
    or (outcome = 'no_show'
      and prior_status in ('Pending', 'Confirmed')
      and resolution_status = 'No-show'
      and not confirmed_no_meal)
    or (outcome = 'cancel'
      and prior_status in ('Pending', 'Confirmed')
      and resolution_status = 'Cancelled'
      and not confirmed_no_meal)
  ),
  constraint pos_stale_booking_one_resolution_uidx unique (reservation_id)
);
comment on table public.pos_stale_booking_resolutions is
  'Append-only audit of manual stale-booking resolutions; retained by the 019 rollback to preserve history.';

create index if not exists pos_stale_booking_resolutions_actor_idx
  on public.pos_stale_booking_resolutions (actor_id, created_at desc);

alter table public.pos_stale_booking_resolutions enable row level security;
revoke all on public.pos_stale_booking_resolutions from public, anon, authenticated;
grant select on public.pos_stale_booking_resolutions to authenticated;

drop policy if exists pos_stale_booking_resolutions_role_read
  on public.pos_stale_booking_resolutions;
create policy pos_stale_booking_resolutions_role_read
  on public.pos_stale_booking_resolutions
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));

create or replace function public.prevent_stale_booking_resolution_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'Stale booking resolution records are append-only.'
    using errcode = '42501';
end;
$$;

drop trigger if exists prevent_stale_booking_resolution_mutation
  on public.pos_stale_booking_resolutions;
create trigger prevent_stale_booking_resolution_mutation
  before update or delete on public.pos_stale_booking_resolutions
  for each row execute function public.prevent_stale_booking_resolution_mutation();

revoke all on function public.prevent_stale_booking_resolution_mutation()
  from public, anon, authenticated;

create or replace function public.stale_booking_resolution_is_allowed(
  p_reservation_id text,
  p_new_status text,
  p_reason text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select auth.uid() is not null
    and public.has_app_role(array['Administrator', 'Manager'])
    and current_setting('costtrack.stale_booking_resolution_id', true)
      is not distinct from p_reservation_id
    and length(btrim(coalesce(p_reason, ''))) between 10 and 500
    and exists (
      select 1
      from public.reservations r
      join public.pos_stale_booking_resolutions x
        on x.reservation_id = r.id
      where r.id = p_reservation_id
        and r.reservation_date < public.pos_business_date()
        and x.actor_id = auth.uid()
        and x.resolution_reason = btrim(p_reason)
        and x.resolution_status = p_new_status
        and (
          (x.outcome = 'close_without_charge'
            and r.status = 'Seated'
            and not exists (
              select 1 from public.pos_bills b
              where b.reservation_id = r.id
            )
            and not exists (
              select 1 from public.pos_reservation_deposits d
              where d.reservation_id = r.id and d.status = 'Held'
            ))
          or (x.outcome = 'no_show'
            and r.status in ('Pending', 'Confirmed'))
          or (x.outcome = 'cancel'
            and r.status in ('Pending', 'Confirmed'))
        )
    );
$$;

revoke all on function public.stale_booking_resolution_is_allowed(text, text, text)
  from public, anon, authenticated;

create or replace function public.stale_walkin_completion_is_allowed(
  p_reservation_id text,
  p_reason text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select false;
$$;

revoke all on function public.stale_walkin_completion_is_allowed(text, text)
  from public, anon, authenticated;

create or replace function public.require_settled_pos_bill_for_reservation_completion()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if old.status = 'Seated'
     and new.status = 'Completed'
     and not exists (
       select 1
       from public.pos_bills b
       where b.reservation_id = new.id
         and b.status = 'Closed'
         and b.balance_due = 0
     )
     and not public.stale_walkin_completion_is_allowed(
       old.id, new.last_correction_reason
     )
     and not public.stale_booking_resolution_is_allowed(
       old.id, new.status, new.last_correction_reason
     ) then
    raise exception 'A reservation can be completed only when its linked POS bill is closed and fully settled, or by the audited stale-booking resolver.'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_reservation_history_guard()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' then
    if old.reservation_date < public.pos_business_date() then
      raise exception 'Past reservations cannot be deleted'
        using errcode = '42501';
    end if;
    return old;
  end if;

  if tg_op = 'INSERT' then
    if btrim(coalesce(new.last_correction_reason, '')) <> '' then
      raise exception 'A correction reason can only be recorded when correcting a past reservation'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.created_by is distinct from old.created_by
       or new.created_at is distinct from old.created_at then
      raise exception 'Reservation identity and creation details cannot be changed'
        using errcode = '42501';
    end if;

    if old.reservation_date < public.pos_business_date() then
      if old.status = 'Seated'
         and new.status = 'Completed'
         and new.completed_at is not null
         and new.last_correction_reason is distinct from old.last_correction_reason
         and (to_jsonb(new) - array[
           'status', 'completed_at', 'last_correction_reason', 'updated_at'
         ]) is not distinct from
           (to_jsonb(old) - array[
             'status', 'completed_at', 'last_correction_reason', 'updated_at'
           ])
         and public.stale_walkin_completion_is_allowed(
           old.id, new.last_correction_reason
         ) then
        return new;
      end if;

      if old.status = 'Seated'
         and new.status = 'Completed'
         and new.completed_at is not null
         and new.last_correction_reason is distinct from old.last_correction_reason
         and (to_jsonb(new) - array[
           'status', 'completed_at', 'last_correction_reason', 'updated_at'
         ]) is not distinct from
           (to_jsonb(old) - array[
             'status', 'completed_at', 'last_correction_reason', 'updated_at'
           ])
         and public.stale_booking_resolution_is_allowed(
           old.id, new.status, new.last_correction_reason
         ) then
        return new;
      end if;

      if old.status in ('Pending', 'Confirmed')
         and new.status in ('No-show', 'Cancelled')
         and new.last_correction_reason is distinct from old.last_correction_reason
         and (to_jsonb(new) - array[
           'status', 'last_correction_reason', 'updated_at'
         ]) is not distinct from
           (to_jsonb(old) - array[
             'status', 'last_correction_reason', 'updated_at'
           ])
         and public.stale_booking_resolution_is_allowed(
           old.id, new.status, new.last_correction_reason
         ) then
        return new;
      end if;

      if old.status = 'Seated'
         and new.status = 'Completed'
         and new.completed_at is not null
         and public.has_app_role(array['Administrator', 'Manager', 'Receptionist'])
         and (to_jsonb(new) - array[
           'status', 'completed_at', 'actual_covers', 'updated_at'
         ]) is not distinct from
           (to_jsonb(old) - array[
             'status', 'completed_at', 'actual_covers', 'updated_at'
           ])
         and exists (
           select 1
           from public.pos_bills b
           where b.id = current_setting('costtrack.pos_bill_close_id', true)
             and b.reservation_id = old.id
             and b.status = 'Closed'
             and b.balance_due = 0
             and b.closed_by = auth.uid()
             and new.actual_covers = b.adult_count + b.senior_count
               + b.kids_count + b.comped_count
         ) then
        return new;
      end if;

      if not public.has_app_role(array['Administrator', 'Manager']) then
        raise exception 'Past reservations are read-only for this role'
          using errcode = '42501';
      end if;

      if row(
        new.reservation_date, new.reservation_time, new.guests, new.type,
        new.adults, new.children, new.status, new.seated_at,
        new.completed_at, new.actual_covers, new.table_id
      ) is distinct from row(
        old.reservation_date, old.reservation_time, old.guests, old.type,
        old.adults, old.children, old.status, old.seated_at,
        old.completed_at, old.actual_covers, old.table_id
      ) then
        raise exception 'Historical corrections cannot change booking date, time, party size, table, or status'
          using errcode = '42501';
      end if;

      if length(btrim(coalesce(new.last_correction_reason, ''))) not between 10 and 500 then
        raise exception 'A correction reason between 10 and 500 characters is required'
          using errcode = '23514';
      end if;
      if btrim(new.last_correction_reason) is not distinct from btrim(coalesce(old.last_correction_reason, '')) then
        raise exception 'Enter a new reason for each historical correction'
          using errcode = '23514';
      end if;
      if row(new.name, new.email, new.phone, new.occasion, new.preference, new.request)
         is not distinct from row(old.name, old.email, old.phone, old.occasion, old.preference, old.request) then
        raise exception 'A historical correction must change a guest detail or note'
          using errcode = '23514';
      end if;
      if new.name is distinct from old.name
         and (nullif(btrim(new.name), '') is null or length(new.name) > 160) then
        raise exception 'A valid reservation name is required'
          using errcode = '23514';
      end if;
      if new.email is distinct from old.email
         and nullif(btrim(new.email), '') is not null
         and (length(new.email) > 254
           or new.email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$') then
        raise exception 'A valid email address is required'
          using errcode = '23514';
      end if;
      if new.phone is distinct from old.phone
         and nullif(btrim(new.phone), '') is not null
         and (length(new.phone) > 40
           or length(regexp_replace(new.phone, '[^0-9]', '', 'g')) not between 7 and 15) then
        raise exception 'A valid phone number is required'
          using errcode = '23514';
      end if;
      if (new.occasion is distinct from old.occasion and length(new.occasion) > 120)
         or (new.preference is distinct from old.preference and length(new.preference) > 500)
         or (new.request is distinct from old.request and length(new.request) > 2000) then
        raise exception 'Reservation details exceed the allowed length'
          using errcode = '23514';
      end if;
      new.last_correction_reason := btrim(new.last_correction_reason);
    elsif new.last_correction_reason is distinct from old.last_correction_reason then
      raise exception 'Correction reasons may only be set for past reservation corrections'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.require_settled_pos_bill_for_reservation_completion()
  from public, anon, authenticated;
revoke all on function public.enforce_reservation_history_guard()
  from public, anon, authenticated;

create or replace function public.pos_list_unresolved_stale_bookings()
returns table (
  reservation_id text,
  name text,
  reservation_date date,
  reservation_time text,
  type text,
  table_id text,
  guests integer,
  reservation_status text,
  bill_status text,
  held_deposit_total numeric,
  age_days integer,
  resolution_label text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null
     or not public.has_app_role(array['Administrator', 'Manager', 'Receptionist']) then
    raise exception 'Your role cannot view unresolved stale bookings.'
      using errcode = '42501';
  end if;

  return query
  select r.id,
         r.name,
         r.reservation_date,
         r.reservation_time,
         r.type,
         r.table_id,
         r.guests,
         r.status,
         coalesce(b.bill_status, 'None'),
         coalesce(d.held_total, 0)::numeric,
         (public.pos_business_date() - r.reservation_date)::integer,
         case
           when r.status = 'Seated' and exists (
             select 1
             from public.pos_bills pb
             where pb.reservation_id = r.id
               and pb.status = 'Open'
           ) then 'Payable'
           else 'Unresolved'
         end
  from public.reservations r
  left join lateral (
    select string_agg(
      pb.status
        || case
          when pb.status = 'Closed' and pb.balance_due = 0 then ' (settled)'
          when pb.status = 'Open' then ' (open)'
          when pb.status <> 'Voided' and pb.balance_due > 0 then ' (balance due)'
          else ''
        end,
      ', ' order by pb.created_at, pb.id
    ) as bill_status
    from public.pos_bills pb
    where pb.reservation_id = r.id
  ) b on true
  left join lateral (
    select sum(pd.amount) as held_total
    from public.pos_reservation_deposits pd
    where pd.reservation_id = r.id
      and pd.status = 'Held'
  ) d on true
  where r.reservation_date < public.pos_business_date()
    and (
      r.status in ('Pending', 'Confirmed')
      or (
        r.status = 'Seated'
        and not exists (
          select 1
          from public.pos_bills pb
          where pb.reservation_id = r.id
            and pb.status = 'Closed'
            and pb.balance_due = 0
        )
      )
    )
  order by r.reservation_date, r.reservation_time, r.id;
end;
$$;

revoke all on function public.pos_list_unresolved_stale_bookings()
  from public, anon;
grant execute on function public.pos_list_unresolved_stale_bookings()
  to authenticated;

create or replace function public.pos_resolve_stale_booking(
  p_reservation_id text,
  p_outcome text,
  p_reason text,
  p_confirm_no_meal boolean,
  p_deposit_action text,
  p_deposit_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reservation_row public.reservations%rowtype;
  table_row public.restaurant_tables%rowtype;
  shift_row public.pos_shifts%rowtype;
  deposit_row public.pos_reservation_deposits%rowtype;
  resolution_row public.pos_stale_booking_resolutions%rowtype;
  outcome_value text := lower(btrim(coalesce(p_outcome, '')));
  deposit_action_value text := nullif(lower(btrim(coalesce(p_deposit_action, ''))), '');
  reason_value text := btrim(coalesce(p_reason, ''));
  deposit_reason_value text := btrim(coalesce(p_deposit_reason, ''));
  idempotency_key_value text := btrim(coalesce(p_idempotency_key, ''));
  business_date_value date;
  resolved_status_value text;
  held_count integer := 0;
  held_total_value numeric(12,2) := 0;
  deposit_ids_value text[] := '{}'::text[];
  bill_ids_value text[] := '{}'::text[];
  cash_movement_ids_value text[] := '{}'::text[];
  cash_movement_id_value text;
  movement_key_value text;
begin
  if auth.uid() is null
     or not public.has_app_role(array['Administrator', 'Manager']) then
    raise exception 'Only Managers and Administrators can resolve stale bookings.'
      using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_reservation_id, '')), '') is null then
    raise exception 'A reservation ID is required.' using errcode = '22023';
  end if;
  if outcome_value not in ('close_without_charge', 'no_show', 'cancel') then
    raise exception 'Choose Close without charge, No-show, or Cancelled.'
      using errcode = '22023';
  end if;
  if length(reason_value) not between 10 and 500 then
    raise exception 'Enter a resolution reason between 10 and 500 characters.'
      using errcode = '22023';
  end if;
  if outcome_value = 'close_without_charge'
     and p_confirm_no_meal is distinct from true then
    raise exception 'Confirm that no meal was served or the record is a test/error.'
      using errcode = '22023';
  end if;
  if outcome_value <> 'close_without_charge'
     and p_confirm_no_meal is distinct from false then
    raise exception 'The no-meal confirmation applies only to Close without charge.'
      using errcode = '22023';
  end if;
  if deposit_action_value is not null
     and deposit_action_value not in ('refund', 'forfeit') then
    raise exception 'Choose Refund or Forfeit for held deposits.'
      using errcode = '22023';
  end if;
  if length(idempotency_key_value) not between 1 and 150 then
    raise exception 'An idempotency key of 1 to 150 characters is required.'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(auth.uid()::text || ':' || idempotency_key_value, 0)
  );
  select x.* into resolution_row
  from public.pos_stale_booking_resolutions x
  where x.idempotency_key = idempotency_key_value;
  if found then
    if resolution_row.actor_id <> auth.uid()
       or resolution_row.reservation_id <> p_reservation_id
       or resolution_row.outcome <> outcome_value
       or resolution_row.resolution_reason <> reason_value
       or resolution_row.confirmed_no_meal <> coalesce(p_confirm_no_meal, false)
       or resolution_row.deposit_action is distinct from deposit_action_value
       or resolution_row.deposit_action_reason <> deposit_reason_value then
      raise exception 'This idempotency key was already used for a different resolution.'
        using errcode = '22023';
    end if;
    return jsonb_build_object(
      'resolution', to_jsonb(resolution_row),
      'reservation_id', resolution_row.reservation_id,
      'status', resolution_row.resolution_status,
      'already_resolved', true
    );
  end if;

  select r.* into reservation_row
  from public.reservations r
  where r.id = p_reservation_id
  for update;
  if not found then
    raise exception 'Reservation not found.' using errcode = 'P0002';
  end if;

  business_date_value := public.pos_business_date();
  if reservation_row.reservation_date >= business_date_value then
    raise exception 'Only bookings from a previous Asia/Manila business day can be resolved.'
      using errcode = '55000';
  end if;
  if reservation_row.type not in ('Reservation', 'Walk-in') then
    raise exception 'Only Reservation and Walk-in records can be resolved.'
      using errcode = '55000';
  end if;
  if exists (
    select 1
    from public.pos_stale_booking_resolutions x
    where x.reservation_id = reservation_row.id
  ) then
    raise exception 'This booking already has a recorded resolution.'
      using errcode = '55000';
  end if;

  if outcome_value = 'close_without_charge' then
    if reservation_row.status <> 'Seated' then
      raise exception 'Only a past Seated booking can be closed without charge.'
        using errcode = '55000';
    end if;
    resolved_status_value := 'Completed';
    if exists (
      select 1 from public.pos_bills b
      where b.reservation_id = reservation_row.id
    ) then
      raise exception 'A bill exists for this booking; use the normal cashier flow instead of Close without charge.'
        using errcode = '55000';
    end if;
  else
    if reservation_row.status not in ('Pending', 'Confirmed') then
      raise exception 'Only a past Pending or Confirmed booking can be marked No-show or Cancelled.'
        using errcode = '55000';
    end if;
    resolved_status_value := case
      when outcome_value = 'no_show' then 'No-show'
      else 'Cancelled'
    end;
    if exists (
      select 1 from public.pos_bills b
      where b.reservation_id = reservation_row.id
        and b.status <> 'Voided'
    ) then
      raise exception 'Resolve the linked bill before marking this booking No-show or Cancelled.'
        using errcode = '55000';
    end if;
  end if;

  if exists (
    select 1
    from public.pos_reservation_deposits d
    where d.reservation_id = reservation_row.id
      and d.status = 'Applied'
  ) then
    raise exception 'An applied deposit must be resolved through its linked bill first.'
      using errcode = '55000';
  end if;

  perform 1
  from public.pos_reservation_deposits d
  where d.reservation_id = reservation_row.id
    and d.status = 'Held'
  order by d.id
  for update;

  select count(*)::integer,
         coalesce(sum(d.amount), 0)::numeric(12,2),
         coalesce(array_agg(d.id order by d.id), '{}'::text[])
    into held_count, held_total_value, deposit_ids_value
  from public.pos_reservation_deposits d
  where d.reservation_id = reservation_row.id
    and d.status = 'Held';

  if exists (
    select 1
    from public.pos_reservation_deposits d
    where d.reservation_id = reservation_row.id
      and d.status = 'Held'
      and (d.bill_id is not null or d.amount <= 0)
  ) then
    raise exception 'A held deposit is linked to a bill or has an invalid amount; resolve it manually before continuing.'
      using errcode = '55000';
  end if;
  if held_count > 0 and deposit_action_value is null then
    raise exception 'Choose Refund or Forfeit for every held deposit.'
      using errcode = '55000';
  end if;
  if held_count = 0 and deposit_action_value is not null then
    raise exception 'A deposit action was supplied but this booking has no held deposits.'
      using errcode = '22023';
  end if;
  if held_count = 0 and deposit_reason_value <> '' then
    raise exception 'A deposit action reason was supplied but this booking has no held deposits.'
      using errcode = '22023';
  end if;
  if held_count > 0 and length(deposit_reason_value) not between 10 and 500 then
    raise exception 'Enter a deposit action reason between 10 and 500 characters.'
      using errcode = '22023';
  end if;

  if deposit_action_value = 'refund' then
    select s.* into shift_row
    from public.pos_shifts s
    where s.opened_by = auth.uid()
      and s.status = 'Open'
    for update;
    if not found then
      raise exception 'An open shift owned by the resolving Manager or Administrator is required to refund cash.'
        using errcode = '55000';
    end if;
  end if;

  if reservation_row.table_id is not null then
    select t.* into table_row
    from public.restaurant_tables t
    where t.id = reservation_row.table_id
    for update;
    if not found then
      raise exception 'The assigned table no longer exists.'
        using errcode = '23503';
    end if;
    if exists (
      select 1
      from public.reservations other
      where other.table_id = reservation_row.table_id
        and other.id <> reservation_row.id
        and (
          other.status = 'Seated'
          or (other.status in ('Pending', 'Confirmed')
            and other.reservation_date >= business_date_value)
        )
    ) then
      raise exception 'Another active booking uses this table; resolve that conflict before changing its availability.'
        using errcode = '55000';
    end if;
    if outcome_value <> 'close_without_charge'
       and table_row.status = 'Needs cleaning' then
      raise exception 'The table already needs cleaning and cannot be marked Available by this booking resolution.'
        using errcode = '55000';
    end if;
  end if;

  select coalesce(array_agg(b.id order by b.created_at, b.id), '{}'::text[])
  into bill_ids_value
  from public.pos_bills b
  where b.reservation_id = reservation_row.id;

  if held_count > 0 then
    for deposit_row in
      select d.*
      from public.pos_reservation_deposits d
      where d.reservation_id = reservation_row.id
        and d.status = 'Held'
      order by d.id
      for update
    loop
      if deposit_action_value = 'refund' then
        cash_movement_id_value := gen_random_uuid()::text;
        movement_key_value := 'STALE-RESOLVE:' ||
          md5(auth.uid()::text || ':' || idempotency_key_value || ':' || deposit_row.id);
        insert into public.pos_cash_movements (
          id, shift_id, movement_type, amount, reason, created_by,
          reference, idempotency_key
        ) values (
          cash_movement_id_value, shift_row.id, 'cash_refund', deposit_row.amount,
          deposit_reason_value, auth.uid(), deposit_row.id, movement_key_value
        );
        cash_movement_ids_value :=
          array_append(cash_movement_ids_value, cash_movement_id_value);
      end if;

      update public.pos_reservation_deposits
      set status = case
        when deposit_action_value = 'refund' then 'Refunded'
        else 'Forfeited'
      end
      where id = deposit_row.id
        and status = 'Held';

      insert into public.pos_deposit_actions (
        deposit_id, action_type, amount, reason, acted_by
      ) values (
        deposit_row.id,
        case when deposit_action_value = 'refund' then 'refunded' else 'forfeited' end,
        deposit_row.amount, deposit_reason_value, auth.uid()
      );
    end loop;
  end if;

  insert into public.pos_stale_booking_resolutions (
    reservation_id, idempotency_key, actor_id, prior_status, outcome,
    resolution_status, resolution_reason, confirmed_no_meal,
    deposit_action, deposit_action_reason, deposit_total, deposit_ids,
    bill_ids, cash_movement_ids, table_id
  ) values (
    reservation_row.id, idempotency_key_value, auth.uid(), reservation_row.status,
    outcome_value, resolved_status_value, reason_value,
    coalesce(p_confirm_no_meal, false), deposit_action_value,
    deposit_reason_value, held_total_value, deposit_ids_value,
    bill_ids_value, cash_movement_ids_value, reservation_row.table_id
  )
  returning * into resolution_row;

  perform set_config('costtrack.stale_booking_resolution_id', reservation_row.id, true);
  update public.reservations
  set status = resolved_status_value,
      completed_at = case
        when outcome_value = 'close_without_charge' then clock_timestamp()
        else completed_at
      end,
      last_correction_reason = reason_value
  where id = reservation_row.id
  returning * into reservation_row;
  perform set_config('costtrack.stale_booking_resolution_id', '', true);

  if reservation_row.table_id is not null then
    update public.restaurant_tables
    set status = case
      when outcome_value = 'close_without_charge' then 'Needs cleaning'
      else 'Available'
    end
    where id = reservation_row.table_id;
  end if;

  return jsonb_build_object(
    'resolution', to_jsonb(resolution_row),
    'reservation_id', reservation_row.id,
    'status', reservation_row.status,
    'table_status', case
      when reservation_row.table_id is null then null
      when outcome_value = 'close_without_charge' then 'Needs cleaning'
      else 'Available'
    end,
    'already_resolved', false
  );
end;
$$;

revoke all on function public.pos_resolve_stale_booking(
  text, text, text, boolean, text, text, text
) from public, anon;
grant execute on function public.pos_resolve_stale_booking(
  text, text, text, boolean, text, text, text
) to authenticated;

-- Retire the pre-D1 entry point. It cannot collect the required no-meal
-- confirmation or deposit decision, so all resolutions must use the new RPC.
create or replace function public.pos_resolve_stale_walkin(
  p_reservation_id text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'This entry point is retired. Use pos_resolve_stale_booking with an explicit outcome and confirmation.'
    using errcode = '0A000';
end;
$$;

revoke all on function public.pos_resolve_stale_walkin(text, text)
  from public, anon, authenticated;

commit;
