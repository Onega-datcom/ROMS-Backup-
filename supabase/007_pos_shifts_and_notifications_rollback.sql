-- Roll back migration 007 after rolling back migration 008.
-- Additive columns/settings and notification rows are retained to avoid data loss.

begin;

revoke all on function public.pos_open_shift(numeric, text) from public, anon, authenticated;
revoke all on function public.pos_record_cash_movement(text, text, numeric, text, text) from public, anon, authenticated;
revoke all on function public.pos_shift_summary(text) from public, anon, authenticated;
revoke all on function public.pos_close_shift(text, numeric, text) from public, anon, authenticated;
revoke all on function public.pos_refresh_notifications() from public, anon, authenticated;
revoke all on function public.pos_mark_notification_read(text) from public, anon, authenticated;

drop function if exists public.pos_mark_notification_read(text);
drop function if exists public.pos_refresh_notifications();
drop function if exists public.pos_close_shift(text, numeric, text);
drop function if exists public.pos_shift_summary(text);
drop function if exists public.pos_record_cash_movement(text, text, numeric, text, text);
drop function if exists public.pos_open_shift(numeric, text);

drop policy if exists pos_notifications_role_read on public.pos_notifications;
revoke all on public.pos_notifications from public, anon, authenticated;

drop policy if exists pos_shifts_phase3_read on public.pos_shifts;
drop policy if exists pos_cash_movements_phase3_read on public.pos_cash_movements;
drop policy if exists pos_shifts_admin_full on public.pos_shifts;
drop policy if exists pos_cash_movements_admin_full on public.pos_cash_movements;

create policy pos_shifts_admin_full on public.pos_shifts
  for all to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']))
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy pos_cash_movements_admin_full on public.pos_cash_movements
  for all to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']))
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));

grant select, insert, update, delete on public.pos_shifts, public.pos_cash_movements to authenticated;

drop index if exists public.pos_notifications_unread_idx;
drop index if exists public.pos_notifications_source_recipient_uidx;
drop index if exists public.pos_cash_movements_idempotency_uidx;
drop index if exists public.pos_shifts_one_open_per_cashier_uidx;

alter table public.pos_bills drop constraint if exists pos_bills_table_id_fkey;
alter table public.pos_bills drop constraint if exists pos_bills_shift_id_fkey;
alter table public.pos_bill_payments drop constraint if exists pos_bill_payments_shift_id_fkey;
alter table public.pos_reservation_deposits drop constraint if exists pos_reservation_deposits_received_shift_id_fkey;

commit;
