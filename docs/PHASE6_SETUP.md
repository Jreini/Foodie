# Phase 6 — Applying the migration (Justin's steps)

One migration, then build. No console work — Realtime is included in the free tier and needs no separate setup beyond adding the table to the publication, which the migration does.

## Apply

Supabase Dashboard → **SQL Editor** → paste and run:

[`supabase/migrations/20260802000700_shared_lists_realtime.sql`](../supabase/migrations/20260802000700_shared_lists_realtime.sql)

It adds `list_entries` to the `supabase_realtime` publication and sets its replica identity to FULL. The lists tables and policies have existed since Phase 2.

Verify:

```sql
select tablename from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public';
```

`list_entries` should be listed.

## Where it lives

**Decide tab → Shared Lists.** Create a list, open it, and use the ⋯ menu to add restaurants or manage members.

## What to test

**Solo first.** Create a list, add a couple of places, add notes. Confirm it survives a force-quit.

**Then the live part, which needs two devices** (same setup as Phase 5 — Apple on one, Google on the other, and the two accounts already friends):

1. Owner creates a list, opens ⋯ → Members → invites the friend.
2. Friend opens Decide → Shared Lists. The list is there.
3. **Both open the list and leave it on screen.**
4. One adds a restaurant.
5. It appears on the other's screen within a second or so, with a brief "Updated" flash in the section header.

That's the whole point of this phase. If step 5 doesn't happen but a pull-to-refresh shows the row, Realtime isn't connected — check the publication query above.

## Notes

**Realtime honours RLS.** A client only receives changes to rows it could have read, so the members-only SELECT policy on `list_entries` is what keeps these broadcasts private. Someone who isn't on the list gets nothing, not even a notification that something changed.

**Only the owner can invite.** The INSERT policy on `list_members` allows only the list owner, so the Members sheet hides the invite section for everyone else — and a tampered client still gets rejected server-side.

**Changes trigger a refetch, not a patch.** A Realtime payload could be an insert, an update, or a delete. Refetching the list's entries handles all three identically and can't drift out of sync; a list holds a few dozen rows at most, so the query is cheap. Decoding three payload shapes to avoid one small query would be the wrong trade.

**Replica identity FULL matters.** Without it a DELETE broadcast carries only the primary key, so a client can't tell which list the removed row belonged to and the server-side filter wouldn't match it.

## The tasting list stays separate

Phase 6 in the plan left this open: fold the personal Tasting List into "a list with one member", or keep it as its own table.

**Kept separate.** It's already wired through the app from Phase 3, it works, and merging would be pure churn — a user would see no difference. The two also mean genuinely different things: the tasting list is a private queue, a shared list is a collaboration. `tasting_list` stays as it is.
