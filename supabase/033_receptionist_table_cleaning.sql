begin;

create or replace function public.costtrack_mark_table_clean(p_table_id text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  updated_table_id text;
begin
  if not public.has_app_role(array['Receptionist']) then
    raise exception 'Only Receptionists can use this table-cleaning action.'
      using errcode = '42501';
  end if;
  if nullif(btrim(p_table_id), '') is null then
    raise exception 'A table is required.';
  end if;

  update public.restaurant_tables
  set status = 'Available'
  where id = p_table_id
    and status = 'Needs cleaning'
  returning id into updated_table_id;

  if updated_table_id is null then
    raise exception 'This table no longer needs cleaning.'
      using errcode = '55000';
  end if;
  return true;
end;
$$;

revoke all on function public.costtrack_mark_table_clean(text)
  from public, anon, authenticated;
grant execute on function public.costtrack_mark_table_clean(text)
  to authenticated;

commit;
