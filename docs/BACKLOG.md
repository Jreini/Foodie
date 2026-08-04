# Backlog

Outstanding work, roughly in the order it's worth doing. Open *bugs* live in [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) — this file is for work that hasn't been started.

Nothing here is required to ship. The app is feature-complete through Phase 9 and on TestFlight.

---

## Do first — real user data is now at stake

### 1. ~~`friendships` INSERT policy lets someone forge an accepted friendship~~ — fixed, needs applying

**Written, not yet applied.** [`20260803000300_fix_insert_policy_gaps.sql`](../supabase/migrations/20260803000300_fix_insert_policy_gaps.sql) adds `and status = 'pending'` to the friendships INSERT policy, and `and role = 'member'` to the one on `list_members`. **Run it in the SQL editor** — the code change does nothing until the policy is actually replaced in the database.

To check whether the gap was ever used, before or after applying:

```sql
select id, requester_id, addressee_id, created_at
from public.friendships
where status = 'accepted' and responded_at is null;
```

Every legitimate acceptance sets `responded_at` — `acceptFriendRequest` writes both columns together — so a row that is accepted without one was inserted that way rather than accepted. Expect zero. Anything that turns up is a decision for Justin, not a cleanup to run automatically.

### 2. `restaurants` INSERT leaves the crowd columns writable

Same shape as the one above, lower severity, deliberately not fixed in that migration.

The policy checks `auth.uid() = created_by` and stops, which leaves `average_rating`, `average_tier`, and `review_count` — all trigger-maintained — settable on insert. A crafted insert could seed a new place with a five-star average and a review count it never earned. It's insert-only (there's no UPDATE policy) and `refresh_restaurant_aggregates()` corrects the values the moment anyone genuinely reviews the place, so the window is real but narrow.

The fix is column-level INSERT privileges, mirroring what `notifications` does for `read_at`:

```sql
revoke insert on public.restaurants from authenticated;
grant insert (mapkit_place_id, name, cuisine, address, latitude, longitude,
              price_level, baseline_tier, created_by)
    on public.restaurants to authenticated;
```

It was held back because `ensureRestaurantPersisted` is the hottest write path in the app — every review, like, and tasting-list add calls it first — so an incomplete column list breaks all three at once for real users. Check the grant against `RestaurantInsert` in `SupabaseDataService.swift` before applying, and verify by adding a place to a tasting list from a real device.

### 3. Confirm what the database backups actually are

There are real reviews in the database now and exactly one Supabase project. Free plans have historically had no automated backups; check what this project's plan actually retains before assuming there's a restore point.

If there isn't one, the cheap mitigation is a periodic `pg_dump` — the dataset is small enough that a scheduled dump to local storage is minutes of work and covers the case that matters (an accidental destructive migration, which is exactly what the new rules in `AGENTS.md` are there to prevent).

### 4. There is no staging environment

`SupabaseService.swift` hard-codes one project URL, so production is also the development environment. Every migration is applied straight to the database holding real users' reviews.

A second Supabase project as staging is free and would make destructive changes safe to rehearse. The cost is keeping two schemas in step and switching the URL per build configuration. Worth doing before any migration that touches existing columns.

---

## Push notification follow-ups

None of these are broken — they're the edges Phase 9 deliberately left square.

### 5. Deep link to the specific shared list

`list_added` notifications currently land on the Shared Lists index. The payload already carries `list_id`, so the data is there; what's missing is a route that can push a `SharedList` the app hasn't loaded yet, which means fetching it by id first. Same for landing on a specific friend request rather than the Friends screen.

### 6. App icon badge

Deliberately omitted — the permission asks for `.badge` so it can be switched on later without a second prompt, but nothing sets one. It would mean one extra query per push, and an icon badge is the part of notifications people resent first. The bell's unread dot covers the same need inside the app.

### 7. The inbox can't be cleared, and stops at 50

There's no delete policy on `notifications` and no pagination — read rows are pruned after 30 days by the Edge Function, which is why neither has bitten. Both are small additions if the inbox starts feeling cluttered.

### 8. No per-type notification preferences

It's all or nothing: the iOS permission, or silence. Once there are more types than the current three, a preferences screen writing to a `notification_settings` table — checked in the Edge Function before sending — is the natural next step.

### 9. `timeAgoString` is duplicated

`FriendActivity` and `AppNotification` carry identical copies. It's ten lines, and they were deliberately kept identical because the two appear one tap apart and drifting wording would read as a bug. Worth extracting to a shared `Date` extension the next time either is touched.

---

## Testing

### 10. There are no tests at all

The highest-value targets are the pure logic, which needs no network and no session:

- `TierFlaggingService` — the flagging thresholds are the app's most intricate rule (≥ 0.25 away *and* ≥ 2 named zones apart, ≥ 1 existing review) and the easiest to break silently.
- `FriendshipState.between(currentUserId:otherUserId:friendships:)` — five states, decided from a list of edges in either direction.
- `RestaurantTier` zone boundaries, which deliberately overlap.
- `AppNotification.message` and `Kind.destination`.

`MockDataService` already exists and conforms to the full protocol, so view-model tests have a backend to run against without touching Supabase.

---

## Cleanup

### 11. Core Data boilerplate is still in the target

`Persistence.swift`, `ContentView.swift`, and `Foodie.xcdatamodeld` are untouched Xcode template output with a single unused `Item` entity. `ContentView` isn't in the app's navigation and `FoodieApp` injects a managed object context no feature reads.

Removing it is tidy but not free: the `.xcdatamodeld` is a real pbxproj reference rather than a synchronized file-system group, so it needs a project-file edit. Worth doing when something else already requires opening the project settings.

---

## Operational

### 12. The legacy service-role key retires at the end of 2026

The `push` Edge Function reads `SUPABASE_SERVICE_ROLE_KEY`, which Supabase injects automatically and which is a legacy JWT key. The code already prefers `FOODIE_SERVICE_KEY` when it's set, so the migration is: create an `sb_secret_...` key, set it as that secret, done. No code change — but it does need doing before the retirement date, and nothing will remind you.

The same deadline applies to the publishable key in `SupabaseService.swift`, which is already the new-style `sb_publishable_...`, so that half is fine.

### 13. Account deletion has no export

The App Store requires the delete path, which exists and works. It doesn't require an export, and there isn't one — someone who deletes their account loses their reviews with no way to keep a copy. Worth having before the user base is anyone other than friends.
