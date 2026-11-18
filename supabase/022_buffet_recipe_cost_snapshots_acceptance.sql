begin;

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public' and table_name = 'recipes'
      and column_name = 'is_active' and is_nullable = 'NO'
  ) then
    raise exception 'recipes.is_active is missing or nullable';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'production_logs'
      and column_name = 'batch_cost_snapshot'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'production_logs'
      and column_name = 'cost_snapshot_at'
  ) then
    raise exception 'Production cost snapshot columns are missing';
  end if;
  if to_regprocedure('public.costtrack_load_recipes()') is null
     or to_regprocedure('public.save_recipe(jsonb,timestamptz)') is null
     or to_regprocedure('public.costtrack_food_cost_report_with_snapshots(date,date,text,boolean)') is null
     or to_regprocedure('public.costtrack_production_report_with_snapshots(date,date)') is null then
    raise exception 'A buffet recipe / snapshot RPC is missing';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgname = 'production_batches_require_active_recipe'
      and not tgisinternal
  ) then
    raise exception 'Inactive recipe production guard is missing';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgname = 'apply_production_stock'
      and not tgisinternal
  ) then
    raise exception 'Production cost snapshot trigger is missing';
  end if;
end;
$$;

select
  count(*) as production_log_count,
  count(batch_cost_snapshot) as logs_with_cost_snapshot,
  count(*) filter (where batch_cost_snapshot is null) as historical_logs_without_snapshot
from public.production_logs;

select is_active, count(*) as recipe_count
from public.recipes
group by is_active
order by is_active desc;

rollback;
