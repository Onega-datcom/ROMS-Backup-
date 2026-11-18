begin;

create table if not exists public.notification_read_states (
  target_role text not null check (target_role in (
    'Administrator', 'Manager', 'Receptionist', 'Inventory Clerk',
    'Chef / Kitchen Staff'
  )),
  notification_key text not null check (
    length(notification_key) between 1 and 300
  ),
  read_at timestamptz not null default clock_timestamp(),
  read_by uuid references auth.users (id) on delete set null,
  primary key (target_role, notification_key)
);

alter table public.notification_read_states enable row level security;
drop policy if exists notification_read_states_role_read
  on public.notification_read_states;
create policy notification_read_states_role_read
  on public.notification_read_states for select to authenticated
  using (
    target_role = public.current_app_role()
    and public.has_app_role(array[
      'Administrator', 'Manager', 'Receptionist', 'Inventory Clerk',
      'Chef / Kitchen Staff'
    ])
  );
revoke all on table public.notification_read_states
  from public, anon, authenticated;
grant select on table public.notification_read_states to authenticated;

create or replace function public.costtrack_notification_read_keys()
returns text[]
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if not public.has_app_role(array[
    'Administrator', 'Manager', 'Receptionist', 'Inventory Clerk',
    'Chef / Kitchen Staff'
  ]) then
    raise exception 'Your role cannot read notification state.'
      using errcode = '42501';
  end if;
  return coalesce(
    array(
      select state.notification_key
      from public.notification_read_states as state
      where state.target_role = public.current_app_role()
      order by state.read_at desc
    ),
    array[]::text[]
  );
end;
$$;

create or replace function public.costtrack_mark_notifications_read(
  p_notification_keys text[]
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  role_value text;
  normalized_keys text[];
  pos_keys text[];
  other_keys text[];
  pos_count integer := 0;
  state_count integer := 0;
begin
  if not public.has_app_role(array[
    'Administrator', 'Manager', 'Receptionist', 'Inventory Clerk',
    'Chef / Kitchen Staff'
  ]) then
    raise exception 'Your role cannot mark notifications read.'
      using errcode = '42501';
  end if;
  if coalesce(cardinality(p_notification_keys), 0) = 0 then
    return 0;
  end if;
  if cardinality(p_notification_keys) > 500 then
    raise exception 'Mark at most 500 notifications read at a time.'
      using errcode = '22023';
  end if;

  select coalesce(
    array_agg(distinct nullif(btrim(keys.notification_key), ''))
      filter (where nullif(btrim(keys.notification_key), '') is not null),
    array[]::text[]
  )
  into normalized_keys
  from unnest(p_notification_keys) as keys(notification_key);
  if exists (
    select 1 from unnest(normalized_keys) as keys(notification_key)
    where length(keys.notification_key) > 300
  ) then
    raise exception 'A notification key is too long.' using errcode = '22023';
  end if;

  role_value := public.current_app_role();
  select coalesce(array_agg(keys.notification_key), array[]::text[])
  into pos_keys
  from unnest(normalized_keys) as keys(notification_key)
  where left(keys.notification_key, 4) = 'pos:';
  select coalesce(array_agg(keys.notification_key), array[]::text[])
  into other_keys
  from unnest(normalized_keys) as keys(notification_key)
  where left(keys.notification_key, 4) <> 'pos:';

  if cardinality(pos_keys) > 0
     and role_value not in ('Administrator', 'Manager') then
    raise exception 'Only Managers and Administrators may mark POS notifications read.'
      using errcode = '42501';
  end if;
  if cardinality(pos_keys) > 0 then
    update public.pos_notifications
    set read_at = coalesce(read_at, clock_timestamp())
    where target_role = role_value
      and ('pos:' || id) = any(pos_keys);
    get diagnostics pos_count = row_count;
  end if;

  insert into public.notification_read_states (
    target_role, notification_key, read_by
  )
  select role_value, keys.notification_key, auth.uid()
  from unnest(other_keys) as keys(notification_key)
  on conflict (target_role, notification_key) do nothing;
  get diagnostics state_count = row_count;
  return pos_count + state_count;
end;
$$;

revoke all on function public.costtrack_notification_read_keys()
  from public, anon, authenticated;
revoke all on function public.costtrack_mark_notifications_read(text[])
  from public, anon, authenticated;
grant execute on function public.costtrack_notification_read_keys()
  to authenticated;
grant execute on function public.costtrack_mark_notifications_read(text[])
  to authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'inventory_batches', 'notifications', 'notification_read_states', 'pos_notifications',
    'pos_shifts', 'pos_bills', 'pos_bill_approvals',
    'pos_reservation_deposits'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end;
$$;

commit;
