begin;

-- PHASE 5: read-only report views and aggregate RPC.
-- Apply this migration after the existing CostTrack schema. It does not
-- alter tables, columns, triggers, or RLS policies.

create or replace view public.report_confirmed_revenue_v
with (security_invoker = true)
as
select
  business_date,
  meal_period,
  adult_customers,
  child_customers,
  senior_pwd_customers,
  adult_customers + child_customers + senior_pwd_customers as covers,
  adult_customers * adult_rate
    + child_customers * child_rate
    + senior_pwd_customers * senior_pwd_rate as revenue
from public.revenue_records
where status = 'Confirmed';

create or replace view public.report_inventory_valuation_v
with (security_invoker = true)
as
select
  i.id as ingredient_id,
  i.name,
  i.category,
  i.unit,
  i.stock,
  i.cost,
  i.stock * i.cost as valuation,
  i.minimum,
  i.stock <= i.minimum as is_low_stock
from public.ingredients as i;

create or replace function public.report_analytics(
  report_key text,
  start_date date,
  end_date date,
  group_by text default 'day',
  include_waste boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  result jsonb;
begin
  if start_date is null or end_date is null or end_date < start_date then
    raise exception 'Invalid report date range';
  end if;
  if end_date - start_date > 366 then
    raise exception 'Report date range cannot exceed 366 days';
  end if;
  if group_by not in ('day', 'week', 'month') then
    raise exception 'Invalid report grouping';
  end if;

  if report_key = 'food_cost' then
    if not public.has_app_role(array['Administrator', 'Manager']) then
      raise exception 'permission denied';
    end if;
    with periods as (
      select generate_series(start_date, end_date, interval '1 day')::date as day
    ),
    revenue as (
      select date_trunc(group_by, business_date)::date as period,
        sum(revenue) as revenue
      from public.report_confirmed_revenue_v
      where business_date between start_date and end_date
      group by 1
    ),
    production as (
      select date_trunc(group_by, p.production_date)::date as period,
        sum(p.quantity * ri.quantity * i.cost * (1 + r.wastage / 100.0)) as production_cost
      from public.production_logs p
      join public.recipes r on r.id = p.recipe_id
      join public.recipe_ingredients ri on ri.recipe_id = r.id
      join public.ingredients i on i.id = ri.ingredient_id
      where p.production_date between start_date and end_date
      group by 1
    ),
    waste as (
      select date_trunc(group_by, w.waste_date)::date as period,
        sum(w.quantity * i.cost) as waste_cost
      from public.waste_logs w
      join public.ingredients i on i.id = w.ingredient_id
      where include_waste and w.waste_date between start_date and end_date
      group by 1
    ),
    rows as (
      select p.day as period,
        coalesce(rv.revenue, 0) as revenue,
        coalesce(pr.production_cost, 0) as production_cost,
        coalesce(wa.waste_cost, 0) as waste_cost,
        coalesce(pr.production_cost, 0) + coalesce(wa.waste_cost, 0) as food_cost,
        case when coalesce(rv.revenue, 0) = 0 then null
          else (coalesce(pr.production_cost, 0) + coalesce(wa.waste_cost, 0)) / rv.revenue * 100 end as food_cost_pct
      from (select distinct date_trunc(group_by, day)::date as day from periods) p
      left join revenue rv on rv.period = p.day
      left join production pr on pr.period = p.day
      left join waste wa on wa.period = p.day
      order by p.day
    )
    select jsonb_build_object(
      'rows', coalesce((select jsonb_agg(to_jsonb(rows)) from rows), '[]'::jsonb),
      'target_pct', 32,
      'includes_waste', include_waste
    ) into result;
  elsif report_key = 'revenue' then
    if not public.has_app_role(array['Administrator', 'Manager']) then
      raise exception 'permission denied';
    end if;
    with rows as (
      select business_date as period, meal_period,
        sum(adult_customers) as adults, sum(child_customers) as children,
        sum(senior_pwd_customers) as senior_pwd,
        sum(covers) as covers, sum(revenue) as revenue,
        coalesce((select sum(p.quantity * ri.quantity * i.cost * (1 + r.wastage / 100.0))
          from public.production_logs p join public.recipes r on r.id = p.recipe_id
          join public.recipe_ingredients ri on ri.recipe_id = r.id
          join public.ingredients i on i.id = ri.ingredient_id
          where p.production_date = business_date), 0) as production_cost,
        coalesce((select sum(w.quantity * i.cost) from public.waste_logs w
          join public.ingredients i on i.id = w.ingredient_id where w.waste_date = business_date), 0) as waste_cost
      from public.report_confirmed_revenue_v
      where business_date between start_date and end_date
      group by business_date, meal_period
      order by business_date, meal_period
    )
    select jsonb_build_object(
      'rows', coalesce((select jsonb_agg(to_jsonb(rows)) from rows), '[]'::jsonb),
      'no_show_count', (select count(*) from public.reservations where reservation_date between start_date and end_date and status = 'No-show'),
      'reservation_covers', (select coalesce(sum(coalesce(actual_covers, guests)), 0) from public.reservations where reservation_date between start_date and end_date and type = 'Reservation' and status in ('Seated', 'Completed')),
      'walk_in_covers', (select coalesce(sum(coalesce(actual_covers, guests)), 0) from public.reservations where reservation_date between start_date and end_date and type = 'Walk-in' and status in ('Seated', 'Completed'))
    ) into result;
  elsif report_key = 'waste' then
    if not public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff', 'Inventory Clerk']) then
      raise exception 'permission denied';
    end if;
    select jsonb_build_object(
      'by_ingredient', coalesce((select jsonb_agg(to_jsonb(x) order by x.waste_cost desc) from (
        select i.id as ingredient_id, i.name, i.unit, sum(w.quantity) as quantity,
          sum(w.quantity * i.cost) as waste_cost
        from public.waste_logs w join public.ingredients i on i.id = w.ingredient_id
        where w.waste_date between start_date and end_date
        group by i.id, i.name, i.unit order by sum(w.quantity * i.cost) desc limit 10
      ) x), '[]'::jsonb),
      'by_reason', coalesce((select jsonb_agg(to_jsonb(x) order by x.waste_cost desc) from (
        select w.reason, sum(w.quantity) as quantity, sum(w.quantity * i.cost) as waste_cost
        from public.waste_logs w join public.ingredients i on i.id = w.ingredient_id
        where w.waste_date between start_date and end_date
        group by w.reason order by sum(w.quantity * i.cost) desc
      ) x), '[]'::jsonb),
      'by_day', coalesce((select jsonb_agg(to_jsonb(x) order by x.period) from (
        select w.waste_date as period, sum(w.quantity * i.cost) as waste_cost, sum(w.quantity) as quantity
        from public.waste_logs w join public.ingredients i on i.id = w.ingredient_id
        where w.waste_date between start_date and end_date
        group by w.waste_date
      ) x), '[]'::jsonb),
      'linked_count', (select count(*) from public.waste_logs where waste_date between start_date and end_date and production_log_id is not null),
      'unlinked_count', (select count(*) from public.waste_logs where waste_date between start_date and end_date and production_log_id is null),
      'revenue_allowed', public.has_app_role(array['Administrator', 'Manager'])
    ) into result;
  elsif report_key = 'inventory' then
    if not public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']) then
      raise exception 'permission denied';
    end if;
    select jsonb_build_object(
      'valuation_by_category', coalesce((select jsonb_agg(to_jsonb(x) order by x.valuation desc) from (
        select category, sum(stock * cost) as valuation, count(*) as ingredients
        from public.ingredients group by category order by sum(stock * cost) desc
      ) x), '[]'::jsonb),
      'low_stock', coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from (
        select id as ingredient_id, name, category, stock, minimum, unit
        from public.ingredients where stock <= minimum order by name
      ) x), '[]'::jsonb),
      'movements', coalesce((select jsonb_agg(to_jsonb(x) order by x.transaction_type) from (
        select transaction_type, sum(quantity) as quantity, count(*) as entries
        from public.inventory_transactions
        where transaction_date between start_date and end_date
        group by transaction_type
      ) x), '[]'::jsonb),
      'variance', coalesce((select jsonb_agg(to_jsonb(x) order by x.count_date desc) from (
        select c.count_date, i.name, i.unit, c.expected, c.actual,
          c.actual - c.expected as variance, (c.actual - c.expected) * i.cost as variance_cost
        from public.physical_counts c join public.ingredients i on i.id = c.ingredient_id
        where c.count_date between start_date and end_date
        order by c.count_date desc
      ) x), '[]'::jsonb)
    ) into result;
  elsif report_key = 'production' then
    if not public.has_app_role(array['Administrator', 'Manager', 'Chef / Kitchen Staff']) then
      raise exception 'permission denied';
    end if;
    select jsonb_build_object(
      'rows', coalesce((select jsonb_agg(to_jsonb(x) order by x.batches desc) from (
        select r.name as recipe, sum(p.quantity) as batches,
          sum(p.quantity * coalesce((select sum(ri.quantity * i.cost) * (1 + r.wastage / 100.0)
            from public.recipe_ingredients ri join public.ingredients i on i.id = ri.ingredient_id
            where ri.recipe_id = r.id), 0)) as production_cost,
          sum(p.covers_produced) filter (where p.covers_produced is not null) as covers_produced
        from public.production_logs p join public.recipes r on r.id = p.recipe_id
        where p.production_date between start_date and end_date
        group by r.id, r.name, r.wastage order by sum(p.quantity) desc
      ) x), '[]'::jsonb)
    ) into result;
  else
    raise exception 'Unknown report';
  end if;
  return result;
end;
$$;

revoke all on function public.report_analytics(text, date, date, text, boolean) from public, anon;
grant execute on function public.report_analytics(text, date, date, text, boolean) to authenticated;

comment on function public.report_analytics(text, date, date, text, boolean) is
  'PHASE 5 read-only aggregate reports. Role checks are enforced inside the security-definer function; only confirmed revenue is included.';

commit;
