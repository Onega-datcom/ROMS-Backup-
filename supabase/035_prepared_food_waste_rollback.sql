begin;

do $$
begin
  if to_regclass('public.prepared_food_waste_logs') is not null
     and exists (select 1 from public.prepared_food_waste_logs) then
    raise exception 'Prepared-food waste data exists; export it before removing this feature.';
  end if;
end;
$$;

drop function if exists public.costtrack_log_prepared_food_waste(jsonb);
drop trigger if exists write_audit_log on public.prepared_food_waste_logs;
drop trigger if exists prevent_prepared_food_waste_mutation on public.prepared_food_waste_logs;
drop table if exists public.prepared_food_waste_logs;
drop function if exists public.prevent_prepared_food_waste_mutation();

commit;
