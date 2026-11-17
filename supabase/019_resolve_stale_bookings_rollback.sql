-- Disable Phase D1 resolution RPCs and restore the 016 Walk-in entry point.
-- Append-only resolution records and the Manila business-date authority remain
-- in place; no operational or audit data is deleted.

begin;

drop function if exists public.pos_resolve_stale_booking(
  text, text, text, boolean, text, text, text
);
drop function if exists public.pos_list_unresolved_stale_bookings();

create or replace function public.stale_booking_resolution_is_allowed(
  p_reservation_id text,
  p_new_status text,
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

revoke all on function public.stale_booking_resolution_is_allowed(text, text, text)
  from public, anon, authenticated;

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
     or reservation_row.reservation_date >= public.pos_business_date()
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
  if reservation_row.reservation_date >= public.pos_business_date()
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

revoke all on function public.pos_resolve_stale_walkin(text, text)
  from public, anon, authenticated;
grant execute on function public.pos_resolve_stale_walkin(text, text)
  to authenticated;

commit;
