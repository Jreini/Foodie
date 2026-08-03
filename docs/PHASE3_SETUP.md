# Phase 3 — Applying the migration (Justin's steps)

One new migration, then build. Short version: **the app has no restaurants until you run this**, because the `restaurants` table has been empty since Phase 2 and Discover reads it directly now.

## Apply

Supabase Dashboard → **SQL Editor** → paste and run:

[`supabase/migrations/20260802000400_restaurant_details_and_seed.sql`](../supabase/migrations/20260802000400_restaurant_details_and_seed.sql)

It does two things: adds the `tags`, `hours_description`, and `is_open_now` columns the `Restaurant` model needs, and inserts the eight starter restaurants. Both halves are safe to re-run — the columns use `if not exists` and the insert uses `on conflict do nothing`.

Verify:

```sql
select count(*) from public.restaurants;
```

Eight.

## What changes in the app

Everything except friends is now live data:

| Works end to end | Notes |
|---|---|
| Discover | Reads the seeded restaurants. Pull to refresh. |
| Restaurant detail | Reviews load from the database. |
| Tasting list | Add and remove persist; survives a reinstall. |
| Reviews | Posting writes a row, which fires triggers that recompute the restaurant's crowd tier and average rating **and** create a feed entry. |
| Feed | Shows real activity. Yours appears immediately; friends' will once friends exist. |
| Profile | Real name, handle, review count, tasting list count. |

Friends stay empty until Phase 5 builds the request/accept UI — the tables and policies are already there, nothing writes to them yet.

## Worth testing specifically

**Post a review, then reopen the restaurant.** The star average and tier badge should move. That confirms the whole chain: the write hit Postgres, `refresh_restaurant_aggregates()` fired, and the re-read picked up the new values. Nothing in the app computes those — if they change, the database did it.

**Then check the Feed tab.** Your review should be there, put there by `log_activity()`. If the review saved but the feed is empty, the trigger didn't fire.

**Force-quit and reopen.** Anything you added to the tasting list should still be there. This is the first phase where that's true.

**Turn on airplane mode and pull to refresh.** You should get "You're offline" with a Try Again button, not a blank screen or a spinner forever.

## Ratings start at zero

The seed deliberately leaves `average_rating` and `review_count` at 0 rather than copying the mock's invented 4.5s. Those columns are maintained by a trigger, so seeded values would have been both untrue and immediately overwritten by your first real review. `baseline_tier` *is* seeded, because the model defines it as the starting point before any user places the restaurant.

So Discover looks unrated on first run. That's correct — nobody has rated anything yet.
