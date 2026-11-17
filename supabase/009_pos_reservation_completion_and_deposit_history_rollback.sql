-- Roll back the reservation completion guard and deposit-history RPC.

begin;

drop trigger if exists require_settled_pos_bill_for_reservation_completion
  on public.reservations;
drop function if exists public.require_settled_pos_bill_for_reservation_completion();
drop function if exists public.pos_reservation_deposit_history(text);

commit;
