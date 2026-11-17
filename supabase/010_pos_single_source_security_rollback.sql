-- Roll back 010_pos_single_source_security.sql.
-- Restores the repository's pre-010 policy/function-execution state.

begin;

do $$
declare
  policy_row record;
  table_names text[] := array[
    'pos_charge_items',
    'pos_charge_item_variants',
    'pos_package_tiers',
    'pos_package_inclusions',
    'pos_discounts',
    'pos_settings',
    'pos_shifts',
    'pos_cash_movements',
    'pos_bills',
    'pos_bill_lines',
    'pos_bill_payments',
    'pos_bill_approvals',
    'pos_reservation_deposits',
    'pos_deposit_actions',
    'pos_notifications',
    'reservations',
    'revenue_records',
    'buffet_rates'
  ];
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = any (table_names)
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_row.policyname, policy_row.schemaname, policy_row.tablename
    );
  end loop;
end;
$$;

create policy pos_charge_items_admin_full on public.pos_charge_items
  for all to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']))
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy pos_charge_items_receptionist_read on public.pos_charge_items
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));

create policy pos_charge_item_variants_admin_full on public.pos_charge_item_variants
  for all to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']))
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy pos_charge_item_variants_receptionist_read on public.pos_charge_item_variants
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));

create policy pos_package_tiers_admin_full on public.pos_package_tiers
  for all to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']))
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy pos_package_tiers_receptionist_read on public.pos_package_tiers
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));

create policy pos_package_inclusions_admin_full on public.pos_package_inclusions
  for all to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']))
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy pos_package_inclusions_receptionist_read on public.pos_package_inclusions
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));

create policy pos_discounts_admin_full on public.pos_discounts
  for all to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']))
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy pos_discounts_receptionist_read on public.pos_discounts
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));

create policy pos_settings_admin_full on public.pos_settings
  for all to authenticated
  using (public.has_app_role(array['Administrator']))
  with check (public.has_app_role(array['Administrator']));
create policy pos_settings_receptionist_read on public.pos_settings
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));

create policy pos_shifts_phase3_read on public.pos_shifts
  for select to authenticated
  using (
    public.has_app_role(array['Administrator', 'Manager'])
    or (public.has_app_role(array['Receptionist']) and opened_by = auth.uid())
  );
create policy pos_cash_movements_phase3_read on public.pos_cash_movements
  for select to authenticated
  using (
    exists (
      select 1
      from public.pos_shifts s
      where s.id = shift_id
        and (
          public.has_app_role(array['Administrator', 'Manager'])
          or (public.has_app_role(array['Receptionist']) and s.opened_by = auth.uid())
        )
    )
  );

create policy pos_bills_phase2_select on public.pos_bills
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy pos_bill_lines_phase2_select on public.pos_bill_lines
  for select to authenticated
  using (
    public.has_app_role(array['Administrator', 'Manager', 'Receptionist'])
    and exists (select 1 from public.pos_bills b where b.id = bill_id)
  );
create policy pos_bill_payments_phase2_select on public.pos_bill_payments
  for select to authenticated
  using (
    public.has_app_role(array['Administrator', 'Manager', 'Receptionist'])
    and exists (select 1 from public.pos_bills b where b.id = bill_id)
  );
create policy pos_bill_approvals_phase2_select on public.pos_bill_approvals
  for select to authenticated
  using (
    public.has_app_role(array['Administrator', 'Manager'])
    or (public.has_app_role(array['Receptionist']) and requested_by = auth.uid())
  );
create policy pos_reservation_deposits_phase3_read on public.pos_reservation_deposits
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy pos_deposit_actions_role_read on public.pos_deposit_actions
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy pos_notifications_role_read on public.pos_notifications
  for select to authenticated
  using (
    target_role = public.current_app_role()
    and public.has_app_role(array['Administrator', 'Manager'])
  );

create policy reservations_read on public.reservations
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy reservations_insert on public.reservations
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy reservations_update on public.reservations
  for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']))
  with check (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy reservations_delete on public.reservations
  for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));

create policy revenue_records_read on public.revenue_records
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));
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

create policy buffet_rates_read on public.buffet_rates
  for select to authenticated
  using (public.has_app_role(array['Administrator', 'Manager', 'Receptionist']));
create policy buffet_rates_insert on public.buffet_rates
  for insert to authenticated
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy buffet_rates_update on public.buffet_rates
  for update to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']))
  with check (public.has_app_role(array['Administrator', 'Manager']));
create policy buffet_rates_delete on public.buffet_rates
  for delete to authenticated
  using (public.has_app_role(array['Administrator', 'Manager']));

drop index if exists public.pos_bills_created_by_idx;
grant execute on function public.create_revenue_draft(text) to authenticated;

commit;
