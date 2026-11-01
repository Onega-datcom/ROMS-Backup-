# Supabase deployment and account setup

## Apply the schema

1. Back up the project before changing its database.
2. Run `supabase-schema.sql` in the Supabase SQL Editor as the project database owner.
3. Check `public.app_records_migrations` for `typed_app_records_backfill_v1`. The supported collections are copied into typed tables atomically; the legacy JSON table remains locked as an archive.
4. If the migration marker is missing, inspect `public.app_records_migration_errors` in the SQL Editor, repair the reported legacy row, and rerun the schema. A failed backfill does not delete the source records.
5. Confirm the migrated counts in the typed tables before deploying the updated browser files.

The schema deliberately does not import the old `users` collection as real accounts. It removes the former anonymous `app_records` policies and grants public access only to the reservation RPCs.

## Provision real users

Do not add signup or service-role credentials to the browser. For each employee:

1. Create or invite the account in **Supabase Dashboard → Authentication → Users** and confirm the email.
2. Copy the Auth user's UUID.
3. In the SQL Editor, create its profile. Create the first Administrator this way:

```sql
insert into public.profiles (id, email, full_name, role)
values ('<AUTH_USER_UUID>'::uuid, '<EMAIL>', '<FULL_NAME>', 'Administrator');
```

Use one of these exact roles for other profiles: `Manager`, `Inventory Clerk`, `Chef / Kitchen Staff`, or `Receptionist`. The profile role is authoritative; users cannot change their own role from the app. User creation remains an administrator-controlled Supabase operation.

## Auth redirect configuration

Serve the files over HTTP(S), not `file://`. In **Authentication → URL Configuration**, set the production Site URL and add the dashboard URL (ending in `/index.html`) to the allowed Redirect URLs so password-reset links return to the app.

## Operational checks

- Confirm anonymous clients cannot select, insert, update, or delete business tables or profiles.
- Confirm authenticated roles can only access the modules assigned by the RLS policies; Revenue is limited to Administrators and Managers.
- Confirm recipe writes use the atomic `save_recipe` RPC and reservation status lookups require both a reference and matching email/phone.
- Keep the publishable key in the browser; never expose a Supabase `service_role` key.
- Use the app's connection indicator to retry queued changes. Resolve stale-record conflicts by reloading before reapplying a change.
