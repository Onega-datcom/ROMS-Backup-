begin;

alter table public.restaurant_tables
  add column if not exists table_type text not null default 'Unassigned',
  add column if not exists area text not null default 'Unassigned';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.restaurant_tables'::regclass
      and conname = 'restaurant_tables_table_type_check'
  ) then
    alter table public.restaurant_tables
      add constraint restaurant_tables_table_type_check
      check (table_type in ('Family', 'Casual', 'Unassigned'));
  end if;
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.restaurant_tables'::regclass
      and conname = 'restaurant_tables_area_check'
  ) then
    alter table public.restaurant_tables
      add constraint restaurant_tables_area_check
      check (area in ('Front', 'Back', 'Unassigned'));
  end if;
end;
$$;

comment on column public.restaurant_tables.table_type is
  'Restaurant seating category: Family, Casual, or Unassigned.';
comment on column public.restaurant_tables.area is
  'Restaurant seating area: Front, Back, or Unassigned.';

commit;
