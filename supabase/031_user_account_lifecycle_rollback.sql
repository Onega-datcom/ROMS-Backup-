begin;

do $$
begin
  if exists (
    select 1
    from public.profiles
    where account_status <> 'Active'
  ) then
    raise exception 'Rollback blocked: resolve all Pending, Deactivated, and Cancelled profiles before rolling back account lifecycle.';
  end if;
end;
$$;

drop policy if exists profile_account_status_audit_admin_read
  on public.profile_account_status_audit;
drop table public.profile_account_status_audit;

drop function public.costtrack_set_profile_account_status(uuid, text, uuid, text);
drop function public.costtrack_accept_user_invitation(uuid, uuid);
drop function public.costtrack_cancel_user_invitation(uuid, uuid);

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

    if old.role = 'Administrator' and new.role is distinct from old.role then
      update public.profile_admin_guard
      set administrator_count = administrator_count - 1
      where singleton and administrator_count > 1;
      if not found then
        if exists (
          select 1 from public.profile_admin_guard where singleton
        ) then
          raise exception 'Cannot remove or demote the last Administrator'
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
      and old.role <> 'Administrator'
      and new.role = 'Administrator' then
      update public.profile_admin_guard
      set administrator_count = administrator_count + 1
      where singleton;
      if not found then
        raise exception 'Administrator protection state is unavailable'
          using errcode = '55000';
      end if;
    end if;
    return new;
  elsif tg_op = 'INSERT' then
    if new.role = 'Administrator' then
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
    if old.role = 'Administrator'
      and exists (
        select 1
        from public.profile_admin_guard
        where singleton and administrator_count <= 1
      ) then
      raise exception 'Cannot delete the last Administrator; profile deletion is not supported'
        using errcode = '55000';
    end if;
    raise exception 'Profile deletion is not supported'
      using errcode = '55000';
  end if;
  raise exception 'Unsupported profiles operation: %', tg_op
    using errcode = '55000';
end;
$$;

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
    for share;
    if inviter_role is distinct from 'Administrator' then
      raise exception 'The inviter must be an existing Administrator'
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
    if old.status <> 'Pending'
      and new.expires_at is distinct from old.expires_at then
      raise exception 'A completed invitation expiry cannot be changed'
        using errcode = '55000';
    end if;
    if new.status is distinct from old.status then
      if old.status <> 'Pending' then
        raise exception 'A completed invitation cannot change status'
          using errcode = '55000';
      end if;
      if new.status = 'Accepted' then
        if old.expires_at <= clock_timestamp() then
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
        if old.expires_at > clock_timestamp() then
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

drop policy if exists user_invites_admin_insert on public.user_invites;
drop policy if exists user_invites_admin_update on public.user_invites;
create policy user_invites_admin_insert
  on public.user_invites for insert to authenticated
  with check (public.has_app_role(array['Administrator']));
create policy user_invites_admin_update
  on public.user_invites for update to authenticated
  using (public.has_app_role(array['Administrator']))
  with check (public.has_app_role(array['Administrator']));
grant select, insert, update on table public.user_invites to authenticated;

update public.profile_admin_guard
set administrator_count = (
  select count(*)::integer
  from public.profiles
  where role = 'Administrator'
)
where singleton;

alter table public.profiles drop column account_status;

commit;
