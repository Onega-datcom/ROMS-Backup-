-- Run as the database owner after migrations 029, 030, 031, and 032.
-- Requires one active Administrator and active profiles for the four staff roles.
-- All fixture changes are rolled back.
begin;

do $$
declare
  admin_id uuid;
  role_profiles jsonb;
  role_count integer;
begin
  select id
  into admin_id
  from public.profiles
  where role = 'Administrator'
    and account_status = 'Active'
  order by id
  limit 1;
  if admin_id is null then
    raise exception 'FAIL: provision an active Administrator first.';
  end if;

  select jsonb_agg(jsonb_build_object('id', id, 'role', role) order by role),
         count(distinct role)
  into role_profiles, role_count
  from (
    select distinct on (role) id, role
    from public.profiles
    where role in (
      'Manager',
      'Receptionist',
      'Inventory Clerk',
      'Chef / Kitchen Staff'
    )
      and account_status = 'Active'
    order by role, id
  ) as fixtures;
  if coalesce(role_count, 0) <> 4 then
    raise exception 'FAIL: provision one active Manager, Receptionist, Inventory Clerk, and Chef / Kitchen Staff profile first.';
  end if;

  perform set_config('costtrack.test.admin_id', admin_id::text, true);
  perform set_config('costtrack.test.role_profiles', role_profiles::text, true);
  perform set_config(
    'request.jwt.claim.sub',
    admin_id::text,
    true
  );
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', admin_id, 'role', 'authenticated')::text,
    true
  );

  insert into public.user_invites (
    email, full_name, role, invited_by, expires_at
  ) values (
    'u1-visibility-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
    'U1 Visibility Fixture',
    'Manager',
    admin_id,
    clock_timestamp() + interval '7 days'
  );
end;
$$;

set local role authenticated;

do $$
declare
  admin_id uuid := current_setting('costtrack.test.admin_id')::uuid;
  role_fixture record;
  denied boolean;
begin
  for role_fixture in
    select *
    from jsonb_to_recordset(current_setting('costtrack.test.role_profiles')::jsonb)
      as actor(id uuid, role text)
  loop
    perform set_config('request.jwt.claim.sub', role_fixture.id::text, true);
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object('sub', role_fixture.id, 'role', 'authenticated')::text,
      true
    );

    if exists (
      select 1
      from public.profiles
      where id = admin_id
    ) then
      raise exception 'FAIL: % can read another user profile.', role_fixture.role;
    end if;
    if exists (select 1 from public.user_invites) then
      raise exception 'FAIL: % can read invitation history.', role_fixture.role;
    end if;

    denied := false;
    begin
      insert into public.profiles (id, email, full_name, role)
      values (
        gen_random_uuid(),
        'u1-profile-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
        'Unauthorized Profile',
        'Manager'
      );
    exception when insufficient_privilege then
      denied := true;
    end;
    if not denied then
      raise exception 'FAIL: % profile INSERT was not denied by PostgreSQL grants.', role_fixture.role;
    end if;

    denied := false;
    begin
      update public.profiles
      set role = 'Manager'
      where id = role_fixture.id;
    exception when insufficient_privilege then
      denied := true;
    end;
    if not denied then
      raise exception 'FAIL: % profile UPDATE was not denied by PostgreSQL grants.', role_fixture.role;
    end if;

    denied := false;
    begin
      update public.profiles
      set account_status = 'Deactivated'
      where id = role_fixture.id;
    exception when insufficient_privilege then
      denied := true;
    end;
    if not denied then
      raise exception 'FAIL: % profile status UPDATE was not denied by PostgreSQL grants.', role_fixture.role;
    end if;

    denied := false;
    begin
      insert into public.user_invites (
        email, full_name, role, invited_by, expires_at
      ) values (
        'u1-invite-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
        'Unauthorized Invite',
        'Manager',
        admin_id,
        clock_timestamp() + interval '7 days'
      );
    exception when insufficient_privilege then
      denied := true;
    end;
    if not denied then
      raise exception 'FAIL: % invitation INSERT was not denied by PostgreSQL grants.', role_fixture.role;
    end if;

    denied := false;
    begin
      update public.user_invites
      set status = 'Cancelled';
    exception when insufficient_privilege then
      denied := true;
    end;
    if not denied then
      raise exception 'FAIL: % invitation UPDATE was not denied by PostgreSQL grants.', role_fixture.role;
    end if;

    denied := false;
    begin
      perform public.costtrack_update_profile_role(
        role_fixture.id,
        'Manager',
        'Unauthorized acceptance attempt'
      );
    exception when insufficient_privilege then
      denied := true;
    end;
    if not denied then
      raise exception 'FAIL: % role-change RPC was not denied.', role_fixture.role;
    end if;

    denied := false;
    begin
      perform public.costtrack_set_profile_account_status(
        role_fixture.id,
        'Deactivated',
        admin_id,
        'Unauthorized acceptance attempt'
      );
    exception when insufficient_privilege then
      denied := true;
    end;
    if not denied then
      raise exception 'FAIL: % account-status RPC was not denied.', role_fixture.role;
    end if;
  end loop;

  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', admin_id, 'role', 'authenticated')::text,
    true
  );
  denied := false;
  begin
    insert into public.profiles (id, email, full_name, role)
    values (
      gen_random_uuid(),
      'u1-admin-profile-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
      'Administrator Direct Insert',
      'Manager'
    );
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: an Administrator could create a profile outside the Edge Function.';
  end if;

  denied := false;
  begin
    update public.profiles
    set full_name = 'Unauthorized direct profile update'
    where id = admin_id;
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: an Administrator could update profile columns directly.';
  end if;

  denied := false;
  begin
    insert into public.user_invites (
      email, full_name, role, invited_by, expires_at
    ) values (
      'u1-admin-invite-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
      'Administrator Direct Invite',
      'Manager',
      admin_id,
      clock_timestamp() + interval '7 days'
    );
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: an Administrator could create an invitation outside the Edge Function.';
  end if;
end;
$$;

reset role;

do $$
declare
  admin_id uuid := current_setting('costtrack.test.admin_id')::uuid;
  target_id uuid;
  target_role text;
  changed boolean;
  denied boolean;
  test_invitation_id uuid;
  new_expiry timestamptz;
  old_expiry timestamptz;
begin
  select id, role
  into target_id, target_role
  from public.profiles
  where role in (
    'Manager',
    'Receptionist',
    'Inventory Clerk',
    'Chef / Kitchen Staff'
  )
    and account_status = 'Active'
  order by id
  limit 1;

  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', admin_id, 'role', 'authenticated')::text,
    true
  );

  denied := false;
  begin
    perform public.costtrack_update_profile_role(
      target_id,
      case when target_role = 'Manager' then 'Receptionist' else 'Manager' end,
      ' '
    );
  exception when invalid_parameter_value then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: a blank role-change reason was accepted.';
  end if;

  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  denied := false;
  begin
    perform public.costtrack_update_profile_role(
      admin_id,
      'Manager',
      'Self-demotion acceptance attempt'
    );
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: an Administrator could demote their own account.';
  end if;

  changed := public.costtrack_update_profile_role(
    target_id,
    case when target_role = 'Manager' then 'Receptionist' else 'Manager' end,
    'Acceptance role change'
  );
  if not changed or not exists (
    select 1
    from public.profiles
    where id = target_id
      and role = case when target_role = 'Manager' then 'Receptionist' else 'Manager' end
  ) then
    raise exception 'FAIL: an authorized role change was not applied.';
  end if;
  if not exists (
    select 1 from public.profile_role_audit
    where user_id = target_id
      and changed_by = admin_id
      and reason = 'Acceptance role change'
  ) then
    raise exception 'FAIL: the role change and reason were not audited.';
  end if;

  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', admin_id, 'role', 'service_role')::text,
    true
  );

  denied := false;
  begin
    perform public.costtrack_set_profile_account_status(
      admin_id,
      'Deactivated',
      admin_id,
      'Self-deactivation acceptance attempt'
    );
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: an Administrator could deactivate their own account.';
  end if;

  denied := false;
  begin
    perform public.costtrack_set_profile_account_status(
      target_id,
      'Deactivated',
      admin_id,
      ' '
    );
  exception when invalid_parameter_value then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: a blank deactivation reason was accepted.';
  end if;

  changed := public.costtrack_set_profile_account_status(
    target_id,
    'Deactivated',
    admin_id,
    'Acceptance deactivation'
  );
  if not changed or not exists (
    select 1 from public.profiles
    where id = target_id and account_status = 'Deactivated'
  ) then
    raise exception 'FAIL: an authorized deactivation was not applied.';
  end if;
  changed := public.costtrack_set_profile_account_status(
    target_id,
    'Active',
    admin_id,
    'Acceptance reactivation'
  );
  if not changed or not exists (
    select 1 from public.profiles
    where id = target_id and account_status = 'Active'
  ) then
    raise exception 'FAIL: an authorized reactivation was not applied.';
  end if;
  if not exists (
    select 1 from public.profile_account_status_audit
    where user_id = target_id
      and changed_by = admin_id
      and old_status = 'Active'
      and new_status = 'Deactivated'
      and reason = 'Acceptance deactivation'
  ) then
    raise exception 'FAIL: deactivation and its reason were not audited.';
  end if;
  if not exists (
    select 1 from public.profile_account_status_audit
    where user_id = target_id
      and changed_by = admin_id
      and old_status = 'Deactivated'
      and new_status = 'Active'
      and reason = 'Acceptance reactivation'
  ) then
    raise exception 'FAIL: reactivation and its reason were not audited.';
  end if;

  denied := false;
  begin
    update public.profile_role_audit
    set reason = 'Mutated acceptance audit'
    where user_id = target_id;
  exception when object_not_in_prerequisite_state then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: role audit records were mutable.';
  end if;

  denied := false;
  begin
    delete from public.profile_account_status_audit
    where user_id = target_id;
  exception when object_not_in_prerequisite_state then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: account-status audit records were deletable.';
  end if;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', admin_id, 'role', 'authenticated')::text,
    true
  );
  changed := public.costtrack_update_profile_role(
    target_id,
    'Administrator',
    'Acceptance last-admin fixture'
  );
  if not changed then
    raise exception 'FAIL: could not create the temporary last-admin fixture.';
  end if;
  update public.profile_admin_guard
  set administrator_count = 1
  where singleton;

  denied := false;
  begin
    perform public.costtrack_update_profile_role(
      target_id,
      'Manager',
      'Last-admin demotion acceptance attempt'
    );
  exception when check_violation then
    denied := true;
  end;
  if not denied or not exists (
    select 1 from public.profiles
    where id = target_id
      and role = 'Administrator'
      and account_status = 'Active'
  ) then
    raise exception 'FAIL: the last active Administrator could be demoted.';
  end if;

  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', admin_id, 'role', 'service_role')::text,
    true
  );
  denied := false;
  begin
    perform public.costtrack_set_profile_account_status(
      target_id,
      'Deactivated',
      admin_id,
      'Last-admin deactivation acceptance attempt'
    );
  exception when check_violation then
    denied := true;
  end;
  if not denied or not exists (
    select 1 from public.profiles
    where id = target_id
      and role = 'Administrator'
      and account_status = 'Active'
  ) then
    raise exception 'FAIL: the last active Administrator could be deactivated.';
  end if;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', admin_id, 'role', 'authenticated')::text,
    true
  );
  denied := false;
  begin
    delete from public.profiles where id = target_id;
  exception when object_not_in_prerequisite_state then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: the active Administrator profile could be deleted.';
  end if;

  update public.profile_admin_guard
  set administrator_count = (
    select count(*)::integer
    from public.profiles
    where role = 'Administrator'
      and account_status = 'Active'
  )
  where singleton;

  insert into public.user_invites (
    email, full_name, role, invited_by, expires_at
  ) values (
    'u1-lifecycle-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
    'U1 Lifecycle',
    'Manager',
    admin_id,
    clock_timestamp() + interval '1 second'
  )
  returning id, expires_at into test_invitation_id, old_expiry;

  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', admin_id, 'role', 'service_role')::text,
    true
  );
  if not public.costtrack_record_user_invitation_sent(test_invitation_id, admin_id) then
    raise exception 'FAIL: the initial sent event was not recorded.';
  end if;
  perform pg_sleep(1.1);
  update public.user_invites
  set status = 'Expired'
  where id = test_invitation_id
    and status = 'Pending';
  if not found then
    raise exception 'FAIL: the expired invitation fixture could not be marked Expired.';
  end if;

  new_expiry := public.costtrack_resend_user_invitation(test_invitation_id, admin_id);
  if new_expiry <= old_expiry or not exists (
    select 1 from public.user_invites
    where id = test_invitation_id
      and status = 'Pending'
      and expires_at = new_expiry
      and expires_at > clock_timestamp()
  ) then
    raise exception 'FAIL: resend did not restore Pending status and refresh expiry.';
  end if;

  denied := false;
  begin
    insert into public.user_invites (
      email, full_name, role, invited_by, expires_at
    )
    select email, 'Duplicate', 'Manager', admin_id, clock_timestamp() + interval '7 days'
    from public.user_invites
    where id = test_invitation_id;
  exception when unique_violation then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: a second active pending invitation for the same email was accepted.';
  end if;

  if (
    select count(*) from public.user_invitation_audit
    where user_invitation_audit.invitation_id = test_invitation_id
      and action in ('Sent', 'Resent')
  ) <> 2 then
    raise exception 'FAIL: sent and resent events were not both audited.';
  end if;
  if not exists (
    select 1 from public.user_invitation_audit
    where user_invitation_audit.invitation_id = test_invitation_id
      and action = 'Resent'
      and old_status = 'Expired'
      and new_status = 'Pending'
      and actor_id = admin_id
  ) then
    raise exception 'FAIL: resend audit did not record its actor and status transition.';
  end if;

  perform public.costtrack_cancel_user_invitation(test_invitation_id, admin_id);
  if not exists (
    select 1 from public.user_invites
    where id = test_invitation_id and status = 'Cancelled'
  ) or not exists (
    select 1 from public.user_invitation_audit
    where user_invitation_audit.invitation_id = test_invitation_id
      and action = 'Cancelled'
      and old_status = 'Pending'
      and new_status = 'Cancelled'
      and actor_id = admin_id
  ) then
    raise exception 'FAIL: cancellation status and audit event were not recorded.';
  end if;

  denied := false;
  begin
    perform public.costtrack_resend_user_invitation(test_invitation_id, admin_id);
  exception when object_not_in_prerequisite_state then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: a cancelled invitation could be resent.';
  end if;

  denied := false;
  begin
    update public.user_invitation_audit
    set action = 'Sent'
    where user_invitation_audit.invitation_id = test_invitation_id;
  exception when object_not_in_prerequisite_state then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: invitation audit records were mutable.';
  end if;
end;
$$;

select 'PASS: U1 authorization, required reasons, last-active-Administrator safeguards, resend lifecycle, and audit checks' as acceptance_result;
rollback;
