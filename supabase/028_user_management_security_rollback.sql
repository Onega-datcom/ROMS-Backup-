begin;

-- This rollback restores direct Administrator profile updates and deletes.
-- It intentionally retains profile_role_audit and its audit trigger so history is not lost.
drop trigger if exists prevent_self_role_change on public.profiles;

create or replace function public.prevent_self_role_change()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if auth.uid() = old.id and new.role is distinct from old.role then
    raise exception 'Users cannot change their own role';
  end if;
  return new;
end;
$$;

create trigger prevent_self_role_change
  before update on public.profiles
  for each row execute function public.prevent_self_role_change();

drop function if exists public.costtrack_update_profile_role(uuid, text, text);
drop table if exists public.profile_admin_guard;

create policy profiles_admin_update
  on public.profiles for update to authenticated
  using (public.has_app_role(array['Administrator']))
  with check (public.has_app_role(array['Administrator']));
create policy profiles_admin_delete
  on public.profiles for delete to authenticated
  using (public.has_app_role(array['Administrator']));
grant update, delete on table public.profiles to authenticated;

commit;
