-- PHASE 6: realtime publication additions and read-only production planning.
begin;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'ingredients', 'recipes', 'recipe_ingredients', 'inventory_transactions',
    'production_logs', 'waste_logs', 'physical_counts', 'reservations',
    'restaurant_tables', 'revenue_records', 'buffet_rates'
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

create or replace function public.get_expected_covers(
  service_date date,
  meal_period text default null
)
returns table (expected_covers integer, average_completed_covers numeric, sample_days integer)
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']) then
    raise exception 'permission denied';
  end if;
  return query
  with expected as (
    select coalesce(sum(coalesce(actual_covers, guests)), 0)::integer as covers
    from public.reservations
    where reservation_date = service_date
      and status in ('Pending', 'Confirmed', 'Seated')
  ), weekday_days as (
    select reservation_date, sum(coalesce(actual_covers, guests))::numeric as covers
    from public.reservations
    where reservation_date < service_date
      and extract(dow from reservation_date) = extract(dow from service_date)
      and status = 'Completed'
    group by reservation_date
    order by reservation_date desc
    limit 4
  )
  select expected.covers,
    coalesce((select avg(wd.covers) from weekday_days wd), 0)::numeric,
    (select count(*)::integer from weekday_days)
  from expected;
end;
$$;

revoke all on function public.get_expected_covers(date, text) from public, anon;
grant execute on function public.get_expected_covers(date, text) to authenticated;

commit;