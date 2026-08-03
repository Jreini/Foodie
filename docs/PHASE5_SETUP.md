# Phase 5 — Applying the migration (Justin's steps)

One migration, then build. No console work.

## Apply

Supabase Dashboard → **SQL Editor** → paste and run:

[`supabase/migrations/20260802000600_friends_and_group_pick.sql`](../supabase/migrations/20260802000600_friends_and_group_pick.sql)

It adds the `group_pick_candidates` function behind Roll the Dice, plus an index on `friendships.status`. The tables and policies themselves have been in place since Phase 2.

Verify:

```sql
select public.group_pick_candidates(array[]::uuid[]);
```

Runs without error and returns your own saved restaurants (or nothing, if you haven't saved any).

## Testing this needs two accounts

Friends are the first feature that can't be tested alone. Options, easiest first:

1. **Two simulators, or simulator + device.** Sign in with Apple on one and Google on the other — two different providers means two different accounts without needing a second Apple ID.
2. **Sign out and back in with the other provider** on one device. Slower, since you lose the first session, but it works for checking that requests arrive.

Once you have two accounts, note both usernames.

## What to test

**Search.** Profile → tap the **Friends** count → search a username (two characters minimum). The other account should appear with an **Add** button.

**Send, then check the other account.** The request appears under "Requests" with Accept/Decline. The sender sees "Pending" under "Sent".

**Accept.** Both friend counts go to 1.

**Then check the Feed.** This is the payoff: activity from your friend now appears in your feed. Nothing in the app filters it — the `activities` SELECT policy uses `is_friend()`, so accepting the request is literally what makes those rows visible to you. Before accepting, they're invisible at the database level.

**Roll the Dice → Group.** Select your friend and roll. If you've both saved or liked the same restaurant, that's what it should surface.

## Notes

**The database decides who can accept.** The UPDATE policy on `friendships` allows only the addressee, so the client sends the accept without re-checking who's who — and a tampered client still can't accept on someone else's behalf.

**Duplicate requests are impossible in either direction.** The unique index on `(least(requester, addressee), greatest(...))` from the initial schema means if they requested you first, your "Add" is rejected with a 23505 — which the app translates into showing **Accept** instead.

**`group_pick_candidates` is SECURITY INVOKER**, deliberately the opposite of the helper functions in migration `...000200`. Those needed DEFINER to break RLS recursion. This one runs as the caller *so that* RLS applies: the `likes` and `tasting_list` policies already limit visibility to you and your accepted friends, which means passing a stranger's id contributes nothing and no explicit friendship check is needed. Switching it to DEFINER would quietly turn it into a way to read anyone's saved restaurants.

**The feed pages by timestamp, not offset.** The feed grows at the top, so an offset would skip or repeat rows as new activity lands mid-scroll.
