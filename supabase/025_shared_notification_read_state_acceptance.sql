-- Run as the database owner after migration 025.
-- Requires one existing profile for each application role. Test rows roll back.
begin;

do $$
declare
  manager_id uuid;
  receptionist_id uuid;
  clerk_id uuid;
  chef_id uuid;
  manager_key text := 'p7-manager-' || gen_random_uuid()::text;
  receptionist_key text := 'p7-receptionist-' || gen_random_uuid()::text;
  read_keys text[];
  denied boolean;
begin
  select id into manager_id from public.profiles where role = 'Manager' limit 1;
  select id into receptionist_id from public.profiles where role = 'Receptionist' limit 1;
  select id into clerk_id from public.profiles where role = 'Inventory Clerk' limit 1;
  select id into chef_id from public.profiles where role = 'Chef / Kitchen Staff' limit 1;
  if manager_id is null or receptionist_id is null or clerk_id is null or chef_id is null then
    raise exception 'FAIL: provision Manager, Receptionist, Inventory Clerk, and Chef / Kitchen Staff profiles.';
  end if;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', manager_id::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', manager_id::text, 'role', 'authenticated')::text, true);
  perform public.costtrack_mark_notifications_read(array[manager_key]);
  read_keys := public.costtrack_notification_read_keys();
  if not manager_key = any(read_keys) then
    raise exception 'FAIL: Manager notification read state was not saved.';
  end if;

  perform set_config('request.jwt.claim.sub', receptionist_id::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', receptionist_id::text, 'role', 'authenticated')::text, true);
  read_keys := public.costtrack_notification_read_keys();
  if manager_key = any(read_keys) then
    raise exception 'FAIL: notification read state leaked across roles.';
  end if;
  perform public.costtrack_mark_notifications_read(array[receptionist_key]);

  denied := false;
  begin
    perform public.costtrack_mark_notifications_read(array['pos:not-authorized']);
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: Receptionist was allowed to mark a Manager/Admin POS notification read.';
  end if;

  foreach manager_id in array array[clerk_id, chef_id]
  loop
    perform set_config('request.jwt.claim.sub', manager_id::text, true);
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', manager_id::text, 'role', 'authenticated')::text, true);
    perform public.costtrack_mark_notifications_read(array[
      'p7-role-' || manager_id::text
    ]);
  end loop;
end;
$$;

rollback;
