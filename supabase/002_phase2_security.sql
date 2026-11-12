-- CostTrack Phase 2 live-data security migration.
-- Run as a database owner. No data or triggers are changed.

begin;

-- PHASE 2: ensure every application table is protected by RLS.
alter table public.profiles enable row level security;
alter table public.ingredients enable row level security;
alter table public.recipes enable row level security;
alter table public.recipe_ingredients enable row level security;
alter table public.inventory_transactions enable row level security;
alter table public.production_logs enable row level security;
alter table public.waste_logs enable row level security;
alter table public.physical_counts enable row level security;
alter table public.revenue_records enable row level security;
alter table public.reservations enable row level security;
alter table public.buffet_rates enable row level security;
alter table public.restaurant_tables enable row level security;
alter table public.audit_logs enable row level security;

do $$
declare
  policy_row record;
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = any (array[
        'profiles', 'ingredients', 'recipes', 'recipe_ingredients',
        'inventory_transactions', 'production_logs', 'waste_logs',
        'physical_counts', 'revenue_records', 'reservations',
        'buffet_rates', 'restaurant_tables', 'audit_logs'
      ])
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_row.policyname, policy_row.schemaname, policy_row.tablename
    );
  end loop;
end;
$$;

-- PHASE 2: profiles are self-readable; only administrators can manage users.
create policy profiles_self_read on public.profiles
  for select to authenticated using (id = auth.uid());
create policy profiles_admin_read on public.profiles
  for select to authenticated using (public.has_app_role(array['Administrator']));
create policy profiles_admin_insert on public.profiles
  for insert to authenticated
  with check (public.has_app_role(array['Administrator']));
create policy profiles_admin_update on public.profiles
  for update to authenticated
  using (public.has_app_role(array['Administrator']))
  with check (public.has_app_role(array['Administrator']));
create policy profiles_admin_delete on public.profiles
  for delete to authenticated using (public.has_app_role(array['Administrator']));

-- PHASE 2: ingredient costs are visible to every role with ingredient access.
create policy ingredients_read on public.ingredients
  for select to authenticated
  using (public.has_app_role(array[
    'Administrator', 'Manager', 'Chef / Kitchen Staff', 'Inventory Clerk'
  ]));
create policy ingredients_insert on public.ingredients
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));
create policy ingredients_update on public.ingredients
  for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']))
  with check (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));
create policy ingredients_delete on public.ingredients
  for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));

create policy recipes_read on public.recipes
  for select to authenticated
  using (public.has_app_role(array[
    'Administrator', 'Manager', 'Chef / Kitchen Staff', 'Inventory Clerk'
  ]));
create policy recipes_delete on public.recipes
  for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']));
create policy recipe_ingredients_read on public.recipe_ingredients
  for select to authenticated
  using (public.has_app_role(array[
    'Administrator', 'Manager', 'Chef / Kitchen Staff', 'Inventory Clerk'
  ]));

create policy inventory_transactions_read on public.inventory_transactions
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));
create policy inventory_transactions_insert on public.inventory_transactions
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));

create policy production_logs_read on public.production_logs
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']));
create policy production_logs_insert on public.production_logs
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']));

create policy waste_logs_read on public.waste_logs
  for select to authenticated
  using (public.has_app_role(array[
    'Administrator', 'Manager', 'Chef / Kitchen Staff', 'Inventory Clerk'
  ]));
create policy waste_logs_insert on public.waste_logs
  for insert to authenticated
  with check (public.has_app_role(array[
    'Administrator', 'Manager', 'Chef / Kitchen Staff', 'Inventory Clerk'
  ]));

create policy physical_counts_read on public.physical_counts
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));
create policy physical_counts_insert on public.physical_counts
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));

-- PHASE 2: managers can view/edit revenue; only administrators can delete/void.
create policy revenue_records_read on public.revenue_records
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));
create policy revenue_records_insert on public.revenue_records
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy revenue_records_update on public.revenue_records
  for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']))
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy revenue_records_delete on public.revenue_records
  for delete to authenticated
  using (public.has_app_role(array['Administrator']));

create policy reservations_read on public.reservations
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy reservations_insert on public.reservations
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy reservations_update on public.reservations
  for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']))
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy reservations_delete on public.reservations
  for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));

create policy buffet_rates_read on public.buffet_rates
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy buffet_rates_insert on public.buffet_rates
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy buffet_rates_update on public.buffet_rates
  for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']))
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy buffet_rates_delete on public.buffet_rates
  for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));

create policy restaurant_tables_read on public.restaurant_tables
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy restaurant_tables_insert on public.restaurant_tables
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy restaurant_tables_update on public.restaurant_tables
  for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']))
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy restaurant_tables_delete on public.restaurant_tables
  for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));

create policy audit_logs_admin_read on public.audit_logs
  for select to authenticated
  using (public.has_app_role(array['Administrator']));

-- PHASE 2: explicit function grants. Existing search_path settings are kept.
revoke all on function public.current_app_role() from public, anon;
revoke all on function public.has_app_role(text[]) from public, anon;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.has_app_role(text[]) to authenticated;
revoke all on function public.save_recipe(jsonb, timestamptz) from public, anon;
grant execute on function public.save_recipe(jsonb, timestamptz) to authenticated;
revoke all on function public.public_create_reservation(jsonb) from public;
grant execute on function public.public_create_reservation(jsonb) to anon, authenticated;
revoke all on function public.public_get_reservation_status(text, text) from public;
grant execute on function public.public_get_reservation_status(text, text) to anon, authenticated;

commit;

-- Verification queries:
-- select tablename, policyname, cmd, roles, qual, with_check
-- from pg_policies where schemaname = 'public' order by tablename, policyname;
-- select routine_name, routine_schema, security_type
-- from information_schema.routines
-- where routine_schema = 'public' and routine_name in
-- ('current_app_role', 'has_app_role', 'save_recipe',
--  'public_create_reservation', 'public_get_reservation_status');
