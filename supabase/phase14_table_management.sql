begin;

drop policy if exists restaurant_tables_insert on public.restaurant_tables;
create policy restaurant_tables_insert
  on public.restaurant_tables for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager']));

drop policy if exists restaurant_tables_update on public.restaurant_tables;
create policy restaurant_tables_update
  on public.restaurant_tables for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']))
  with check (public.has_app_role(array['Administrator', 'Manager']));

drop index if exists public.reservations_active_assigned_table_uidx;
create unique index reservations_active_assigned_table_uidx
  on public.reservations (table_id, reservation_date, reservation_time)
  where table_id is not null and status not in ('Cancelled', 'Completed', 'No-show');

create or replace function public.enforce_reservation_table_capacity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  table_capacity integer;
begin
  if tg_op = 'INSERT'
     or new.table_id is distinct from old.table_id
     or new.guests is distinct from old.guests
     or new.actual_covers is distinct from old.actual_covers then
    if new.table_id is not null then
      select seats into table_capacity
      from public.restaurant_tables
      where id = new.table_id;
      if not found then
        raise exception 'The selected table does not exist'
          using errcode = '23503';
      end if;
      if coalesce(new.actual_covers, new.guests) > table_capacity then
        raise exception 'The selected table does not have enough seats for this reservation'
          using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_reservation_capacity on public.reservations;
create trigger enforce_reservation_capacity
  before insert or update on public.reservations
  for each row execute function public.enforce_reservation_table_capacity();

create or replace function public.enforce_restaurant_table_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
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
         and reservation_date >= current_date
         and status in ('Pending', 'Confirmed', 'Seated')
         and coalesce(actual_covers, guests) > new.seats
     ) then
    raise exception 'Table capacity cannot be reduced below an assigned active party'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_restaurant_table_update on public.restaurant_tables;
create trigger enforce_restaurant_table_update
  before update on public.restaurant_tables
  for each row execute function public.enforce_restaurant_table_update();

create or replace function public.prevent_table_delete_with_reservations()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if exists (
    select 1
    from public.reservations
    where table_id = old.id
  ) then
    raise exception 'Tables linked to reservation history cannot be deleted'
      using errcode = '23503';
  end if;
  return old;
end;
$$;

drop trigger if exists prevent_table_delete_with_reservations on public.restaurant_tables;
create trigger prevent_table_delete_with_reservations
  before delete on public.restaurant_tables
  for each row execute function public.prevent_table_delete_with_reservations();

revoke all on function public.enforce_reservation_table_capacity() from public, anon, authenticated;
revoke all on function public.enforce_restaurant_table_update() from public, anon, authenticated;
revoke all on function public.prevent_table_delete_with_reservations() from public, anon, authenticated;

commit;
