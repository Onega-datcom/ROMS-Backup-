begin;

-- CostTrack Phase 7b-B security migration.
-- Run as a database owner. Do not use CASCADE: dependency failures must abort
-- this transaction and leave the live schema unchanged.

-- The reservation estimate is redundant with buffet_rates and exposes a
-- revenue figure through the Receptionist-readable reservations row.
alter table public.reservations
  drop column if exists estimated_revenue;

-- Match the approved delete matrix: only Administrators and Managers may
-- delete ingredients. Foreign-key restrictions still reject referenced rows.
drop policy if exists ingredients_delete on public.ingredients;
create policy ingredients_delete
  on public.ingredients for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));

create index if not exists reservations_table_id_idx
  on public.reservations (table_id);

commit;
