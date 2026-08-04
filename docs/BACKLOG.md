# Backlog

Outstanding work, roughly in the order it's worth doing. Open *bugs* live in [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) — this file is for work that hasn't been started.

Nothing here is required to ship. The app is feature-complete through Phase 9 and on TestFlight.

---

## Do first — real user data is now at stake

### 1. `friendships` INSERT policy lets someone forge an accepted friendship

**Security. This is the one item on this page that is actively exploitable.**

The policy in `20260802000300_rls_policies.sql` constrains who is sending a request but not what state they send it in:

```sql
create policy "Users can send friend requests as themselves"
    on public.friendships for insert
    to authenticated
    with check ((select auth.uid()) = requester_id);
```

The publishable key ships in the app and PostgREST accepts any column a policy doesn't constrain, so a crafted request can insert a row with `status = 'accepted'` and create a mutual friendship the other person never agreed to. That hands the attacker whatever an accepted friendship unlocks: the victim's `likes` and `tasting_list` — whose SELECT policies both call `is_friend()` — and their activity in the feed.

The fix is one condition: `and status = 'pending'`. Nothing legitimate inserts an accepted row; `SupabaseDataService.sendFriendRequest` relies on the schema default, and accepting is already correctly restricted to the addressee by the separate UPDATE policy.

Phase 9 made it quieter, which is worth knowing: `notify_friend_request` only fires on pending rows, so a forged accept now arrives with no notification at all.

**While you're in there,** audit every other INSERT policy for the same shape — ownership constrained, a state or role column left free. `list_members` is the one to check: its policy should not let an owner insert `role = 'owner'` for somebody else.

### 2. Confirm what the database backups actually are

There are real reviews in the database now and exactly one Supabase project. Free plans have historically had no automated backups; check what this project's plan actually retains before assuming there's a restore point.

If there isn't one, the cheap mitigation is a periodic `pg_dump` — the dataset is small enough that a scheduled dump to local storage is minutes of work and covers the case that matters (an accidental destructive migration, which is exactly what the new rules in `AGENTS.md` are there to prevent).

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
