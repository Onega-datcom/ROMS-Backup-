-- Phase A acceptance checks. Run as the database owner after migration 012.
-- All test rows and public-reservation rate-limit entries are rolled back.

begin;

do $$
declare
  suffix text := upper(replace(gen_random_uuid()::text, '-', ''));
  table_id_value text;
  walk_in_id text;
  staff_reservation_id text;
  public_reference text;
  public_phone text;
  public_ip text;
  reservation_row public.reservations%rowtype;
begin
  table_id_value := 'PA-' || left(suffix, 12);
  walk_in_id := 'PA-WI-' || left(suffix, 12);
  staff_reservation_id := 'PA-ST-' || left(suffix, 12);
  public_phone := '09' || lpad((floor(random() * 100000000))::bigint::text, 8, '0');
  public_ip := '198.51.100.' || (floor(random() * 254) + 1)::integer::text;
  perform set_config(
    'request.headers',
    jsonb_build_object('x-forwarded-for', public_ip)::text,
    true
  );

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.reservations'::regclass
      and conname = 'reservations_guest_count_check'
      and position('senior_pwd_count' in pg_get_constraintdef(oid)) > 0
  ) then
    raise exception 'FAIL: reservations_guest_count_check must include senior_pwd_count; run migration 012';
  end if;

  insert into public.restaurant_tables (id, seats)
  values (table_id_value, 7);

  insert into public.reservations (
    id, name, reservation_date, reservation_time, guests, type,
    adults, senior_pwd_count, children, status, table_id, source
  ) values (
    walk_in_id, 'Walk-in guest', current_date + 1, '11:00 AM', 7, 'Walk-in',
    4, 1, 2, 'Seated', table_id_value, 'Walk-in'
  );

  select * into reservation_row
  from public.reservations
  where id = walk_in_id;
  if reservation_row.adults <> 4
     or reservation_row.senior_pwd_count <> 1
     or reservation_row.children <> 2
     or reservation_row.guests <> 7
     or reservation_row.actual_covers <> 7
     or reservation_row.source <> 'Walk-in'
     or reservation_row.email is not null
     or reservation_row.phone is not null then
    raise exception 'FAIL: contactless 4/1/2 Walk-in did not persist correctly';
  end if;

  begin
    insert into public.reservations (
      id, name, reservation_date, reservation_time, guests, type,
      adults, senior_pwd_count, children, status, table_id
    ) values (
      'PA-OV-' || left(suffix, 12), 'Oversized walk-in',
      current_date + 1, '2:00 PM', 8, 'Walk-in',
      8, 0, 0, 'Seated', table_id_value
    );
    raise exception 'FAIL: table capacity accepted 8 guests at 7-seat table';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.reservations (
      id, name, reservation_date, reservation_time, guests, type,
      adults, senior_pwd_count, children, status
    ) values (
      'PA-ZERO-' || left(suffix, 10), 'Zero guest test',
      current_date + 1, '11:00 AM', 1, 'Walk-in',
      0, 0, 0, 'Pending'
    );
    raise exception 'FAIL: zero total guests were accepted';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.reservations (
      id, name, reservation_date, reservation_time, guests, type,
      adults, senior_pwd_count, children, status
    ) values (
      'PA-NEG-' || left(suffix, 10), 'Negative count test',
      current_date + 1, '11:00 AM', 1, 'Walk-in',
      -1, 2, 0, 'Pending'
    );
    raise exception 'FAIL: negative guest count was accepted';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.reservations (
      id, name, reservation_date, reservation_time, guests, type,
      adults, senior_pwd_count, children, status
    ) values (
      'PA-DEC-' || left(suffix, 10), 'Decimal count test',
      current_date + 1, '11:00 AM', 1, 'Walk-in',
      '0.5', 1, 0, 'Pending'
    );
    raise exception 'FAIL: decimal guest count was accepted';
  exception when invalid_text_representation then
    null;
  end;

  insert into public.reservations (
    id, name, email, phone, reservation_date, reservation_time,
    guests, type, adults, senior_pwd_count, children, status, source
  ) values (
    staff_reservation_id, 'Phone-only staff booking', null, '09123456789',
    current_date + 1, '3:00 PM', 2, 'Reservation', 1, 1, 0, 'Pending', 'Phone'
  );

  select * into reservation_row
  from public.reservations
  where id = staff_reservation_id;
  if reservation_row.status <> 'Pending'
     or reservation_row.email is not null
     or reservation_row.phone <> '09123456789'
     or reservation_row.adults <> 1
     or reservation_row.senior_pwd_count <> 1
     or reservation_row.guests <> 2
     or reservation_row.source <> 'Phone' then
    raise exception 'FAIL: phone-only staff reservation did not persist correctly';
  end if;

  public_reference := public.public_create_reservation(jsonb_build_object(
    'name', 'Phase A website acceptance',
    'phone', public_phone,
    'reservation_date', (current_date + 1)::text,
    'reservation_time', '5:00 PM',
    'guests', 2,
    'adults', 2,
    'children', 0,
    'occasion', '',
    'preference', '',
    'request', ''
  ));

  select * into reservation_row
  from public.reservations
  where id = public_reference;
  if reservation_row.status <> 'Pending'
     or reservation_row.senior_pwd_count <> 0
     or reservation_row.source <> 'Website'
     or reservation_row.guests <> 2
     or reservation_row.adults <> 2 then
    raise exception 'FAIL: public booking did not remain Pending with Senior/PWD zero and Website source';
  end if;

  raise notice 'PASS: walk-in 4/1/2 counts, contactless Walk-in, table capacity, phone-only staff booking, and public Website booking';
end;
$$;

rollback;
