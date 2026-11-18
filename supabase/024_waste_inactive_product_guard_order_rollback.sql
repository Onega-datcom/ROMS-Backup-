begin;

drop trigger if exists a_costtrack_waste_logs_require_active_product
  on public.waste_logs;
drop trigger if exists costtrack_waste_logs_require_active_product
  on public.waste_logs;
create trigger costtrack_waste_logs_require_active_product
  before insert or update on public.waste_logs
  for each row execute function public.costtrack_require_active_product();

commit;
