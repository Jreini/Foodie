# Phase 2 — Applying the schema (Justin's steps)

The Swift side is done, but **the app won't get past sign-in until these migrations are applied** — there's no `profiles` table for it to read yet.

## The simple path: SQL Editor

You don't have the Supabase CLI installed, and for a first schema the dashboard is honestly fine.

Supabase Dashboard → **SQL Editor** → New query. Paste and **Run** each file, **in this order**:

1. [`supabase/migrations/20260802000100_initial_schema.sql`](../supabase/migrations/20260802000100_initial_schema.sql) — tables and indexes
2. [`supabase/migrations/20260802000200_functions_and_triggers.sql`](../supabase/migrations/20260802000200_functions_and_triggers.sql) — functions, triggers, and the profile backfill
3. [`supabase/migrations/20260802000300_rls_policies.sql`](../supabase/migrations/20260802000300_rls_policies.sql) — Row Level Security

Order matters: file 2 references tables from file 1, and file 3 references helper functions from file 2.

Each should report success with no rows. If one errors partway, fix the cause and re-run that file from the top — the files are not individually idempotent, so if you need to start over, the cleanest reset is:

```sql
drop schema public cascade;
create schema public;
grant usage on schema public to authenticated, anon, service_role;
```

That wipes app data only; `auth.users` lives in a different schema, so your account survives.

## The durable path (optional)

If you'd rather run these the way the CLI does, and get `supabase db diff` for future changes:

```bash
brew install supabase/tap/supabase
```

Then `supabase link --project-ref lwyesojyqmagpnvclobl` and `supabase db push`. Worth doing before the schema gets much bigger, but not required today.

## Verify

Three checks in the dashboard, then one in the app.

**1. Tables exist.** Table Editor should list ten: `profiles`, `friendships`, `restaurants`, `reviews`, `likes`, `tasting_list`, `lists`, `list_members`, `list_entries`, `activities`.

**2. Your account got backfilled.** The signup trigger only fires for *new* users, so the migration backfills existing ones. Run:

```sql
select id, username, name from public.profiles;
```

You should see one row — your Phase 1 account — with a null username and your name from Apple or Google. If the table is empty, file 2 didn't finish.

**3. RLS is on everywhere.** Every table should show "RLS enabled" in the Table Editor. This query lists any that slipped through:

```sql
select tablename from pg_tables
where schemaname = 'public' and rowsecurity = false;
```

Zero rows is what you want.

**4. Run the app.** You'll land on the username screen (because your username is null). Pick one — availability is checked live against the database — and you should drop into the app with your real name and handle at the top of Profile.

## What's real now vs. still mock

Real: your account, your profile row, your username, and profile editing.

Still mock: restaurants, reviews, friends, tasting list, and the feed. Those are `MockDataService` until Phase 3 swaps the data layer. So Profile shows your true name and handle above stats that are still fictional — expected, not a bug.

## Note on the SQL

Two things in there are load-bearing and worth knowing about:

**Helper functions are `SECURITY DEFINER`.** `is_friend()`, `is_list_member()`, and `is_list_owner()` deliberately bypass RLS. Without that, a policy on `list_members` that queries `list_members` would recurse infinitely — a classic Supabase failure. They all set `search_path = ''` so a caller can't shadow `public` and hijack them.

**Missing policies are intentional.** `restaurants` has no UPDATE policy and `activities` has no INSERT policy. RLS denies anything without a matching policy, which is exactly the goal: only the aggregate-recompute and activity-logging triggers should write there, and they can, because they're `SECURITY DEFINER`. If clients could, anyone could forge ratings or fake a friend's activity.
