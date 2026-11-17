-- POS Phase 3 follow-up: require a settled POS bill before a seated
-- reservation can be completed, and expose its deposit audit history.
-- Run after 007_pos_shifts_and_notifications.sql and
-- 008_pos_reservations_deposits_and_close.sql.

begin;

create or replace function public.require_settled_pos_bill_for_reservation_completion()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
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
    ) then
    raise exception 'A reservation can be completed only when its linked POS bill is closed and fully settled.'
      using errcode = '55000';
  end if;
  return new;
end;
$$;

drop trigger if exists require_settled_pos_bill_for_reservation_completion
  on public.reservations;
create trigger require_settled_pos_bill_for_reservation_completion
  before update of status on public.reservations
  for each row
  execute function public.require_settled_pos_bill_for_reservation_completion();

create or replace function public.pos_reservation_deposit_history(p_reservation_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null
    or not public.has_app_role(array['Administrator', 'Manager', 'Receptionist']) then
    raise exception 'Your role cannot view reservation deposit history.'
      using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.reservations where id = p_reservation_id
  ) then
    raise exception 'Reservation not found.' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'deposits', coalesce((
      select jsonb_agg(to_jsonb(d) order by d.created_at, d.id)
      from public.pos_reservation_deposits d
      where d.reservation_id = p_reservation_id
    ), '[]'::jsonb),
    'actions', coalesce((
      select jsonb_agg(to_jsonb(a) order by a.acted_at, a.id)
      from public.pos_deposit_actions a
      join public.pos_reservation_deposits d on d.id = a.deposit_id
      where d.reservation_id = p_reservation_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.pos_reservation_deposit_history(text) from public, anon;
grant execute on function public.pos_reservation_deposit_history(text) to authenticated;

commit;
