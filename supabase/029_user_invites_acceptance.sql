-- Run as the database owner after migration 029.
-- Requires one Administrator and one Manager profile. All test rows are rolled back.
begin;

do $$
declare
  admin_id uuid;
  manager_id uuid;
  admin_email text;
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
  select email into admin_email
  from public.profiles
  where id = admin_id;

  if admin_id is null or manager_id is null then
    raise exception 'FAIL: provision one Administrator and one Manager profile first.';
  end if;

  perform set_config('costtrack.test.invite_admin_id', admin_id::text, true);
  perform set_config('costtrack.test.invite_manager_id', manager_id::text, true);
  perform set_config('costtrack.test.invite_admin_email', admin_email, true);
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
  admin_id uuid := current_setting('costtrack.test.invite_admin_id')::uuid;
  manager_id uuid := current_setting('costtrack.test.invite_manager_id')::uuid;
  admin_email text := current_setting('costtrack.test.invite_admin_email');
  valid_email text := 'phase2-' || replace(gen_random_uuid()::text, '-', '') || '@example.test';
  cancel_email text := 'phase2-cancel-' || replace(gen_random_uuid()::text, '-', '') || '@example.test';
  expired_email text := 'phase2-expired-' || replace(gen_random_uuid()::text, '-', '') || '@example.test';
  active_email text := 'phase2-active-' || replace(gen_random_uuid()::text, '-', '') || '@example.test';
  invite_id uuid;
  cancel_id uuid;
  expired_id uuid;
  active_id uuid;
  denied boolean;
  affected_rows integer;
begin
  insert into public.user_invites (
    email, full_name, role, invited_by, expires_at
  ) values (
    '  ' || upper(valid_email) || '  ',
    '  Phase 2 Invitee  ',
    'Receptionist',
    admin_id,
    clock_timestamp() + interval '7 days'
  )
  returning id into invite_id;

  if not exists (
    select 1
    from public.user_invites
    where id = invite_id
      and email = valid_email
      and full_name = 'Phase 2 Invitee'
      and role = 'Receptionist'
      and status = 'Pending'
      and invited_by = admin_id
      and accepted_at is null
  ) then
    raise exception 'FAIL: valid invitation was not normalized or stored correctly.';
  end if;

  denied := false;
  begin
    insert into public.user_invites (
      email, full_name, role, invited_by, expires_at
    ) values (
      'not-an-email', 'Invalid Email', 'Manager', admin_id,
      clock_timestamp() + interval '7 days'
    );
  exception when check_violation then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: invalid email was accepted.';
  end if;

  denied := false;
  begin
    insert into public.user_invites (
      email, full_name, role, invited_by, expires_at
    ) values (
      'phase2-invalid-role-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
      'Invalid Role', 'Customer', admin_id, clock_timestamp() + interval '7 days'
    );
  exception when check_violation then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: a non-staff role was accepted.';
  end if;

  denied := false;
  begin
    insert into public.user_invites (
      email, full_name, role, invited_by, expires_at
    ) values (
      'phase2-invalid-inviter-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
      'Invalid Inviter', 'Manager', manager_id, clock_timestamp() + interval '7 days'
    );
  exception when insufficient_privilege then
    if position('inviter must be an existing administrator' in lower(sqlerrm)) = 0 then
      raise exception 'FAIL: invalid inviter rejected unexpectedly: %', sqlerrm;
    end if;
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: a non-Administrator inviter was accepted.';
  end if;

  denied := false;
  begin
    insert into public.user_invites (
      email, full_name, role, invited_by, expires_at
    ) values (
      admin_email, 'Existing Profile', 'Manager', admin_id,
      clock_timestamp() + interval '7 days'
    );
  exception when unique_violation then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: an invitation was created for an existing profile email.';
  end if;

  denied := false;
  begin
    insert into public.user_invites (
      email, full_name, role, status, invited_by, expires_at
    ) values (
      'phase2-invalid-status-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
      'Invalid Status', 'Manager', 'Accepted', admin_id,
      clock_timestamp() + interval '7 days'
    );
  exception when check_violation then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: an invitation was inserted in a non-Pending state.';
  end if;

  denied := false;
  begin
    insert into public.user_invites (
      email, full_name, role, invited_by, expires_at
    ) values (
      valid_email, 'Duplicate Invite', 'Manager', admin_id,
      clock_timestamp() + interval '7 days'
    );
  exception when unique_violation then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: duplicate pending invitations for one email were accepted.';
  end if;

  update public.user_invites
  set status = 'Accepted'
  where id = invite_id;

  if not exists (
    select 1
    from public.user_invites
    where id = invite_id
      and status = 'Accepted'
      and accepted_at is not null
  ) then
    raise exception 'FAIL: accepting an invitation did not set accepted_at.';
  end if;

  denied := false;
  begin
    update public.user_invites
    set status = 'Pending'
    where id = invite_id;
  exception when object_not_in_prerequisite_state then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: a completed invitation was reopened.';
  end if;

  denied := false;
  begin
    update public.user_invites
    set email = 'phase2-mutated-' || replace(gen_random_uuid()::text, '-', '') || '@example.test'
    where id = invite_id;
  exception when object_not_in_prerequisite_state then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: invitation identity fields were mutable.';
  end if;

  denied := false;
  begin
    update public.user_invites
    set accepted_at = null
    where id = invite_id;
  exception when object_not_in_prerequisite_state then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: accepted_at could be changed independently of status.';
  end if;

  insert into public.user_invites (
    email, full_name, role, invited_by, expires_at
  ) values (
    expired_email, 'Expired Invite', 'Manager', admin_id,
    clock_timestamp() + interval '2 seconds'
  )
  returning id into expired_id;

  perform pg_sleep(2.1);
  denied := false;
  begin
    update public.user_invites
    set status = 'Accepted'
    where id = expired_id;
  exception when check_violation then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: an expired invitation was accepted.';
  end if;

  update public.user_invites
  set status = 'Expired'
  where id = expired_id;

  if not exists (
    select 1
    from public.user_invites
    where id = expired_id and status = 'Expired' and accepted_at is null
  ) then
    raise exception 'FAIL: an already-expired invitation could not be marked Expired.';
  end if;

  insert into public.user_invites (
    email, full_name, role, invited_by, expires_at
  ) values (
    active_email, 'Active Invite', 'Manager', admin_id,
    clock_timestamp() + interval '7 days'
  )
  returning id into active_id;

  denied := false;
  begin
    update public.user_invites
    set status = 'Expired'
    where id = active_id;
  exception when check_violation then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: an invitation was marked Expired before expires_at.';
  end if;

  insert into public.user_invites (
    email, full_name, role, invited_by, expires_at
  ) values (
    cancel_email, 'Cancelled Invite', 'Inventory Clerk', admin_id,
    clock_timestamp() + interval '7 days'
  )
  returning id into cancel_id;

  update public.user_invites
  set status = 'Cancelled'
  where id = cancel_id;

  if not exists (
    select 1
    from public.user_invites
    where id = cancel_id and status = 'Cancelled' and accepted_at is null
  ) then
    raise exception 'FAIL: a pending invitation could not be cancelled.';
  end if;

  denied := false;
  begin
    delete from public.user_invites where id = invite_id;
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: an Administrator was allowed to delete invitation history.';
  end if;

  perform set_config('request.jwt.claim.sub', manager_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', manager_id::text, 'role', 'authenticated')::text,
    true
  );

  if exists (
    select 1 from public.user_invites where id = invite_id
  ) then
    raise exception 'FAIL: a non-Administrator read invitation data.';
  end if;

  denied := false;
  begin
    insert into public.user_invites (
      email, full_name, role, invited_by, expires_at
    ) values (
      'phase2-unauthorized-' || replace(gen_random_uuid()::text, '-', '') || '@example.test',
      'Unauthorized Invite', 'Manager', admin_id,
      clock_timestamp() + interval '7 days'
    );
  exception when insufficient_privilege then
    denied := true;
  end;
  if not denied then
    raise exception 'FAIL: a non-Administrator created an invitation.';
  end if;

  update public.user_invites
  set status = 'Cancelled'
  where id = invite_id;
  get diagnostics affected_rows = row_count;
  if affected_rows <> 0 then
    raise exception 'FAIL: a non-Administrator updated an invitation.';
  end if;
end;
$$;

select 'PASS: invite validation, lifecycle, RLS, and history protections' as acceptance_result;
rollback;
