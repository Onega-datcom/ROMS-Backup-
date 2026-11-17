-- CostTrack Phase 1 rollback.
-- WARNING: removing new columns/table can destroy Phase 1 data. Take a backup
-- and review the statements before uncommenting the destructive block.
begin;

-- The recipe rename is reversible without data loss.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'recipes' and column_name = 'menu_price'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'recipes' and column_name = 'price'
  ) then
    alter table public.recipes rename column menu_price to price;
  end if;
end;
$$;

-- New status values cannot be safely mapped back without an application decision.
-- New columns and buffet_rates are intentionally retained by this safe rollback.
-- To remove them after backup, execute the following reviewed statements:
-- drop policy if exists buffet_rates_phase1_delete on public.buffet_rates;
-- drop policy if exists buffet_rates_phase1_update on public.buffet_rates;
-- drop policy if exists buffet_rates_phase1_insert on public.buffet_rates;
-- drop policy if exists buffet_rates_phase1_read on public.buffet_rates;
-- alter table public.buffet_rates disable row level security;
-- drop table public.buffet_rates;
-- alter table public.waste_logs drop column production_log_id;
-- alter table public.production_logs drop column covers_produced;
-- alter table public.revenue_records drop column reservation_id;
-- alter table public.revenue_records drop column rate_id;
-- alter table public.reservations drop column actual_covers;
-- alter table public.reservations drop column completed_at;
-- alter table public.reservations drop column seated_at;
-- alter table public.reservations drop column type;

commit;
