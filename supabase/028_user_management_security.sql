begin;

lock table public.profiles in share row exclusive mode;

create table if not exists public.profile_admin_guard (
  singleton boolean primary key default true check (singleton),
  administrator_count integer not null check (administrator_count >= 0)
);

alter table public.profile_admin_guard enable row level security;
revoke all on table public.profile_admin_guard from public, anon, authenticated;

insert into public.profile_admin_guard (singleton, administrator_count)
select true, count(*)::integer
from public.profiles
where role = 'Administrator'
on conflict (singleton) do update
set administrator_count = excluded.administrator_count;

create table if not exists public.profile_role_audit (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  old_role text not null,
  new_role text not null,
  changed_by uuid references auth.users (id) on delete set null,
  changed_at timestamptz not null default clock_timestamp(),
  reason text not null default '' check (char_length(reason) <= 500)
);

alter table public.profile_role_audit enable row level security;
revoke all on table public.profile_role_audit from public, anon, authenticated;
grant select on table public.profile_role_audit to authenticated;
drop policy if exists profile_role_audit_admin_read on public.profile_role_audit;
create policy profile_role_audit_admin_read
  on public.profile_role_audit for select to authenticated
  using (public.has_app_role(array['Administrator']));

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

drop trigger if exists prevent_self_role_change on public.profiles;
create trigger prevent_self_role_change
  before insert or update or delete on public.profiles
  for each row execute function public.prevent_self_role_change();

create or replace function public.audit_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if old.role is distinct from new.role then
    insert into public.profile_role_audit (
      user_id, old_role, new_role, changed_by, reason
    ) values (
      old.id,
      old.role,
      new.role,
      auth.uid(),
      coalesce(nullif(btrim(current_setting('costtrack.role_change_reason', true)), ''), '')
    );
  end if;
  return new;
end;
$$;

drop trigger if exists audit_profile_role_change on public.profiles;
create trigger audit_profile_role_change
  after update on public.profiles
  for each row
  when (old.role is distinct from new.role)
  execute function public.audit_profile_role_change();

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

  if p_user_id = auth.uid() then
    raise exception 'Users cannot change their own role'
      using errcode = '42501';
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

revoke all on function public.prevent_self_role_change() from public, anon, authenticated;
revoke all on function public.audit_profile_role_change() from public, anon, authenticated;
revoke all on function public.costtrack_update_profile_role(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.costtrack_update_profile_role(uuid, text, text)
  to authenticated;

drop policy if exists profiles_admin_update on public.profiles;
drop policy if exists profiles_admin_delete on public.profiles;
revoke update, delete on table public.profiles from public, anon, authenticated;

commit;
