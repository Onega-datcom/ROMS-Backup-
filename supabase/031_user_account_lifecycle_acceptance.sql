begin;

do $$
declare
  admin_id uuid;
  target_id uuid;
  target_role text;
  changed boolean;
  invite_id uuid;
  invited_email text := 'lifecycle-' || replace(gen_random_uuid()::text, '-', '') || '@example.test';
begin
  select id
  into admin_id
  from public.profiles
  where role = 'Administrator'
    and account_status = 'Active'
  order by id
  limit 1;
  if admin_id is null then
    raise exception 'FAIL: an active Administrator is required for lifecycle acceptance tests.';
  end if;

  select id, role
  into target_id, target_role
  from public.profiles
  where role <> 'Administrator'
    and account_status = 'Active'
  order by id
  limit 1;
  if target_id is null then
    raise exception 'FAIL: an active non-Administrator profile is required for lifecycle acceptance tests.';
  end if;

  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('role', 'service_role', 'sub', admin_id)::text,
    true
  );
  perform set_config('request.jwt.claim.sub', admin_id::text, true);

  changed := public.costtrack_set_profile_account_status(
    target_id,
    'Deactivated',
    admin_id,
    'Acceptance test'
  );
  if not changed or not exists (
    select 1 from public.profiles
    where id = target_id and account_status = 'Deactivated'
  ) then
    raise exception 'FAIL: an active staff account was not deactivated.';
  end if;

  perform set_config('request.jwt.claim.sub', target_id::text, true);
  if public.has_app_role(array[target_role]) then
    raise exception 'FAIL: a deactivated account retained its application role.';
  end if;
  perform set_config('request.jwt.claim.sub', admin_id::text, true);

  changed := public.costtrack_set_profile_account_status(
    target_id,
    'Active',
    admin_id,
    'Acceptance test reactivation'
  );
  if not changed or not exists (
    select 1 from public.profiles
    where id = target_id and account_status = 'Active'
  ) then
    raise exception 'FAIL: a deactivated staff account was not reactivated.';
  end if;

  if (
    select count(*)
    from public.profiles
    where role = 'Administrator'
      and account_status = 'Active'
  ) = 1 then
    begin
      update public.profiles
      set account_status = 'Deactivated'
      where id = admin_id;
      raise exception 'FAIL: the last active Administrator was deactivated.';
    exception when check_violation then
      null;
    end;
    if not exists (
      select 1 from public.profiles
      where id = admin_id and account_status = 'Active'
    ) then
      raise exception 'FAIL: rejected deactivation changed the last Administrator.';
    end if;
  end if;

  insert into public.user_invites (
    email, full_name, role, invited_by, expires_at
  ) values (
    invited_email,
    'Lifecycle Acceptance',
    'Manager',
    admin_id,
    clock_timestamp() + interval '7 days'
  )
  returning id into invite_id;

  perform set_config('costtrack.account_status_change', 'on', true);
  update public.profiles
  set email = invited_email,
      account_status = 'Pending'
  where id = target_id;
  perform set_config('costtrack.account_status_change', 'off', true);

  if public.costtrack_cancel_user_invitation(invite_id, admin_id)
    is distinct from target_id then
    raise exception 'FAIL: cancellation did not locate the invited profile.';
  end if;
  if not exists (
    select 1
    from public.user_invites
    where id = invite_id and status = 'Cancelled'
  ) then
    raise exception 'FAIL: a pending invitation was not cancelled.';
  end if;
  if not exists (
    select 1
    from public.profiles
    where id = target_id and account_status = 'Cancelled'
  ) then
    raise exception 'FAIL: cancellation did not block the pending profile.';
  end if;

  if not exists (
    select 1
    from public.profile_account_status_audit
    where user_id = target_id
      and changed_by = admin_id
      and old_status = 'Active'
      and new_status = 'Deactivated'
      and reason = 'Acceptance test'
  ) then
    raise exception 'FAIL: account deactivation was not recorded in the audit table.';
  end if;

  delete from public.profiles where id = target_id;
  if exists (select 1 from public.profiles where id = target_id) then
    raise exception 'FAIL: a cancelled pending profile could not be removed during Auth cleanup.';
  end if;
end;
$$;

rollback;
