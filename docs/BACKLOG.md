# Backlog

Outstanding work, roughly in the order it's worth doing. Open *bugs* live in [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) — this file is for work that hasn't been started.

Nothing here is required to ship. The app is feature-complete through Phase 9 and on TestFlight.

---

## Do first — real user data is now at stake

The `friendships` forged-acceptance hole that used to head this list is **closed**. [`20260803000300_fix_insert_policy_gaps.sql`](../supabase/migrations/20260803000300_fix_insert_policy_gaps.sql) was applied on 4 August 2026, and the audit for accepted friendships that were never actually accepted —

```sql
select id, requester_id, addressee_id, created_at
from public.friendships
where status = 'accepted' and responded_at is null;
```

— returned **zero rows**, so the gap was never used before it was closed. The same migration also constrained `list_members.role`.

### 1. ~~`restaurants` INSERT leaves the crowd columns writable~~ — fixed, needs applying

**Written, not yet applied.** [`20260804000100_restaurant_insert_column_grants.sql`](../supabase/migrations/20260804000100_restaurant_insert_column_grants.sql) replaces the table-wide INSERT grant on `restaurants` with column-level ones, leaving `average_rating`, `average_tier` and `review_count` — all trigger-maintained — ungrantable to a client. **Run it in the SQL editor**; the file does nothing sitting in the repo.

Same shape as the friendships one: the policy checks `auth.uid() = created_by` and stops, so a crafted insert could seed a new place with a five-star average and a review count it never earned. It's insert-only (there's no UPDATE policy) and `refresh_restaurant_aggregates()` corrects the values the moment anyone genuinely reviews the place, so the window is real but narrow — which is why it was held back for its own change rather than folded into `...000300`.

The granted column list was checked against `RestaurantInsert` in `SupabaseDataService.swift`, and `price_level` is included even though nothing sends it today. **Verify on a real device**, because `ensureRestaurantPersisted` is the hottest write path in the app: add a place that isn't in the database yet to a tasting list, like it, and review it. All three resolve the place through that one call, so a wrong column list breaks them together with a 403. The migration's footer has the two SQL checks worth running first.

### 2. Confirm what the database backups actually are — tooling written, dashboard check outstanding

**Half done.** [`Tools/backup_db.sh`](../Tools/backup_db.sh) takes a verified local `pg_dump` of the `public` schema (with its grants and policies) plus `auth.users`, and [`docs/BACKUPS.md`](BACKUPS.md) covers setup, cadence, what a dump doesn't cover, and how a restore should go.

What's left, and it needs the dashboard:

- Check the plan, the Database → Backups tab, and whether PITR is on.
- Write the answers into the *Findings* block in [`BACKUPS.md`](BACKUPS.md), so the next person doesn't re-check.
- Run the script once so the first dump exists and the Keychain entry is set up.

Whatever the plan turns out to retain, the local dump is worth having: recovering one table from a file you already have beats restoring a whole project.

### 3. There is no staging environment

`SupabaseService.swift` hard-codes one project URL, so production is also the development environment. Every migration is applied straight to the database holding real users' reviews.

A second Supabase project as staging is free and would make destructive changes safe to rehearse. The cost is keeping two schemas in step and switching the URL per build configuration. Worth doing before any migration that touches existing columns.

---

## Push notification follow-ups

None of these are broken — they're the edges Phase 9 deliberately left square.

### 4. Deep link to the specific shared list

`list_added` notifications currently land on the Shared Lists index. The payload already carries `list_id`, so the data is there; what's missing is a route that can push a `SharedList` the app hasn't loaded yet, which means fetching it by id first. Same for landing on a specific friend request rather than the Friends screen.

### 5. App icon badge

Deliberately omitted — the permission asks for `.badge` so it can be switched on later without a second prompt, but nothing sets one. It would mean one extra query per push, and an icon badge is the part of notifications people resent first. The bell's unread dot covers the same need inside the app.

### 6. The inbox can't be cleared, and stops at 50

There's no delete policy on `notifications` and no pagination — read rows are pruned after 30 days by the Edge Function, which is why neither has bitten. Both are small additions if the inbox starts feeling cluttered.

### 7. No per-type notification preferences

It's all or nothing: the iOS permission, or silence. Once there are more types than the current three, a preferences screen writing to a `notification_settings` table — checked in the Edge Function before sending — is the natural next step.

### 8. `timeAgoString` is duplicated

`FriendActivity` and `AppNotification` carry identical copies. It's ten lines, and they were deliberately kept identical because the two appear one tap apart and drifting wording would read as a bug. Worth extracting to a shared `Date` extension the next time either is touched.

---

## Testing

### 9. There are no tests at all

The highest-value targets are the pure logic, which needs no network and no session:

- `TierFlaggingService` — the flagging thresholds are the app's most intricate rule (≥ 0.25 away *and* ≥ 2 named zones apart, ≥ 1 existing review) and the easiest to break silently.
- `FriendshipState.between(currentUserId:otherUserId:friendships:)` — five states, decided from a list of edges in either direction.
- `RestaurantTier` zone boundaries, which deliberately overlap.
- `AppNotification.message` and `Kind.destination`.

`MockDataService` already exists and conforms to the full protocol, so view-model tests have a backend to run against without touching Supabase.

---

## Cleanup

### 10. Core Data boilerplate is still in the target

`Persistence.swift`, `ContentView.swift`, and `Foodie.xcdatamodeld` are untouched Xcode template output with a single unused `Item` entity. `ContentView` isn't in the app's navigation and `FoodieApp` injects a managed object context no feature reads.

Removing it is tidy but not free: the `.xcdatamodeld` is a real pbxproj reference rather than a synchronized file-system group, so it needs a project-file edit. Worth doing when something else already requires opening the project settings.

---

## Operational

### 11. The legacy service-role key retires at the end of 2026

The `push` Edge Function reads `SUPABASE_SERVICE_ROLE_KEY`, which Supabase injects automatically and which is a legacy JWT key. The code already prefers `FOODIE_SERVICE_KEY` when it's set, so the migration is: create an `sb_secret_...` key, set it as that secret, done. No code change — but it does need doing before the retirement date, and nothing will remind you.

The same deadline applies to the publishable key in `SupabaseService.swift`, which is already the new-style `sb_publishable_...`, so that half is fine.

### 12. Account deletion has no export

The App Store requires the delete path, which exists and works. It doesn't require an export, and there isn't one — someone who deletes their account loses their reviews with no way to keep a copy. Worth having before the user base is anyone other than friends.
