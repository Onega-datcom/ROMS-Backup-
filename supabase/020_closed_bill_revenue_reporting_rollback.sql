-- Roll back Phase 4 reporting without deleting historical or POS data.

begin;

drop function if exists public.pos_revenue_report(text, date, date, text, boolean, integer, integer);
drop view if exists public.pos_voided_bill_revenue_v;
drop view if exists public.pos_closed_bill_revenue_v;

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
  if not public.has_app_role(array['Administrator', 'Manager', 'Inventory Clerk']) then
    raise exception 'Not authorized to read financial or operational reports'
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

drop policy if exists revenue_records_insert on public.revenue_records;
drop policy if exists revenue_records_update on public.revenue_records;
drop policy if exists revenue_records_delete on public.revenue_records;
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
grant insert, update, delete on table public.revenue_records to authenticated;
grant execute on function public.confirm_revenue(text, jsonb) to authenticated;

commit;
