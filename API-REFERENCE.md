# CostTrack API and endpoint reference

## Architecture

CostTrack is a browser application that uses Supabase as its backend-as-a-service:

```text
Browser UI
  -> Supabase REST/PostgREST, RPC, Auth, and Realtime APIs
  -> Supabase PostgreSQL database
```

There is no separate Node.js, PHP, Python, or Express API server in this repository. The Supabase client is created in `supabase-config.js` with the project URL and publishable key.

## Base URL and endpoint meaning

The project base URL is:

```text
https://niiodqunoflblfcgdods.supabase.co
```

An endpoint is a URL that receives a request for one operation, such as reading reservations or calling a database function. Supabase generates these endpoints from the database schema and functions.

The browser sends requests through `@supabase/supabase-js`; application code normally uses `.from()`, `.rpc()`, `.auth`, and `.channel()` instead of constructing URLs manually.

## REST table API

Supabase exposes database tables through PostgREST:

```text
https://niiodqunoflblfcgdods.supabase.co/rest/v1/<table>
```

The client uses standard REST operations:

| Client operation | HTTP operation | Purpose |
| --- | --- | --- |
| `.select()` | GET | Read rows |
| `.insert()` | POST | Create rows |
| `.update()` | PATCH | Update rows |
| `.delete()` | DELETE | Delete rows |

Tables and views used by the application include:

- `profiles` — staff profiles and roles
- `product_categories` — active product categories
- `units` — active units and abbreviations
- `suppliers` — active suppliers
- `ingredients` — product records
- `recipes` — recipe records
- `inventory_transactions` — inventory movements
- `production_logs` — production records
- `revenue_records` — revenue records
- `waste_logs` — waste records
- `physical_counts` — stock-count records
- `reservations` — reservation records
- `restaurant_tables` — restaurant table records
- `buffet_rates` — buffet-rate records

Examples:

```text
GET    /rest/v1/reservations
PATCH  /rest/v1/restaurant_tables
POST   /rest/v1/revenue_records
DELETE /rest/v1/waste_logs
```

Endpoint inventory and purpose:

| Endpoint path | Main method(s) | Purpose |
| --- | --- | --- |
| `/rest/v1/profiles` | GET, PATCH | Load staff profiles and update a user's role |
| `/rest/v1/product_categories` | GET | Load active product categories for product forms |
| `/rest/v1/units` | GET | Load active measurement units |
| `/rest/v1/suppliers` | GET | Load active suppliers |
| `/rest/v1/ingredients` | GET, POST, PATCH, DELETE | Read and manage ingredient/product records |
| `/rest/v1/recipes` | GET, POST, PATCH, DELETE | Read and manage recipe records when direct table access is used |
| `/rest/v1/inventory_transactions` | GET, POST, PATCH, DELETE | Read and manage inventory movements |
| `/rest/v1/production_logs` | GET, POST, PATCH, DELETE | Read and manage production records |
| `/rest/v1/revenue_records` | GET, POST, PATCH, DELETE | Read and manage revenue records |
| `/rest/v1/waste_logs` | GET, POST, PATCH, DELETE | Read and manage waste records |
| `/rest/v1/physical_counts` | GET, POST, PATCH, DELETE | Read and manage physical stock counts |
| `/rest/v1/reservations` | GET, POST, PATCH, DELETE | Read and manage reservations |
| `/rest/v1/restaurant_tables` | GET, POST, PATCH, DELETE | Read and manage restaurant tables |
| `/rest/v1/buffet_rates` | GET, POST, PATCH, DELETE | Read and manage buffet rates |

Some sensitive product, recipe, waste, receiving, and production operations use RPC instead of direct table writes so the database can validate the complete transaction. The actual filters, selected columns, and version checks are defined in `supabase-config.js`.

## RPC endpoints

RPC means Remote Procedure Call. In this application, an RPC call invokes a PostgreSQL function through Supabase PostgREST:

```text
POST https://niiodqunoflblfcgdods.supabase.co/rest/v1/rpc/<function_name>
```

The frontend sends JSON arguments, and the PostgreSQL function validates and processes the operation.

RPC functions used by the application:

| Function | Application purpose |
| --- | --- |
| `costtrack_load_products` | Load products with database-controlled product data |
| `costtrack_load_recipes` | Load recipes |
| `costtrack_log_waste` | Record waste and apply its stock movement |
| `costtrack_save_product` | Create or update a product with validation |
| `save_recipe` | Create or update a recipe |
| `public_create_reservation` | Create a public reservation |
| `public_get_reservation_status` | Retrieve public reservation status |
| `confirm_revenue` | Confirm revenue and adjustments |
| `pos_reservation_deposit_history` | Read a reservation’s deposit and action history |
| `report_analytics` | Return report and analytics data |
| `costtrack_receive_delivery` | Record receiving, invoice lines, batches, and stock movements |
| `get_expected_covers` | Calculate expected covers for a service |
| `costtrack_load_production_batches` | Load production batches |
| `costtrack_start_production_batches` | Start production batches |
| `costtrack_load_production_history` | Load production history |
| `costtrack_complete_production_batch` | Complete a production batch |

Full RPC endpoint inventory:

| Endpoint path | Purpose |
| --- | --- |
| `/rest/v1/rpc/costtrack_load_products` | Load products using database-controlled fields |
| `/rest/v1/rpc/costtrack_load_recipes` | Load recipes using database-controlled fields |
| `/rest/v1/rpc/costtrack_log_waste` | Record waste and apply its stock deduction |
| `/rest/v1/rpc/costtrack_save_product` | Validate and save a product |
| `/rest/v1/rpc/save_recipe` | Validate and save a recipe and its ingredients |
| `/rest/v1/rpc/public_create_reservation` | Create a reservation from the public booking page |
| `/rest/v1/rpc/public_get_reservation_status` | Return public status for a reservation |
| `/rest/v1/rpc/confirm_revenue` | Confirm revenue and apply adjustments |
| `/rest/v1/rpc/pos_reservation_deposit_history` | Read reservation deposits and audit actions |
| `/rest/v1/rpc/report_analytics` | Return report and analytics results |
| `/rest/v1/rpc/costtrack_receive_delivery` | Save receiving data, batches, and inventory movements |
| `/rest/v1/rpc/get_expected_covers` | Calculate expected covers for a service |
| `/rest/v1/rpc/costtrack_load_production_batches` | Load production batches for a service date |
| `/rest/v1/rpc/costtrack_start_production_batches` | Start selected production batches |
| `/rest/v1/rpc/costtrack_load_production_history` | Load filtered production history |
| `/rest/v1/rpc/costtrack_complete_production_batch` | Mark a production batch ready and apply its completion logic |

## POS access rules

Migration 010 is the current POS security layer. RLS policies are authoritative; listing a REST operation above does not mean every role can perform it.

| POS data | Administrator / Manager | Receptionist | Inventory Clerk / Chef |
| --- | --- | --- | --- |
| Charge catalog, package tiers/inclusions, discounts | Read and manage | Read only | No POS access |
| POS settings | Administrator manages; Manager reads | Read only | No POS access |
| Bills, bill lines, bill payments | Read all | Own bills only (`created_by = auth.uid()`); save, close, and void requests use RPC | No POS access |
| Shifts and cash movements | Read all; approved operations use RPC | Read own shift and its movements; cashier operations use RPC | No POS access |
| Reservation deposits and deposit action history | Read all; Manager-only refund/forfeit through RPC | Read and record deposits through RPC; cannot refund or forfeit | No POS access |
| Bill approvals | Read all and decide through RPC | Read own requests; can request but cannot approve | No POS access |
| Revenue records | Read/write according to revenue role policies | No access | No access |

Receptionist bill visibility is enforced twice: RLS filters database reads by `created_by`, and the Cashier UI lists only bills created by the signed-in Receptionist. Billing writes, closing, void requests, and deposit operations remain RPC-controlled.

The former `create_revenue_draft(text)` function is not an available API. Migration 010 revokes execution from `PUBLIC`, `anon`, and `authenticated`; no current UI code calls it. Revenue integration is deferred to Phase 4, where closed POS bills will be the source of truth.

## Reservation guest counts and source (Phase A)

The `reservations` table stores:

| Column | Meaning |
| --- | --- |
| `adults` | Adult guest count |
| `senior_pwd_count` | Senior/PWD guest count; defaults to `0` for existing and new rows |
| `children` | Kids guest count |
| `source` | Optional `Website`, `Phone`, `Facebook`, `Walk-in`, or `Other` source |

Reservation totals and table-capacity checks use `adults + senior_pwd_count + children`. The browser validates whole-number counts; the database enforces a positive total and table capacity. Walk-ins may have no email or phone. Other reservations still require at least one of them, and the application does not fabricate contact details.

The public booking endpoint remains `POST /rest/v1/rpc/public_create_reservation` with the existing `payload` JSON argument. Website requests remain Pending, use the existing contact/rate-limit validation, default `senior_pwd_count` to `0`, and are tagged `Website` by the database. Staff create or update reservations through the existing `reservations` table endpoint subject to RLS, triggers, and constraints; the optional source is selected from the supported list.

Example:

```js
const { data, error } = await window.supabaseClient.rpc(
  'public_create_reservation',
  { payload: reservation }
);
```

## Authentication API

The application uses Supabase Auth through `window.supabaseClient.auth`:

- `signInWithPassword()` — sign in staff
- `getSession()` — restore/check the current session
- `signOut()` — sign out
- `updateUser()` — update the authenticated user's password
- `resetPasswordForEmail()` — start password recovery
- `onAuthStateChange()` — react to sign-in, sign-out, and session changes

These are handled by Supabase Auth rather than by a custom login endpoint in this repository.

The Auth SDK uses Supabase-managed Auth endpoints under the project URL. The application does not define or expose custom `/api/login` or `/api/logout` routes.

## Realtime WebSocket API

The application does use Supabase Realtime. It creates a channel with a topic shaped like:

```text
costtrack:<authenticated-user-id>:<current-view>
```

The channel is used to subscribe to database changes and refresh the relevant view when another user changes shared data. This is a WebSocket-based connection managed by Supabase, not a custom WebSocket server in the project.

| Realtime resource | Purpose |
| --- | --- |
| `costtrack:<user-id>:<view>` | Subscribe the current signed-in browser to relevant database changes for its active view |

## Security and backend responsibilities

Supabase provides the backend services used here:

- PostgreSQL stores the data.
- Database functions implement protected multi-step operations.
- Row-level security and database policies restrict access.
- Auth identifies the current staff member.
- Realtime distributes selected database changes.

The frontend contains only the publishable Supabase key. A Supabase service-role key must never be placed in browser code.

## Source locations

- Client setup and REST/RPC data access: `supabase-config.js`
- UI calls, authentication flow, and Realtime subscription: `app.js`
- Database tables, functions, triggers, and security policies: `supabase/`
- Deployment and migration instructions: `SUPABASE-SETUP.md`

## Presentation checklist and likely questions

### What backend does the system use?

The system uses Supabase as a backend-as-a-service. Supabase provides the PostgreSQL database, REST API, RPC API, authentication, security policies, and Realtime service. The repository does not contain a separate Express, Node.js, PHP, or Python server.

### What type of API is used?

The system uses several Supabase API services:

1. **REST/PostgREST API** for table reads and direct table changes.
2. **RPC API** for calling PostgreSQL functions that perform validated business operations.
3. **Supabase Auth API** for login, sessions, password changes, and recovery.
4. **Supabase Realtime WebSocket API** for database-change notifications.

### What exactly is RPC in this project?

RPC means Remote Procedure Call. In this project, it is a `POST` request to a Supabase endpoint that executes a named PostgreSQL function:

```text
POST /rest/v1/rpc/<function_name>
```

For example:

```js
await window.supabaseClient.rpc('costtrack_receive_delivery', {
  payload: delivery
});
```

This calls:

```text
https://niiodqunoflblfcgdods.supabase.co/rest/v1/rpc/costtrack_receive_delivery
```

The function can validate input and perform several related database changes atomically. This is safer than making many independent browser requests for one business transaction.

### Why does the system use RPC instead of only REST?

Simple table reads are suitable for REST. More sensitive workflows use RPC so that validation and related changes happen inside the database. Examples include:

- Receiving a delivery and creating its inventory movements.
- Recording waste and deducting stock.
- Saving a product or recipe with validation.
- Confirming revenue.
- Starting or completing production batches.
- Creating reservations with reservation rules.
- Generating analytics results.

This helps prevent incomplete transactions and makes database rules apply even if a user bypasses the interface.

### What is an endpoint?

An endpoint is a URL that accepts a request for a particular operation. For example:

```text
GET  /rest/v1/reservations
POST /rest/v1/rpc/public_create_reservation
```

The first reads reservation rows. The second runs the PostgreSQL function that creates a public reservation.

### What should be shown in a presentation?

Recommended files and demonstrations:

1. Open `index.html` and show that the browser loads the Supabase client.
2. Open `supabase-config.js` and show `createClient()`, `.from()`, and `.rpc()`.
3. Show one REST example, such as loading reservations.
4. Show one RPC example, such as `public_create_reservation` or `report_analytics`.
5. Open the corresponding SQL function in `supabase/` and show where validation and database logic run.
6. Show Supabase Dashboard -> Database -> Functions and Table Editor.
7. Explain that authentication and row-level security control who may call or modify data.
8. Explain that Realtime refreshes relevant views when shared database records change.

### What happens during a request?

The normal request flow is:

```text
User action
  -> app.js event handler
  -> supabase-config.js data-access method
  -> Supabase API endpoint
  -> Auth and row-level security checks
  -> PostgreSQL table or function
  -> response returned to the browser
  -> UI state refreshed
```

For an RPC transaction, the PostgreSQL function may also run triggers and related updates before returning its result.

### How is the API secured?

- Users authenticate through Supabase Auth.
- The browser uses only the publishable key.
- Row-level security policies restrict database access by authenticated user and role.
- PostgreSQL functions validate important business operations.
- Database triggers enforce consistency for related changes.
- A service-role key is not included in the frontend and must never be exposed there.

The publishable key is not a password. It is safe to distribute to the browser only when database policies and functions are configured correctly.

### How can the endpoints be tested?

They can be demonstrated through the application, Supabase Dashboard API documentation, or an API client such as Postman. A test request needs the Supabase project URL, the appropriate REST or RPC path, JSON input when required, and an authenticated access token for protected operations. The preferred demonstration is through the application or Supabase's generated API documentation rather than exposing credentials.

### What are the system's limitations?

- There is no custom `/api/...` route folder in this repository.
- Supabase-generated endpoints depend on the database schema and deployed SQL migrations.
- Direct REST access is still controlled by authentication and row-level security.
- RPC functions must exist in the Supabase project before their frontend calls can succeed.
- Realtime works only for configured subscriptions and permitted database changes.
- The retired `create_revenue_draft(text)` RPC is intentionally excluded from the active endpoint inventory.

### Short answer for a professor

> "Our system uses Supabase as a backend-as-a-service. We use its REST API for table operations, its RPC API to execute validated PostgreSQL functions for complex transactions, Supabase Auth for authentication, and Realtime WebSockets for live updates. The frontend calls these services through `supabase-config.js`, while the database tables, functions, triggers, and row-level security policies are defined in the `supabase` SQL files."
