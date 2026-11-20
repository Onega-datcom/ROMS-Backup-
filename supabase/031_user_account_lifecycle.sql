begin;

alter table public.profiles
  add column if not exists account_status text not null default 'Active';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_account_status_check'
  ) then
    alter table public.profiles
      add constraint profiles_account_status_check
      check (account_status in ('Pending', 'Active', 'Deactivated', 'Cancelled'));
  end if;
end;
$$;

update public.profiles as profile
set account_status = case
  when exists (
    select 1
    from public.user_invites as accepted_invite
    where lower(accepted_invite.email) = lower(profile.email)
      and accepted_invite.status = 'Accepted'
  ) then 'Active'
  when (
    select latest_invite.status
    from public.user_invites as latest_invite
    where lower(latest_invite.email) = lower(profile.email)
    order by latest_invite.invited_at desc, latest_invite.id desc
    limit 1
  ) in ('Pending', 'Expired') then 'Pending'
  when (
    select latest_invite.status
    from public.user_invites as latest_invite
    where lower(latest_invite.email) = lower(profile.email)
    order by latest_invite.invited_at desc, latest_invite.id desc
    limit 1
  ) = 'Cancelled' then 'Cancelled'
  else 'Active'
end;

update public.profile_admin_guard
set administrator_count = (
  select count(*)::integer
  from public.profiles
  where role = 'Administrator'
    and account_status = 'Active'
)
where singleton;

create table if not exists public.profile_account_status_audit (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  old_status text not null check (
    old_status in ('Pending', 'Active', 'Deactivated', 'Cancelled')
  ),
  new_status text not null check (
    new_status in ('Pending', 'Active', 'Deactivated', 'Cancelled')
  ),
  changed_by uuid references auth.users (id) on delete set null,
  invitation_id uuid references public.user_invites (id) on delete restrict,
  changed_at timestamptz not null default clock_timestamp(),
  reason text not null default '' check (char_length(reason) <= 500)
);

alter table public.profile_account_status_audit enable row level security;
revoke all on table public.profile_account_status_audit from public, anon, authenticated;
grant select on table public.profile_account_status_audit to authenticated;
drop policy if exists profile_account_status_audit_admin_read
  on public.profile_account_status_audit;
create policy profile_account_status_audit_admin_read
  on public.profile_account_status_audit for select to authenticated
  using (public.has_app_role(array['Administrator']));

drop policy if exists user_invites_admin_update on public.user_invites;
drop policy if exists user_invites_admin_insert on public.user_invites;
revoke insert, update on table public.user_invites from authenticated;

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select profile.role
  from public.profiles as profile
  where profile.id = auth.uid()
    and profile.account_status = 'Active'
$$;

create or replace function public.has_app_role(allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.profiles as profile
    where profile.id = auth.uid()
      and profile.account_status = 'Active'
      and profile.role = any (allowed_roles)
  )
$$;

create or replace function public.prevent_self_role_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'UPDATE' then
    if auth.uid() = old.id and new.role is distinct from old.role then
      raise exception 'Users cannot change their own role'
        using errcode = '42501';
    end if;

    if new.account_status is distinct from old.account_status
      and (
        auth.role() is distinct from 'service_role'
        or current_setting('costtrack.account_status_change', true) is distinct from 'on'
      ) then
      raise exception 'User account status must be changed through the authorized lifecycle workflow'
        using errcode = '42501';
    end if;

    if old.role = 'Administrator' and new.role is distinct from old.role
      and old.account_status = 'Active' then
      update public.profile_admin_guard
      set administrator_count = administrator_count - 1
      where singleton and administrator_count > 1;

      if not found then
        if exists (
          select 1 from public.profile_admin_guard where singleton
        ) then
          raise exception 'Cannot remove or demote the last active Administrator'
            using errcode = '23514';
        end if;
        raise exception 'Administrator protection state is unavailable'
          using errcode = '55000';
      end if;
    end if;

    if old.role is distinct from new.role then
      if auth.uid() is null
        or not coalesce(public.has_app_role(array['Administrator']), false) then
        raise exception 'Only Administrators may change user roles'
          using errcode = '42501';
      end if;
    end if;

    if old.role is distinct from new.role
      and new.role = 'Administrator'
      and new.account_status = 'Active' then
      update public.profile_admin_guard
      set administrator_count = administrator_count + 1
      where singleton;
      if not found then
        raise exception 'Administrator protection state is unavailable'
          using errcode = '55000';
      end if;
    end if;

    if old.role = 'Administrator'
      and new.role = old.role
      and old.account_status is distinct from new.account_status then
      if old.account_status = 'Active' then
        update public.profile_admin_guard
        set administrator_count = administrator_count - 1
        where singleton and administrator_count > 1;
        if not found then
          raise exception 'Cannot deactivate the last active Administrator'
            using errcode = '23514';
        end if;
      elsif new.account_status = 'Active' then
        update public.profile_admin_guard
        set administrator_count = administrator_count + 1
        where singleton;
        if not found then
          raise exception 'Administrator protection state is unavailable'
            using errcode = '55000';
        end if;
      end if;
    end if;

    return new;
  elsif tg_op = 'INSERT' then
    if new.role = 'Administrator' and new.account_status = 'Active' then
      update public.profile_admin_guard
      set administrator_count = administrator_count + 1
      where singleton;
      if not found then
        raise exception 'Administrator protection state is unavailable'
          using errcode = '55000';
      end if;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if old.account_status in ('Pending', 'Cancelled') then
      return old;
    end if;
    if old.role = 'Administrator'
      and old.account_status = 'Active'
      and exists (
        select 1
        from public.profile_admin_guard
        where singleton and administrator_count <= 1
      ) then
      raise exception 'Cannot delete the last active Administrator; profile deletion is not supported'
        using errcode = '55000';
    end if;
    raise exception 'Profile deletion is not supported for active or deactivated users'
      using errcode = '55000';
  end if;

  raise exception 'Unsupported profiles operation: %', tg_op
    using errcode = '55000';
end;
$$;

create or replace function public.costtrack_set_profile_account_status(
  p_user_id uuid,
  p_new_status text,
  p_actor_id uuid,
  p_reason text default ''
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  prior_status text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'This account operation requires the authorized server workflow'
      using errcode = '42501';
  end if;
  if p_user_id is null or p_actor_id is null
    or p_new_status not in ('Active', 'Deactivated')
    or char_length(btrim(coalesce(p_reason, ''))) > 500 then
    raise exception 'The account status request is invalid'
      using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.profiles as actor
    where actor.id = p_actor_id
      and actor.role = 'Administrator'
      and actor.account_status = 'Active'
  ) then
    raise exception 'Only active Administrators may manage user accounts'
      using errcode = '42501';
  end if;
  if p_new_status = 'Deactivated' and p_user_id = p_actor_id then
    raise exception 'Administrators cannot deactivate their own account'
      using errcode = '42501';
  end if;

  perform 1
  from public.profile_admin_guard
  where singleton
  for update;
  if not found then
    raise exception 'Administrator protection state is unavailable'
      using errcode = '55000';
  end if;

  select profile.account_status
  into prior_status
  from public.profiles as profile
  where profile.id = p_user_id
  for update;
  if not found then
    raise exception 'User profile not found'
      using errcode = 'P0002';
  end if;
  if prior_status not in ('Active', 'Deactivated') then
    raise exception 'Only active or deactivated staff accounts can change status'
      using errcode = '55000';
  end if;
  if prior_status = p_new_status then
    return false;
  end if;

  perform set_config('costtrack.account_status_change', 'on', true);
  update public.profiles
  set account_status = p_new_status,
      updated_at = clock_timestamp()
  where id = p_user_id;

  insert into public.profile_account_status_audit (
    user_id, old_status, new_status, changed_by, reason
  ) values (
    p_user_id,
    prior_status,
    p_new_status,
    p_actor_id,
    btrim(coalesce(p_reason, ''))
  );
  return true;
end;
$$;

create or replace function public.costtrack_update_profile_role(
  p_user_id uuid,
  p_new_role text,
  p_reason text default ''
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  existing_role text;
  previous_reason text;
begin
  if auth.uid() is null
    or not coalesce(public.has_app_role(array['Administrator']), false) then
    raise exception 'Only Administrators may change user roles'
      using errcode = '42501';
  end if;
  if p_user_id is null then
    raise exception 'A user profile is required'
      using errcode = '22023';
  end if;
  if p_new_role is null or p_new_role not in (
    'Administrator',
    'Manager',
    'Receptionist',
    'Inventory Clerk',
    'Chef / Kitchen Staff'
  ) then
    raise exception 'The requested role is not a valid staff role'
      using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) > 500 then
    raise exception 'The role-change reason must be 500 characters or fewer'
      using errcode = '22023';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Users cannot change their own role'
      using errcode = '42501';
  end if;

  perform 1
  from public.profile_admin_guard
  where singleton
  for update;
  if not found then
    raise exception 'Administrator protection state is unavailable'
      using errcode = '55000';
  end if;

  select profile.role
  into existing_role
  from public.profiles as profile
  where profile.id = p_user_id
  for update;
  if not found then
    raise exception 'User profile not found'
      using errcode = 'P0002';
  end if;
  if existing_role = p_new_role then
    return false;
  end if;

  previous_reason := current_setting('costtrack.role_change_reason', true);
  perform set_config(
    'costtrack.role_change_reason',
    btrim(coalesce(p_reason, '')),
    true
  );
  update public.profiles
  set role = p_new_role
  where id = p_user_id;
  if not found then
    raise exception 'User profile was not updated'
      using errcode = 'P0002';
  end if;
  perform set_config(
    'costtrack.role_change_reason',
    coalesce(previous_reason, ''),
    true
  );
  return true;
end;
$$;

create or replace function public.costtrack_accept_user_invitation(
  p_invitation_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  invitation public.user_invites%rowtype;
  profile_status text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Invitation acceptance requires the authorized server workflow'
      using errcode = '42501';
  end if;
  if p_invitation_id is null or p_user_id is null then
    raise exception 'The invitation acceptance request is invalid'
      using errcode = '22023';
  end if;

  perform 1
  from public.profile_admin_guard
  where singleton
  for update;
  if not found then
    raise exception 'Administrator protection state is unavailable'
      using errcode = '55000';
  end if;

  select *
  into invitation
  from public.user_invites
  where id = p_invitation_id
  for update;
  if not found then
    raise exception 'Invitation not found'
      using errcode = 'P0002';
  end if;
  if invitation.status = 'Accepted' then
    return false;
  end if;
  if invitation.status <> 'Pending'
    or invitation.expires_at <= clock_timestamp() then
    raise exception 'Invitation is no longer pending or has expired'
      using errcode = '23514';
  end if;

  select profile.account_status
  into profile_status
  from public.profiles as profile
  where profile.id = p_user_id
    and lower(profile.email) = invitation.email
  for update;
  if not found or profile_status <> 'Pending' then
    raise exception 'The invited account is not pending acceptance'
      using errcode = '42501';
  end if;

  update public.user_invites
  set status = 'Accepted'
  where id = invitation.id
    and status = 'Pending';
  if not found then
    raise exception 'Invitation acceptance could not be recorded'
      using errcode = '40001';
  end if;

  perform set_config('costtrack.account_status_change', 'on', true);
  update public.profiles
  set account_status = 'Active',
      updated_at = clock_timestamp()
  where id = p_user_id;

  insert into public.profile_account_status_audit (
    user_id, old_status, new_status, changed_by, invitation_id, reason
  ) values (
    p_user_id,
    'Pending',
    'Active',
    p_user_id,
    invitation.id,
    'Invitation accepted'
  );
  return true;
end;
$$;

create or replace function public.costtrack_cancel_user_invitation(
  p_invitation_id uuid,
  p_actor_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  invitation public.user_invites%rowtype;
  target_user_id uuid;
  prior_status text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Invitation cancellation requires the authorized server workflow'
      using errcode = '42501';
  end if;
  if p_invitation_id is null or p_actor_id is null then
    raise exception 'The invitation cancellation request is invalid'
      using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.profiles as actor
    where actor.id = p_actor_id
      and actor.role = 'Administrator'
      and actor.account_status = 'Active'
  ) then
    raise exception 'Only active Administrators may cancel invitations'
      using errcode = '42501';
  end if;

  perform 1
  from public.profile_admin_guard
  where singleton
  for update;
  if not found then
    raise exception 'Administrator protection state is unavailable'
      using errcode = '55000';
  end if;

  select *
  into invitation
  from public.user_invites
  where id = p_invitation_id
  for update;
  if not found then
    raise exception 'Invitation not found'
      using errcode = 'P0002';
  end if;

  select profile.id, profile.account_status
  into target_user_id, prior_status
  from public.profiles as profile
  where lower(profile.email) = invitation.email
  for update;

  if invitation.status = 'Accepted' then
    raise exception 'An accepted invitation cannot be cancelled; deactivate the staff account instead'
      using errcode = '55000';
  end if;
  if invitation.status not in ('Pending', 'Expired', 'Cancelled') then
    raise exception 'This invitation cannot be cancelled'
      using errcode = '55000';
  end if;
  if prior_status in ('Active', 'Deactivated') then
    raise exception 'This invitation is linked to an existing staff account'
      using errcode = '55000';
  end if;

  if invitation.status <> 'Cancelled' then
    update public.user_invites
    set status = 'Cancelled'
    where id = invitation.id;
  end if;

  if target_user_id is not null and prior_status = 'Pending' then
    perform set_config('costtrack.account_status_change', 'on', true);
    update public.profiles
    set account_status = 'Cancelled',
        updated_at = clock_timestamp()
    where id = target_user_id;

    insert into public.profile_account_status_audit (
      user_id, old_status, new_status, changed_by, invitation_id, reason
    ) values (
      target_user_id,
      'Pending',
      'Cancelled',
      p_actor_id,
      invitation.id,
      'Invitation cancelled'
    );
  end if;
  return target_user_id;
end;
$$;

revoke all on function public.costtrack_set_profile_account_status(uuid, text, uuid, text)
  from public, anon, authenticated;
revoke all on function public.costtrack_accept_user_invitation(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.costtrack_cancel_user_invitation(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.costtrack_set_profile_account_status(uuid, text, uuid, text)
  to service_role;
grant execute on function public.costtrack_accept_user_invitation(uuid, uuid)
  to service_role;
grant execute on function public.costtrack_cancel_user_invitation(uuid, uuid)
  to service_role;

create or replace function public.guard_user_invite()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  inviter_role text;
begin
  if tg_op = 'INSERT' then
    new.email := lower(btrim(new.email));
    new.full_name := btrim(new.full_name);
    new.invited_at := clock_timestamp();
    new.created_at := new.invited_at;
    new.updated_at := new.invited_at;

    if new.status <> 'Pending' then
      raise exception 'New invitations must start as Pending'
        using errcode = '23514';
    end if;

    select profile.role
    into inviter_role
    from public.profiles as profile
    where profile.id = new.invited_by
      and profile.account_status = 'Active'
    for share;

    if inviter_role is distinct from 'Administrator' then
      raise exception 'The inviter must be an active Administrator'
        using errcode = '42501';
    end if;

    if exists (
      select 1
      from public.profiles as profile
      where lower(profile.email) = new.email
    ) then
      raise exception 'A profile already exists for this email address'
        using errcode = '23505';
    end if;
    return new;
  elsif tg_op = 'UPDATE' then
    if new.id is distinct from old.id
      or new.email is distinct from old.email
      or new.full_name is distinct from old.full_name
      or new.role is distinct from old.role
      or new.invited_by is distinct from old.invited_by
      or new.invited_at is distinct from old.invited_at
      or new.created_at is distinct from old.created_at then
      raise exception 'Invitation identity fields cannot be changed'
        using errcode = '55000';
    end if;
    if old.status not in ('Pending', 'Expired')
      and new.expires_at is distinct from old.expires_at then
      raise exception 'A completed invitation expiry cannot be changed'
        using errcode = '55000';
    end if;
    if new.status is distinct from old.status then
      if auth.role() is distinct from 'service_role' then
        raise exception 'Invitation status changes must use the authorized lifecycle workflow'
          using errcode = '42501';
      end if;
      if old.status not in ('Pending', 'Expired') then
        raise exception 'A completed invitation cannot change status'
          using errcode = '55000';
      end if;
      if new.status = 'Accepted' then
        if old.status <> 'Pending' or old.expires_at <= clock_timestamp() then
          raise exception 'An expired invitation cannot be accepted'
            using errcode = '23514';
        end if;
        new.accepted_at := clock_timestamp();
        if new.accepted_at < old.invited_at
          or new.accepted_at > clock_timestamp() then
          raise exception 'The acceptance timestamp is invalid'
            using errcode = '23514';
        end if;
      elsif new.status = 'Expired' then
        if old.status <> 'Pending' or old.expires_at > clock_timestamp() then
          raise exception 'An invitation cannot expire before its expiry time'
            using errcode = '23514';
        end if;
        new.accepted_at := null;
      elsif new.status = 'Cancelled' then
        new.accepted_at := null;
      else
        raise exception 'Unsupported invitation status transition'
          using errcode = '23514';
      end if;
    elsif new.accepted_at is distinct from old.accepted_at then
      raise exception 'Acceptance timestamps can only change with invitation status'
        using errcode = '55000';
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    raise exception 'Invitation records cannot be deleted; change their status instead'
      using errcode = '55000';
  end if;
  raise exception 'Unsupported user_invites operation: %', tg_op
    using errcode = '55000';
end;
$$;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;
end;
$$;

commit;
