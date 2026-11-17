begin;

-- CostTrack Phase 7b-B rollback.
-- The old estimated_revenue values are restored from the production backup
-- schema/data, not by this rollback script.

alter table public.reservations
  add column if not exists estimated_revenue numeric;

drop policy if exists ingredients_delete on public.ingredients;
create policy ingredients_delete
  on public.ingredients for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']));

commit;
