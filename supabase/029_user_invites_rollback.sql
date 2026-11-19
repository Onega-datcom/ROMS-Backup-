begin;

drop trigger if exists user_invites_guard on public.user_invites;
drop function if exists public.guard_user_invite();
drop table if exists public.user_invites;

commit;
