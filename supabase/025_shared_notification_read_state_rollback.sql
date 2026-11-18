begin;

revoke all on function public.costtrack_mark_notifications_read(text[])
  from public, anon, authenticated;
revoke all on function public.costtrack_notification_read_keys()
  from public, anon, authenticated;
drop function if exists public.costtrack_mark_notifications_read(text[]);
drop function if exists public.costtrack_notification_read_keys();
drop policy if exists notification_read_states_role_read
  on public.notification_read_states;
revoke all on table public.notification_read_states
  from public, anon, authenticated;

commit;
