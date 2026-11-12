# Supabase deployment and account setup

## Apply the schema

1. Back up the project before changing its database.
2. Run [`supabase-schema.sql`](./supabase/supabase-schema.sql) in the Supabase SQL Editor as the project database owner.
3. Check `public.app_records_migrations` for `typed_app_records_backfill_v1`. The supported collections are copied into typed tables atomically; the legacy JSON table remains locked as an archive.
4. If the migration marker is missing, inspect `public.app_records_migration_errors` in the SQL Editor, repair the reported legacy row, and rerun the schema. A failed backfill does not delete the source records.
5. Confirm the migrated counts in the typed tables before deploying the updated browser files.

The schema deliberately does not import the old `users` collection as real accounts. It removes the former anonymous `app_records` policies and grants public access only to the reservation RPCs.

## Phase 1 inventory foundation

The Phase 1 migration is additive and depends on the base schema above. Before applying it, make and verify a database backup, then run [`phase8_inventory_architecture_migration.sql`](./supabase/phase8_inventory_architecture_migration.sql) as the database owner in a non-production project first. Do not apply it to a live project until the non-production checks pass.

If you already applied an earlier version of Phase 8, do **not** paste and rerun the full Phase 8 file. Back up the database, then run [`phase8_receiving_invoice_upgrade.sql`](./supabase/phase8_receiving_invoice_upgrade.sql) instead. It adds only the invoice fields and receiving batch/RPC behavior, and is safe to rerun. If Phase 8 has not been applied at all, apply the current full Phase 8 migration first; do not run both files for the same database.

For an existing Phase 8 database, also run [`phase8_product_details_upgrade.sql`](./supabase/phase8_product_details_upgrade.sql) after the receiving invoice upgrade. This separate, rerunnable upgrade adds preferred supplier, expiry tracking, and product notes. Do not rerun the full Phase 8 migration to add these fields. Fresh installations using the current full Phase 8 migration do not need this additional upgrade.

After it runs:

1. Inspect `public.inventory_migration_issues` for products with unknown unit conversions, duplicate product names, and legacy production rows without a recipe mapping. Resolve each issue before relying on converted quantities or migrated recipe versions.
2. Verify each positive existing stock balance has exactly one opening batch and matching opening movement. Its received date is the migration date and it has no expiration date because legacy data did not store either value.
3. Verify duplicate legacy recipe names are represented as versions with only the latest recipe active; compare recipe versions and ingredient quantities with the source tables.
4. Confirm the application loads product and recipe data through `costtrack_load_products()` and `costtrack_load_recipes()`, product edits use `costtrack_save_product()`, and recipe edits use `save_recipe()`. The product form uses active category, unit, and supplier suggestions; expiry-tracked products require an expiration date when received.
5. Test all roles, especially that Chef / Kitchen Staff cannot read product costs, recipe prices, or reports, and that only Administrators can create or edit products.
6. After applying the full migration or the receiving upgrade, the receiving panel saves an invoice and multiple product lines through `costtrack_receive_delivery()`. Confirm the supplier, invoice, dates, quantities, costs, lot numbers, and expiration dates are saved with their stock movements and inventory batches.

The new dish/version tables are a migration baseline; recipe edits still use the legacy recipe tables and RPC until those workflows are migrated. The new receiving RPC records each delivery as a batch and stock movement, while the existing inventory transaction trigger updates on-hand stock. Until Phase 9 is applied, production, waste, and physical-count writes remain on their legacy workflows. Phase 9 adds a production status queue but still uses the existing production stock trigger; FIFO/FEFO consumption is not enabled. Do not replay old inventory movements into opening batches or apply both legacy and new writes for the same receipt. The migration is designed to be rerunnable but has no automatic rollback; restore the verified backup if rollback is required.

## Phase 9 buffet production board

After the Phase 8 inventory migration and any required Phase 8 upgrades above are complete, back up the database and run [`phase9_buffet_production_migration.sql`](./supabase/phase9_buffet_production_migration.sql) once in the Supabase SQL Editor as the database owner. Do not rerun Phase 8 to enable the production board.

Phase 9 adds recipe batch yield, per-service prep targets, and Chef-facing preparation notes. It also creates a separately numbered batch queue; starting a batch does not deduct stock, while marking it Ready creates the append-only production log and applies the existing stock deduction atomically. Historical production logs are summarized as Ready batches, with unknown cooking/ready times left blank.

After applying it, confirm that `costtrack_load_recipes()` returns the new recipe fields and the app can load, start, and complete batches for today. Test all three actions with a recipe that has enough inventory, then test a batch with insufficient inventory to confirm it remains Cooking and no stock is deducted. Chef / Kitchen Staff can run the board but cannot edit recipe setup or view recipe costs; Administrators and Managers can configure categories, ingredients, yield, target, and prep notes. Apply this migration before deploying the updated app files.

## Phase 10 custom portions and production history

After Phase 9 is applied, back up the database and run [`phase10_custom_portions_production_history.sql`](./supabase/phase10_custom_portions_production_history.sql) as the database owner before deploying the updated app. This additive upgrade lets the Chef start each numbered cooking batch with half/full recipe yield or a custom whole-number portion amount (1–10,000). Recipe ingredient stock use is scaled to the chosen portions while each production log still counts as one physical batch.

The board’s Production history can filter by date range (up to 91 days), activity time, dish, and Cooking/Ready status. Activity time means the start time for a cooking batch or the ready time for a completed batch. Phase 9 backfilled earlier logs as completed batches but could not recover their exact times; these older entries are shown as “Not recorded (legacy)” and are excluded when a time filter is applied. Test a half-yield and custom-size batch, then confirm the stock deduction is proportional and its history shows the selected portions and timestamps.

## Phase 11 quick waste logging

After Phase 10, back up the database and run [`phase11_waste_workflow_migration.sql`](./supabase/phase11_waste_workflow_migration.sql) as the database owner before deploying the updated app. It adds waste-entry notes, an activity timestamp, and the authenticated staff ID. Existing waste entries remain intact; their historical times and staff are left unknown.

The waste form has searchable ingredient selection, one-tap common reasons, a stock balance preview, optional notes, and optional production-log context. Before saving, the user confirms the quantity and estimated remaining stock. The database still records each entry as append-only and atomically deducts stock once; it rejects a deduction that would make stock negative. Waste history can be filtered by date, time, ingredient, reason, and staff (including legacy entries). Estimated costs remain restricted to Administrators and Managers.

Only items actually being discarded belong in Waste Logs. Food stored safely or reused is not recorded as waste; if it is later discarded, log it then. This avoids counting retained food as a loss or deducting stock twice.

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
