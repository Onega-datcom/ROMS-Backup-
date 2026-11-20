-- Run as the database owner after migration 033.
-- Requires active Receptionist and Chef / Kitchen Staff profiles.
-- The test table and status changes are rolled back.
begin;

do $$
declare
  receptionist_id uuid;
  chef_id uuid;
  table_id text := '033-CLEAN-' || gen_random_uuid()::text;
begin
  select id into receptionist_id
  from public.profiles
  where role = 'Receptionist' and account_status = 'Active'
  order by id limit 1;
  select id into chef_id
  from public.profiles
  where role = 'Chef / Kitchen Staff' and account_status = 'Active'
  order by id limit 1;

  if receptionist_id is null or chef_id is null then
    raise exception 'FAIL: provision active Receptionist and Chef / Kitchen Staff profiles first.';
  end if;

  insert into public.restaurant_tables (id, seats, status)
  values (table_id, 2, 'Needs cleaning');
  perform set_config('costtrack.test.receptionist_id', receptionist_id::text, true);
  perform set_config('costtrack.test.chef_id', chef_id::text, true);
  perform set_config('costtrack.test.table_id', table_id, true);
end;
$$;

set local role authenticated;

do $$
declare
  receptionist_id uuid := current_setting('costtrack.test.receptionist_id')::uuid;
  table_id text := current_setting('costtrack.test.table_id');
  denied boolean := false;
begin
  perform set_config('request.jwt.claim.sub', receptionist_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', receptionist_id, 'role', 'authenticated')::text,
    true
  );

  if not public.costtrack_mark_table_clean(table_id) then
    raise exception 'FAIL: the Receptionist RPC did not report success.';
  end if;
  if not exists (
    select 1 from public.restaurant_tables
    where id = table_id and status = 'Available'
  ) then
    raise exception 'FAIL: the Receptionist could not mark a table available.';
  end if;

  update public.restaurant_tables
  set status = 'Needs cleaning'
  where id = table_id;
  if not exists (
    select 1 from public.restaurant_tables
    where id = table_id and status = 'Available'
  ) then
    raise exception 'FAIL: the Receptionist can directly update table records.';
  end if;

  begin
    perform public.costtrack_mark_table_clean(table_id);
    raise exception 'FAIL: a second cleaning action succeeded for an already available table.';
  exception
    when sqlstate '55000' then null;
  end;

  perform set_config('request.jwt.claim.sub', current_setting('costtrack.test.chef_id'), true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', current_setting('costtrack.test.chef_id')::uuid,
      'role', 'authenticated'
    )::text,
    true
  );
  begin
    perform public.costtrack_mark_table_clean(table_id);
  exception
    when sqlstate '42501' then denied := true;
  end;
  if not denied then
    raise exception 'FAIL: a non-Receptionist role can use the table-cleaning RPC.';
  end if;
end;
$$;

rollback;
