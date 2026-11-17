begin;

alter table public.reservations
  add column if not exists last_correction_reason text not null default '';

comment on column public.reservations.last_correction_reason is
  'Reason for the most recent privileged correction to a past reservation; changes are also stored in audit_logs.';

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

  if tg_op = 'INSERT'
     or new.status is distinct from old.status
     or new.table_id is distinct from old.table_id
     or new.reservation_date is distinct from old.reservation_date
     or new.reservation_time is distinct from old.reservation_time then
    if new.table_id is not null and new.status = 'Seated' then
      update public.restaurant_tables
      set status = 'Occupied',
          guest = new.name
      where id = new.table_id;
    elsif new.table_id is not null
          and new.status in ('Completed', 'Cancelled', 'No-show') then
      select exists (
        select 1
        from public.reservations as r
        where r.id <> new.id
          and r.table_id = new.table_id
          and r.reservation_date = new.reservation_date
          and r.reservation_time = new.reservation_time
          and r.status in ('Pending', 'Confirmed', 'Seated')
      ) into table_is_held;
      if table_is_held then
        update public.restaurant_tables
        set status = 'Reserved'
        where id = new.table_id;
      else
        update public.restaurant_tables
        set status = 'Available',
            guest = ''
        where id = new.table_id;
      end if;
    end if;
  elsif tg_op = 'UPDATE'
        and new.status = 'Seated'
        and new.table_id is not null
        and new.reservation_date >= current_date
        and new.name is distinct from old.name then
    update public.restaurant_tables
    set guest = new.name
    where id = new.table_id;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_reservation_history_guard on public.reservations;
create trigger enforce_reservation_history_guard
  before insert or update or delete on public.reservations
  for each row execute function public.enforce_reservation_history_guard();

revoke all on function public.enforce_reservation_history_guard() from public, anon, authenticated;

commit;
