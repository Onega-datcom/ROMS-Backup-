-- Allow audited Manager/Administrator cleanup of past Seated Walk-ins that
-- have no non-Closed/unsettled bill or unresolved deposit.
-- Run after 015_past_reservation_bill_close.sql.

begin;

create or replace function public.stale_walkin_completion_is_allowed(
  p_reservation_id text,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reservation_row public.reservations%rowtype;
begin
  if auth.uid() is null
     or not public.has_app_role(array['Administrator', 'Manager'])
     or current_setting('costtrack.stale_walkin_completion_id', true)
       is distinct from p_reservation_id
     or length(btrim(coalesce(p_reason, ''))) not between 10 and 500 then
    return false;
  end if;

  select r.* into reservation_row
  from public.reservations r
  where r.id = p_reservation_id;
  if not found
     or reservation_row.reservation_date >= current_date
     or reservation_row.type <> 'Walk-in'
     or reservation_row.status <> 'Seated' then
    return false;
  end if;

  if exists (
    select 1
    from public.pos_bills b
    where b.reservation_id = p_reservation_id
      and (b.status <> 'Closed' or b.balance_due <> 0)
  ) or exists (
    select 1
    from public.pos_reservation_deposits d
    where d.reservation_id = p_reservation_id
      and d.status = 'Held'
  ) then
    return false;
  end if;

  return true;
end;
$$;

revoke all on function public.stale_walkin_completion_is_allowed(text, text)
  from public, anon, authenticated;

create or replace function public.require_settled_pos_bill_for_reservation_completion()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
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
     ) then
    raise exception 'A reservation can be completed only when its linked POS bill is closed and fully settled.'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_reservation_history_guard()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    if old.reservation_date < current_date then
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

    if old.reservation_date < current_date then
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
         and public.has_app_role(array['Administrator', 'Manager', 'Receptionist'])
         and (to_jsonb(new) - array['status', 'completed_at', 'actual_covers', 'updated_at'])
           is not distinct from
           (to_jsonb(old) - array['status', 'completed_at', 'actual_covers', 'updated_at'])
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

create or replace function public.pos_resolve_stale_walkin(
  p_reservation_id text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  reservation_row public.reservations%rowtype;
begin
  if auth.uid() is null
     or not public.has_app_role(array['Administrator', 'Manager']) then
    raise exception 'Only Managers and Administrators can resolve a stale Walk-in.'
      using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) not between 10 and 500 then
    raise exception 'Enter a reason between 10 and 500 characters.'
      using errcode = '22023';
  end if;

  select r.* into reservation_row
  from public.reservations r
  where r.id = p_reservation_id
  for update;
  if not found then
    raise exception 'Reservation not found.' using errcode = 'P0002';
  end if;
  if reservation_row.reservation_date >= current_date
     or reservation_row.type <> 'Walk-in' then
    raise exception 'Only past Walk-in reservations can be resolved this way.'
      using errcode = '55000';
  end if;

  if exists (
    select 1
    from public.pos_bills b
    where b.reservation_id = p_reservation_id
      and (b.status <> 'Closed' or b.balance_due <> 0)
  ) then
    raise exception 'Resolve this Walk-in’s linked POS bill first (it must be Closed and fully settled).'
      using errcode = '55000';
  end if;
  if exists (
    select 1
    from public.pos_reservation_deposits d
    where d.reservation_id = p_reservation_id
      and d.status = 'Held'
  ) then
    raise exception 'Refund or forfeit this Walk-in’s held deposit before resolving it.'
      using errcode = '55000';
  end if;
  if reservation_row.status = 'Completed' then
    return jsonb_build_object(
      'reservation_id', reservation_row.id,
      'status', reservation_row.status,
      'already_completed', true
    );
  end if;
  if reservation_row.status <> 'Seated' then
    raise exception 'Only a past Seated Walk-in can be resolved.'
      using errcode = '55000';
  end if;

  perform set_config('costtrack.stale_walkin_completion_id', reservation_row.id, true);
  update public.reservations
  set status = 'Completed',
      completed_at = clock_timestamp(),
      last_correction_reason = btrim(p_reason)
  where id = reservation_row.id
  returning * into reservation_row;
  perform set_config('costtrack.stale_walkin_completion_id', '', true);

  return jsonb_build_object(
    'reservation_id', reservation_row.id,
    'status', reservation_row.status,
    'already_completed', false
  );
end;
$$;

revoke all on function public.pos_resolve_stale_walkin(text, text) from public, anon;
grant execute on function public.pos_resolve_stale_walkin(text, text) to authenticated;

commit;
