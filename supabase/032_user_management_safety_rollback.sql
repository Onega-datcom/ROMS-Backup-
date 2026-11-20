-- Data-preserving compatibility rollback.
-- Retains profile-write restrictions, required audit reasons, append-only audit
-- protections, and all invitation audit rows. Redeploy the previous Edge
-- Function before running this script; the current version requires resend and
-- invitation-event RPCs.
begin;

drop function if exists public.costtrack_resend_user_invitation(uuid, uuid);
drop function if exists public.costtrack_record_user_invitation_sent(uuid, uuid);

commit;
