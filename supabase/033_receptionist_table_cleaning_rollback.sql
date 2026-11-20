begin;

revoke all on function public.costtrack_mark_table_clean(text)
  from public, anon, authenticated;
drop function if exists public.costtrack_mark_table_clean(text);

commit;
