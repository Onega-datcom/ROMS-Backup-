create table if not exists public.app_records (
  collection text not null,
  record_id text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (collection, record_id)
);

alter table public.app_records enable row level security;

create policy "CostTrack demo records are readable"
  on public.app_records for select
  to anon, authenticated
  using (true);

create policy "CostTrack demo records are writable"
  on public.app_records for insert
  to anon, authenticated
  with check (true);

create policy "CostTrack demo records are editable"
  on public.app_records for update
  to anon, authenticated
  using (true)
  with check (true);

create policy "CostTrack demo records are removable"
  on public.app_records for delete
  to anon, authenticated
  using (true);
