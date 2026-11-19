-- Persist all public reservation guest categories and derive the total from them.
-- Run after 029_user_invites.sql.

begin;

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
  provided_guest_count integer;
  computed_guest_count bigint;
  adult_count integer;
  senior_pwd_count integer;
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
  if reservation_day is null then
    raise exception 'A reservation date is required';
  end if;
  if reservation_day < current_date then
    raise exception 'Reservation date cannot be in the past';
  end if;
  reservation_time_value := nullif(btrim(payload ->> 'reservation_time'), '');
  if reservation_time_value is null or length(reservation_time_value) > 40 then
    raise exception 'A reservation time is required';
  end if;
  if not public.reservation_time_within_open_hours(reservation_time_value) then
    raise exception 'The two-hour reservation window must fit between 10:00 AM and 9:00 PM'
      using errcode = '23514';
  end if;

  provided_guest_count := nullif(payload ->> 'guests', '')::integer;
  adult_count := coalesce(nullif(payload ->> 'adults', '')::integer, provided_guest_count);
  senior_pwd_count := coalesce(nullif(payload ->> 'senior_pwd_count', '')::integer, 0);
  child_count := coalesce(nullif(payload ->> 'children', '')::integer, 0);
  if adult_count is null then
    raise exception 'Guest counts are invalid';
  end if;
  computed_guest_count := adult_count::bigint + senior_pwd_count + child_count;
  if computed_guest_count < 1 or computed_guest_count > 1000
     or adult_count < 0 or senior_pwd_count < 0 or child_count < 0
     or (provided_guest_count is not null
       and provided_guest_count::bigint <> computed_guest_count) then
    raise exception 'Guest counts are invalid';
  end if;
  guest_count := computed_guest_count::integer;

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
        ->> 'x-forwarded-for',
      ',', 1
    ), ''),
    nullif(
      coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb
        ->> 'x-real-ip',
      ''
    ),
    'unknown'
  );
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
      guests, type, adults, senior_pwd_count, children,
      occasion, status, preference, request, created_by
    ) values (
      new_reference, reservation_name, reservation_email, reservation_phone,
      reservation_day, reservation_time_value, guest_count, 'Reservation',
      adult_count, senior_pwd_count, child_count,
      occasion_value, 'Pending', preference_value, request_value, auth.uid()
    );
  exception when unique_violation then
    raise exception 'Reservation reference or table/time slot is already in use'
      using errcode = '23P01';
  end;

  return new_reference;
end;
$$;

commit;
