begin;

create table if not exists public.user_invites (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  full_name text not null,
  role text not null check (role in (
    'Administrator',
    'Manager',
    'Receptionist',
    'Inventory Clerk',
    'Chef / Kitchen Staff'
  )),
  status text not null default 'Pending'
    check (status in ('Pending', 'Accepted', 'Expired', 'Cancelled')),
  invited_by uuid not null
    references public.profiles (id) on delete restrict,
  invited_at timestamptz not null default clock_timestamp(),
  accepted_at timestamptz,
  expires_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint user_invites_email_valid check (
    char_length(email) between 3 and 254
    and char_length(split_part(email, '@', 1)) between 1 and 64
    and email = lower(btrim(email))
    and email ~ $invite_email$^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?([.][a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$invite_email$
  ),
  constraint user_invites_full_name_valid check (
    char_length(btrim(full_name)) between 1 and 160
  ),
  constraint user_invites_expiry_after_invite check (expires_at > invited_at),
  constraint user_invites_accepted_at_matches_status check (
    (status = 'Accepted' and accepted_at is not null)
    or (status <> 'Accepted' and accepted_at is null)
  )
);

create unique index if not exists user_invites_one_pending_per_email_uidx
  on public.user_invites (email)
  where status = 'Pending';
create index if not exists user_invites_status_invited_at_idx
  on public.user_invites (status, invited_at desc);

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

revoke all on function public.guard_user_invite() from public, anon, authenticated;

drop trigger if exists user_invites_guard on public.user_invites;
create trigger user_invites_guard
  before insert or update or delete on public.user_invites
  for each row execute function public.guard_user_invite();

drop trigger if exists user_invites_touch_updated_at on public.user_invites;
create trigger user_invites_touch_updated_at
  before update on public.user_invites
  for each row execute function public.touch_updated_at();

alter table public.user_invites enable row level security;
revoke all on table public.user_invites from public, anon, authenticated;
grant select, insert, update on table public.user_invites to authenticated;

do $$
declare
  policy_name text;
begin
  for policy_name in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'user_invites'
  loop
    execute format('drop policy if exists %I on public.user_invites', policy_name);
  end loop;
end;
$$;

create policy user_invites_admin_select
  on public.user_invites for select to authenticated
  using (public.has_app_role(array['Administrator']));

create policy user_invites_admin_insert
  on public.user_invites for insert to authenticated
  with check (public.has_app_role(array['Administrator']));

create policy user_invites_admin_update
  on public.user_invites for update to authenticated
  using (public.has_app_role(array['Administrator']))
  with check (public.has_app_role(array['Administrator']));

commit;
