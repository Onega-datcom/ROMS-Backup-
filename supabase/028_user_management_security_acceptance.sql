-- Run as the database owner after migration 028.
-- Requires one Administrator and one Manager profile. All changes are rolled back.
begin;

do $$
declare
  admin_id uuid;
  manager_id uuid;
begin
  select id into admin_id
  from public.profiles
  where role = 'Administrator'
  order by id
  limit 1;
  select id into manager_id
  from public.profiles
  where role = 'Manager'
  order by id
  limit 1;

  if admin_id is null or manager_id is null then
    raise exception 'FAIL: provision one Administrator and one Manager profile first.';
  end if;

  perform set_config('costtrack.test.admin_id', admin_id::text, true);
  perform set_config('costtrack.test.manager_id', manager_id::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', admin_id::text, 'role', 'authenticated')::text,
    true
  );
end;
$$;

set local role authenticated;

do $$
declare
  admin_id uuid := current_setting('costtrack.test.admin_id')::uuid;
  manager_id uuid := current_setting('costtrack.test.manager_id')::uuid;
  denied boolean := false;
begin
  if public.costtrack_update_profile_role(
    manager_id, 'Receptionist', 'Phase 1 acceptance test'
  ) is not true then
    raise exception 'FAIL: an Administrator role update did not report a change.';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = manager_id and role = 'Receptionist'
  ) then
    raise exception 'FAIL: the role update was not persisted.';
  end if;

  if not exists (
    select 1
    from public.profile_role_audit
    where user_id = manager_id
      and old_role = 'Manager'
      and new_role = 'Receptionist'
      and changed_by = admin_id
      and reason = 'Phase 1 acceptance test'
  ) then
    raise exception 'FAIL: the role change audit record is missing or incorrect.';
  end if;

  if public.costtrack_update_profile_role(
    manager_id, 'Receptionist', 'No-op acceptance test'
  ) is not false then
    raise exception 'FAIL: a no-op role update was reported as a successful change.';
  end if;
  if exists (
    select 1
    from public.profile_role_audit
    where user_id = manager_id and reason = 'No-op acceptance test'
  ) then
    raise exception 'FAIL: a no-op role update generated an audit record.';
  end if;

  denied := false;
  begin
    perform public.costtrack_update_profile_role(
      admin_id, 'Manager', 'Self-demotion acceptance test'
    );
  exception when insufficient_privilege then
    if position('Users cannot change their own role' in sqlerrm) = 0 then
      raise exception 'FAIL: self-demotion was rejected for an unexpected reason: %', sqlerrm;
    end if;
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: an Administrator was allowed to change their own role.';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    manager_id::text,
    true
  );
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', manager_id::text, 'role', 'authenticated')::text,
    true
  );

  denied := false;
  begin
    perform public.costtrack_update_profile_role(
      admin_id, 'Manager', 'Unauthorized acceptance test'
    );
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: a non-Administrator called the role-change RPC.';
  end if;

  if exists (
    select 1
    from public.profile_role_audit
    where user_id = manager_id
  ) then
    raise exception 'FAIL: a non-Administrator read profile role audit data.';
  end if;

  denied := false;
  begin
    update public.profiles
    set role = 'Manager'
    where id = admin_id;
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: a direct profile role update was allowed through the API.';
  end if;

  denied := false;
  begin
    delete from public.profiles where id = manager_id;
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: profile deletion was allowed through the API.';
  end if;
end;
$$;

reset role;

do $$
declare
  admin_id uuid := current_setting('costtrack.test.admin_id')::uuid;
  blocked boolean := false;
begin
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', admin_id::text, 'role', 'authenticated')::text,
    true
  );

  begin
    update public.profiles
    set role = 'Manager'
    where id = admin_id;
  exception when insufficient_privilege then
    if position('Users cannot change their own role' in sqlerrm) = 0 then
      raise exception 'FAIL: direct self-demotion was rejected for an unexpected reason: %', sqlerrm;
    end if;
    blocked := true;
  end;
  if not blocked then
    raise exception 'FAIL: a direct SQL self-demotion was allowed.';
  end if;

  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', admin_id::text, 'role', 'authenticated')::text,
    true
  );

  update public.profiles
  set role = 'Manager'
  where role = 'Administrator' and id <> admin_id;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  blocked := false;
  begin
    update public.profiles
    set role = 'Chef / Kitchen Staff'
    where id = current_setting('costtrack.test.manager_id')::uuid;
  exception when insufficient_privilege then
    if position('Only Administrators may change user roles' in sqlerrm) = 0 then
      raise exception 'FAIL: direct role change was rejected unexpectedly: %', sqlerrm;
    end if;
    blocked := true;
  end;
  if not blocked then
    raise exception 'FAIL: SQL without an Administrator identity changed a role.';
  end if;

  blocked := false;
  begin
    update public.profiles
    set role = 'Manager'
    where id = admin_id;
  exception when check_violation then
    if position('last Administrator' in sqlerrm) = 0 then
      raise exception 'FAIL: the last Administrator demotion was rejected unexpectedly: %', sqlerrm;
    end if;
    blocked := true;
  end;
  if not blocked then
    raise exception 'FAIL: the last Administrator was demoted through direct SQL.';
  end if;

  blocked := false;
  begin
    delete from public.profiles where id = admin_id;
  exception when object_not_in_prerequisite_state then
    if position('last Administrator' in sqlerrm) = 0 then
      raise exception 'FAIL: direct profile deletion was rejected unexpectedly: %', sqlerrm;
    end if;
    blocked := true;
  end;
  if not blocked then
    raise exception 'FAIL: direct SQL deleted the last Administrator profile.';
  end if;

  if (select role from public.profiles where id = admin_id) <> 'Administrator'
     or (select administrator_count from public.profile_admin_guard where singleton) <> 1
     or (select count(*) from public.profiles where role = 'Administrator') <> 1 then
    raise exception 'FAIL: a rejected operation changed the Administrator state.';
  end if;
end;
$$;

select 'PASS: role updates, audit logging, authorization, self-demotion, last-admin, and delete protections' as acceptance_result;
rollback;
