-- Phase 4: closed POS bills are the sole revenue source.
-- Run after 019_resolve_stale_bookings.sql.

begin;

create or replace view public.pos_closed_bill_revenue_v
with (security_invoker = true)
as
select
  b.id as bill_id,
  b.bill_number,
  b.reservation_id,
  b.shift_id,
  timezone('Asia/Manila', b.closed_at)::date as business_date,
  b.closed_at,
  b.subtotal,
  b.service_charge,
  b.discount_total,
  round(greatest(0::numeric, b.subtotal + b.service_charge - b.discount_total), 2)
    as net_revenue,
  b.food_revenue_total,
  b.non_food_revenue_total,
  b.adult_count,
  b.senior_count,
  b.kids_count,
  b.comped_count,
  b.customers_served
from public.pos_bills as b
where b.status = 'Closed'
  and b.closed_at is not null;

create or replace view public.pos_voided_bill_revenue_v
with (security_invoker = true)
as
select
  b.id as bill_id,
  b.bill_number,
  b.shift_id,
  timezone('Asia/Manila', b.voided_at)::date as void_business_date,
  b.voided_at,
  b.closed_at,
  b.subtotal,
  b.service_charge,
  b.discount_total,
  case when b.closed_at is not null
    then round(greatest(0::numeric, b.subtotal + b.service_charge - b.discount_total), 2)
    else 0::numeric
  end as reversed_revenue
from public.pos_bills as b
where b.status = 'Voided'
  and b.voided_at is not null;

revoke all on table public.pos_closed_bill_revenue_v,
  public.pos_voided_bill_revenue_v from public, anon, authenticated;

create or replace function public.pos_revenue_report(
  p_report_key text,
  p_start_date date default null,
  p_end_date date default null,
  p_group_by text default 'day',
  p_include_waste boolean default true,
  p_page integer default 1,
  p_page_size integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  report_key_value text := lower(btrim(coalesce(p_report_key, '')));
  group_by_value text := lower(btrim(coalesce(p_group_by, 'day')));
  today_value date := public.pos_business_date();
  page_value integer := coalesce(p_page, 1);
  page_size_value integer := coalesce(p_page_size, 100);
  total_rows_value bigint;
  result_value jsonb;
begin
  if auth.uid() is null
     or not public.has_app_role(array['Administrator', 'Manager']) then
    raise exception 'Only Managers and Administrators may read POS revenue reports.'
      using errcode = '42501';
  end if;

  if report_key_value not in (
    'dashboard', 'daily_revenue', 'revenue_trend', 'customer_count',
    'shift_revenue', 'closed_bill_summary', 'food_cost'
  ) then
    raise exception 'Unknown POS revenue report.'
      using errcode = '22023';
  end if;
  if group_by_value not in ('day', 'week', 'month') then
    raise exception 'Group by must be day, week, or month.'
      using errcode = '22023';
  end if;

  if report_key_value = 'dashboard' then
    select jsonb_build_object(
      'business_date', today_value,
      'today_revenue', coalesce((
        select sum(v.net_revenue)
        from public.pos_closed_bill_revenue_v as v
        where v.business_date = today_value
      ), 0),
      'closed_bill_count', (
        select count(*) from public.pos_closed_bill_revenue_v as v
        where v.business_date = today_value
      ),
      'customers_served', coalesce((
        select sum(v.customers_served) from public.pos_closed_bill_revenue_v as v
        where v.business_date = today_value
      ), 0),
      'adult_count', coalesce((
        select sum(v.adult_count) from public.pos_closed_bill_revenue_v as v
        where v.business_date = today_value
      ), 0),
      'senior_count', coalesce((
        select sum(v.senior_count) from public.pos_closed_bill_revenue_v as v
        where v.business_date = today_value
      ), 0),
      'kids_count', coalesce((
        select sum(v.kids_count) from public.pos_closed_bill_revenue_v as v
        where v.business_date = today_value
      ), 0),
      'comped_count', coalesce((
        select sum(v.comped_count) from public.pos_closed_bill_revenue_v as v
        where v.business_date = today_value
      ), 0),
      'average_check', coalesce((
        select round(sum(v.net_revenue) / nullif(count(*), 0), 2)
        from public.pos_closed_bill_revenue_v as v
        where v.business_date = today_value
      ), 0),
      'discount_total', coalesce((
        select sum(v.discount_total) from public.pos_closed_bill_revenue_v as v
        where v.business_date = today_value
      ), 0),
      'voided_bill_count', (
        select count(*) from public.pos_voided_bill_revenue_v as v
        where v.void_business_date = today_value
      ),
      'voided_bill_amount', coalesce((
        select sum(v.reversed_revenue) from public.pos_voided_bill_revenue_v as v
        where v.void_business_date = today_value
      ), 0)
    ) into result_value;
    return result_value;
  end if;

  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'A valid report date range is required.'
      using errcode = '22023';
  end if;
  if p_end_date - p_start_date > 366 then
    raise exception 'Report date range cannot exceed 366 days.'
      using errcode = '22023';
  end if;
  if page_value < 1 or page_size_value < 1 or page_size_value > 500 then
    raise exception 'Page must be positive and page size must be between 1 and 500.'
      using errcode = '22023';
  end if;

  if report_key_value in ('daily_revenue', 'revenue_trend') then
    if report_key_value = 'daily_revenue' then
      group_by_value := 'day';
    end if;
    with periods as (
      select distinct date_trunc(group_by_value, d)::date as period
      from generate_series(
        p_start_date::timestamp, p_end_date::timestamp, interval '1 day'
      ) as days(d)
    ),
    sales as (
      select date_trunc(group_by_value, v.business_date::timestamp)::date as period,
        count(*)::bigint as closed_bill_count,
        coalesce(sum(v.adult_count), 0)::bigint as adult_count,
        coalesce(sum(v.senior_count), 0)::bigint as senior_count,
        coalesce(sum(v.kids_count), 0)::bigint as kids_count,
        coalesce(sum(v.comped_count), 0)::bigint as comped_count,
        coalesce(sum(v.customers_served), 0)::bigint as customers_served,
        coalesce(sum(v.subtotal), 0)::numeric(12,2) as subtotal,
        coalesce(sum(v.service_charge), 0)::numeric(12,2) as service_charge,
        coalesce(sum(v.discount_total), 0)::numeric(12,2) as discount_total,
        coalesce(sum(v.net_revenue), 0)::numeric(12,2) as net_revenue
      from public.pos_closed_bill_revenue_v as v
      where v.business_date between p_start_date and p_end_date
      group by 1
    ),
    voids as (
      select date_trunc(group_by_value, v.void_business_date::timestamp)::date as period,
        count(*)::bigint as voided_bill_count,
        coalesce(sum(v.reversed_revenue), 0)::numeric(12,2) as voided_bill_amount
      from public.pos_voided_bill_revenue_v as v
      where v.void_business_date between p_start_date and p_end_date
      group by 1
    )
    select jsonb_build_object(
      'group_by', group_by_value,
      'rows', coalesce(jsonb_agg(to_jsonb(r) order by r.period), '[]'::jsonb)
    )
    into result_value
    from (
      select p.period,
        coalesce(s.closed_bill_count, 0) as closed_bill_count,
        coalesce(s.adult_count, 0) as adult_count,
        coalesce(s.senior_count, 0) as senior_count,
        coalesce(s.kids_count, 0) as kids_count,
        coalesce(s.comped_count, 0) as comped_count,
        coalesce(s.customers_served, 0) as customers_served,
        coalesce(s.subtotal, 0) as subtotal,
        coalesce(s.service_charge, 0) as service_charge,
        coalesce(s.discount_total, 0) as discount_total,
        coalesce(s.net_revenue, 0) as net_revenue,
        coalesce(v.voided_bill_count, 0) as voided_bill_count,
        coalesce(v.voided_bill_amount, 0) as voided_bill_amount
      from periods as p
      left join sales as s on s.period = p.period
      left join voids as v on v.period = p.period
    ) as r;
    return result_value;
  end if;

  if report_key_value = 'customer_count' then
    with periods as (
      select distinct date_trunc(group_by_value, d)::date as period
      from generate_series(
        p_start_date::timestamp, p_end_date::timestamp, interval '1 day'
      ) as days(d)
    ),
    counts as (
      select date_trunc(group_by_value, v.business_date::timestamp)::date as period,
        count(*)::bigint as closed_bill_count,
        coalesce(sum(v.adult_count), 0)::bigint as adult_count,
        coalesce(sum(v.senior_count), 0)::bigint as senior_count,
        coalesce(sum(v.kids_count), 0)::bigint as kids_count,
        coalesce(sum(v.comped_count), 0)::bigint as comped_count,
        coalesce(sum(v.customers_served), 0)::bigint as customers_served
      from public.pos_closed_bill_revenue_v as v
      where v.business_date between p_start_date and p_end_date
      group by 1
    )
    select jsonb_build_object(
      'group_by', group_by_value,
      'rows', coalesce(jsonb_agg(to_jsonb(r) order by r.period), '[]'::jsonb)
    )
    into result_value
    from (
      select p.period,
        coalesce(c.closed_bill_count, 0) as closed_bill_count,
        coalesce(c.adult_count, 0) as adult_count,
        coalesce(c.senior_count, 0) as senior_count,
        coalesce(c.kids_count, 0) as kids_count,
        coalesce(c.comped_count, 0) as comped_count,
        coalesce(c.customers_served, 0) as customers_served
      from periods as p
      left join counts as c on c.period = p.period
    ) as r;
    return result_value;
  end if;

  if report_key_value = 'shift_revenue' then
    with bill_sales as (
      select v.shift_id,
        count(*)::bigint as closed_bill_count,
        coalesce(sum(v.net_revenue), 0)::numeric(12,2) as net_revenue,
        coalesce(sum(v.discount_total), 0)::numeric(12,2) as discount_total,
        coalesce(sum(v.customers_served), 0)::bigint as customers_served,
        coalesce(sum(v.adult_count), 0)::bigint as adult_count,
        coalesce(sum(v.senior_count), 0)::bigint as senior_count,
        coalesce(sum(v.kids_count), 0)::bigint as kids_count,
        coalesce(sum(v.comped_count), 0)::bigint as comped_count,
        coalesce(sum(da.deposit_applied), 0)::numeric(12,2) as deposit_applied
      from public.pos_closed_bill_revenue_v as v
      left join lateral (
        select coalesce(sum(p.amount), 0)::numeric(12,2) as deposit_applied
        from public.pos_bill_payments as p
        where p.bill_id = v.bill_id and p.payment_method = 'deposit'
      ) as da on true
      where v.business_date between p_start_date and p_end_date
      group by v.shift_id
    ),
    relevant_shift_ids as (
      select s.shift_id from bill_sales as s where s.shift_id is not null
      union
      select d.received_shift_id
      from public.pos_reservation_deposits as d
      where d.received_shift_id is not null
        and timezone('Asia/Manila', d.created_at)::date
          between p_start_date and p_end_date
      union
      select m.shift_id
      from public.pos_cash_movements as m
      where m.shift_id is not null
        and timezone('Asia/Manila', m.created_at)::date
          between p_start_date and p_end_date
    ),
    shift_rows as (
      select s.id as shift_id,
        s.shift_code,
        s.opened_by,
        s.opened_at,
        s.closed_at,
        s.status as shift_status,
        coalesce(b.closed_bill_count, 0) as closed_bill_count,
        coalesce(b.net_revenue, 0) as net_revenue,
        coalesce(b.discount_total, 0) as discount_total,
        coalesce(b.customers_served, 0) as customers_served,
        coalesce(b.adult_count, 0) as adult_count,
        coalesce(b.senior_count, 0) as senior_count,
        coalesce(b.kids_count, 0) as kids_count,
        coalesce(b.comped_count, 0) as comped_count,
        coalesce(b.deposit_applied, 0) as deposit_applied,
        coalesce((summary.data->>'deposit_receipts')::numeric, 0) as deposit_receipts,
        coalesce((summary.data->>'cash_payments')::numeric, 0) as cash_payments,
        coalesce((summary.data->>'paid_in')::numeric, 0) as paid_in,
        coalesce((summary.data->>'paid_out')::numeric, 0) as paid_out,
        coalesce((summary.data->>'cash_refunds')::numeric, 0) as cash_refunds,
        coalesce((summary.data->>'expected_cash')::numeric, 0) as expected_cash
      from relevant_shift_ids as ids
      join public.pos_shifts as s on s.id = ids.shift_id
      left join bill_sales as b on b.shift_id = s.id
      cross join lateral (
        select public.pos_shift_summary(s.id) as data
      ) as summary
    )
    select jsonb_build_object(
      'rows',
      coalesce((
        select jsonb_agg(to_jsonb(r) order by r.opened_at desc)
        from shift_rows as r
      ), '[]'::jsonb)
      ||
      coalesce((
        select jsonb_agg(to_jsonb(r))
        from (
          select
            null::text as shift_id,
            'Unassigned / legacy'::text as shift_code,
            null::uuid as opened_by,
            null::timestamptz as opened_at,
            null::timestamptz as closed_at,
            null::text as shift_status,
            b.closed_bill_count,
            b.net_revenue,
            b.discount_total,
            b.customers_served,
            b.adult_count,
            b.senior_count,
            b.kids_count,
            b.comped_count,
            b.deposit_applied,
            0::numeric as deposit_receipts,
            0::numeric as cash_payments,
            0::numeric as paid_in,
            0::numeric as paid_out,
            0::numeric as cash_refunds,
            0::numeric as expected_cash
          from bill_sales as b
          where b.shift_id is null
        ) as r
      ), '[]'::jsonb)
    ) into result_value;
    return result_value;
  end if;

  if report_key_value = 'closed_bill_summary' then
    select count(*) into total_rows_value
    from public.pos_closed_bill_revenue_v as v
    where v.business_date between p_start_date and p_end_date;

    select jsonb_build_object(
      'rows', coalesce(jsonb_agg(to_jsonb(r) order by r.closed_at desc), '[]'::jsonb),
      'total_rows', total_rows_value,
      'page', page_value,
      'page_size', page_size_value
    )
    into result_value
    from (
      select v.bill_id,
        v.bill_number,
        v.business_date,
        v.closed_at,
        v.shift_id,
        s.shift_code,
        v.subtotal,
        v.service_charge,
        v.discount_total,
        v.net_revenue,
        v.adult_count,
        v.senior_count,
        v.kids_count,
        v.comped_count,
        v.customers_served,
        coalesce((
          select sum(p.amount)
          from public.pos_bill_payments as p
          where p.bill_id = v.bill_id and p.payment_method = 'deposit'
        ), 0)::numeric(12,2) as deposit_applied
      from public.pos_closed_bill_revenue_v as v
      left join public.pos_shifts as s on s.id = v.shift_id
      where v.business_date between p_start_date and p_end_date
      order by v.closed_at desc, v.bill_id
      limit page_size_value
      offset (page_value - 1) * page_size_value
    ) as r;
    return result_value;
  end if;

  if report_key_value = 'food_cost' then
    with periods as (
      select distinct date_trunc(group_by_value, d)::date as period
      from generate_series(
        p_start_date::timestamp, p_end_date::timestamp, interval '1 day'
      ) as days(d)
    ),
    revenue as (
      select date_trunc(group_by_value, v.business_date::timestamp)::date as period,
        sum(v.net_revenue) as revenue
      from public.pos_closed_bill_revenue_v as v
      where v.business_date between p_start_date and p_end_date
      group by 1
    ),
    production as (
      select date_trunc(group_by_value, p.production_date::timestamp)::date as period,
        sum(p.quantity * ri.quantity * i.cost * (1 + r.wastage / 100.0)) as production_cost
      from public.production_logs as p
      join public.recipes as r on r.id = p.recipe_id
      join public.recipe_ingredients as ri on ri.recipe_id = r.id
      join public.ingredients as i on i.id = ri.ingredient_id
      where p.production_date between p_start_date and p_end_date
      group by 1
    ),
    waste as (
      select date_trunc(group_by_value, w.waste_date::timestamp)::date as period,
        sum(w.quantity * i.cost) as waste_cost
      from public.waste_logs as w
      join public.ingredients as i on i.id = w.ingredient_id
      where p_include_waste and w.waste_date between p_start_date and p_end_date
      group by 1
    )
    select jsonb_build_object(
      'rows', coalesce(jsonb_agg(to_jsonb(r) order by r.period), '[]'::jsonb),
      'target_pct', 32,
      'includes_waste', p_include_waste
    )
    into result_value
    from (
      select periods.period,
        coalesce(revenue.revenue, 0) as revenue,
        coalesce(production.production_cost, 0) as production_cost,
        coalesce(waste.waste_cost, 0) as waste_cost,
        coalesce(production.production_cost, 0) + coalesce(waste.waste_cost, 0) as food_cost,
        case when coalesce(revenue.revenue, 0) = 0 then null
          else (coalesce(production.production_cost, 0)
            + coalesce(waste.waste_cost, 0)) / revenue.revenue * 100
        end as food_cost_pct
      from periods
      left join revenue using (period)
      left join production using (period)
      left join waste using (period)
    ) as r;
    return result_value;
  end if;

  raise exception 'Unknown POS revenue report.'
    using errcode = '22023';
end;
$$;

revoke all on function public.pos_revenue_report(text, date, date, text, boolean, integer, integer)
  from public, anon;
grant execute on function public.pos_revenue_report(text, date, date, text, boolean, integer, integer)
  to authenticated;

-- Route existing revenue and food-cost report requests through closed bills.
create or replace function public.report_analytics(
  report_key text,
  start_date date,
  end_date date,
  group_by text default 'day',
  include_waste boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if report_key in ('revenue', 'food_cost') then
    if not public.has_app_role(array['Administrator', 'Manager']) then
      raise exception 'Not authorized to read financial reports.'
        using errcode = '42501';
    end if;
    return public.pos_revenue_report(
      case when report_key = 'revenue' then 'daily_revenue' else 'food_cost' end,
      start_date, end_date, group_by, include_waste
    );
  end if;
  if not public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']) then
    raise exception 'Not authorized to read operational reports.'
      using errcode = '42501';
  end if;
  return public.costtrack_report_analytics_legacy(
    report_key, start_date, end_date, group_by, include_waste
  );
end;
$$;

revoke all on function public.report_analytics(text, date, date, text, boolean)
  from public, anon;
grant execute on function public.report_analytics(text, date, date, text, boolean)
  to authenticated;

-- Keep the legacy table as a Manager/Administrator-readable archive only.
drop policy if exists revenue_records_insert on public.revenue_records;
drop policy if exists revenue_records_update on public.revenue_records;
drop policy if exists revenue_records_delete on public.revenue_records;
revoke insert, update, delete on table public.revenue_records from public, anon, authenticated;
grant select on table public.revenue_records to authenticated;
revoke all on function public.confirm_revenue(text, jsonb) from public, anon, authenticated;
revoke all on function public.create_revenue_draft(text) from public, anon, authenticated;

commit;
