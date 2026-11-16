-- Fix Phase B/C: allow a Walk-in insert with no package while retaining
-- Manager/Administrator-only package changes and required override reasons.
-- Apply after 013_walkin_atomic_billing_safeguards.sql.

begin;

create or replace function public.guard_walkin_reservation_package()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  package_changed boolean;
  walkin_related boolean;
  override_reason text;
begin
  if tg_op = 'INSERT' then
    package_changed := new.package_charge_item_id is not null
      or new.package_tier_id is not null
      or new.package_pax_count is not null;
    walkin_related := new.type = 'Walk-in';
  else
    package_changed := row(new.package_charge_item_id, new.package_tier_id, new.package_pax_count)
      is distinct from row(old.package_charge_item_id, old.package_tier_id, old.package_pax_count)
      or (
        new.type is distinct from old.type
        and (new.package_charge_item_id is not null or old.package_charge_item_id is not null)
      );
    walkin_related := new.type = 'Walk-in' or old.type = 'Walk-in';
  end if;

  if package_changed and walkin_related then
    if auth.uid() is null
      or not public.has_app_role(array['Administrator', 'Manager']) then
      raise exception 'Walk-ins cannot have event packages without a Manager or Administrator override.'
        using errcode = '42501';
    end if;
    if new.type = 'Walk-in' and new.package_charge_item_id is not null then
      override_reason := btrim(coalesce(new.package_override_reason, ''));
      if length(override_reason) not between 10 and 500 then
        raise exception 'A package override reason between 10 and 500 characters is required.'
          using errcode = '22023';
      end if;
    end if;
  end if;
  return new;
end;
$$;

commit;
