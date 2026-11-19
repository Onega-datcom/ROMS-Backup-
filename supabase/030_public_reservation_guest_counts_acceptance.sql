-- Verify public reservation field mapping, guest-count persistence, and validation after migration 030.
-- All reservation rows and rate-limit entries are rolled back.

begin;

do $$
declare
  payload_value jsonb;
  reference_value text;
  reservation_row public.reservations%rowtype;
  rejected boolean;
  party_size integer;
  public_email text := 'phase4-' || replace(gen_random_uuid()::text, '-', '') || '@example.test';
  public_phone text := '09' || lpad((floor(random() * 100000000))::bigint::text, 8, '0');
  public_ip text := '198.51.100.' || (floor(random() * 254) + 1)::integer::text;
begin
  perform set_config(
    'request.headers',
    jsonb_build_object('x-forwarded-for', public_ip)::text,
    true
  );
  payload_value := jsonb_build_object(
    'name', 'Juan Dela Cruz',
    'email', public_email,
    'phone', public_phone,
    'reservation_date', (current_date + 1)::text,
    'reservation_time', '11:00 AM',
    'occasion', 'Birthday',
    'request', 'Window seat near the garden',
    'adults', 2,
    'senior_pwd_count', 1,
    'children', 2,
    'guests', 5,
    'website', ''
  );

  reference_value := public.public_create_reservation(payload_value);
  select * into reservation_row
  from public.reservations
  where id = reference_value;
  if not found
     or reservation_row.name <> 'Juan Dela Cruz'
     or reservation_row.email <> public_email
     or reservation_row.phone <> public_phone
     or reservation_row.reservation_date <> current_date + 1
     or reservation_row.reservation_time <> '11:00 AM'
     or reservation_row.adults <> 2
     or reservation_row.senior_pwd_count <> 1
     or reservation_row.children <> 2
     or reservation_row.guests <> 5
     or reservation_row.occasion <> 'Birthday'
     or reservation_row.request <> 'Window seat near the garden'
     or reservation_row.type <> 'Reservation'
     or reservation_row.status <> 'Pending'
     or reservation_row.source <> 'Website' then
    raise exception 'FAIL: public reservation field mapping, guest counts, status, or source were not persisted as expected';
  end if;

  payload_value := jsonb_build_object(
    'name', 'Phase 2 party of 10',
    'email', 'phase2-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
    'phone', '09' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'),
    'reservation_date', (current_date + 1)::text,
    'reservation_time', '11:00 AM',
    'adults', 5,
    'senior_pwd_count', 2,
    'children', 3,
    'guests', 10,
    'website', ''
  );
  reference_value := public.public_create_reservation(payload_value);
  select * into reservation_row
  from public.reservations
  where id = reference_value;
  if not found
     or reservation_row.adults <> 5
     or reservation_row.senior_pwd_count <> 2
     or reservation_row.children <> 3
     or reservation_row.guests <> 10
     or reservation_row.status <> 'Pending'
     or reservation_row.source <> 'Website' then
    raise exception 'FAIL: large-party categorized guest counts were not persisted exactly';
  end if;

  for party_size in select unnest(array[7, 8, 12]) loop
    payload_value := jsonb_build_object(
      'name', 'Phase 2 party of ' || party_size,
      'email', 'phase2-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
      'phone', '09' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'),
      'reservation_date', (current_date + 1)::text,
      'reservation_time', '11:00 AM',
      'adults', party_size,
      'senior_pwd_count', 0,
      'children', 0,
      'guests', party_size,
      'website', ''
    );
    reference_value := public.public_create_reservation(payload_value);
    select * into reservation_row
    from public.reservations
    where id = reference_value;
    if not found
       or reservation_row.adults <> party_size
       or reservation_row.senior_pwd_count <> 0
       or reservation_row.children <> 0
       or reservation_row.guests <> party_size
       or reservation_row.status <> 'Pending'
       or reservation_row.source <> 'Website' then
      raise exception 'FAIL: party of % was truncated or not saved correctly', party_size;
    end if;
  end loop;

  rejected := false;
  begin
    perform public.public_create_reservation(
      jsonb_set(payload_value, '{guests}', '4'::jsonb)
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then
    raise exception 'FAIL: mismatched guest total was accepted';
  end if;

  rejected := false;
  begin
    perform public.public_create_reservation(
      jsonb_set(payload_value, '{senior_pwd_count}', '-1'::jsonb)
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then
    raise exception 'FAIL: negative guest count was accepted';
  end if;

  rejected := false;
  begin
    perform public.public_create_reservation(
      jsonb_set(payload_value, '{children}', '2.5'::jsonb)
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then
    raise exception 'FAIL: decimal guest count was accepted';
  end if;

  rejected := false;
  begin
    perform public.public_create_reservation(
      jsonb_set(
        jsonb_set(
          jsonb_set(payload_value, '{adults}', '0'::jsonb),
          '{senior_pwd_count}', '0'::jsonb
        ),
        '{children}', '0'::jsonb
      ) || jsonb_build_object('guests', 0)
    );
  exception when others then
    rejected := true;
  end;
  if not rejected then
    raise exception 'FAIL: zero total guest count was accepted';
  end if;
end;
$$;

rollback;
