# Phase 8 — Profile pictures and friend profiles (Justin's steps)

One migration, then build. No console work — the Storage bucket is created by the SQL itself.

## Apply

Supabase Dashboard → **SQL Editor** → paste and run:

[`supabase/migrations/20260803000100_avatars_and_friend_counts.sql`](../supabase/migrations/20260803000100_avatars_and_friend_counts.sql) — creates the `avatars` bucket with per-user write policies, renames `profiles.avatar_url` to `avatar_path`, and adds `friend_count()`.

⚠️ **Run this before building, or the new screens fail in two quiet ways.** Existing profiles still load — a missing `avatar_path` key decodes as "no picture" rather than an error — but saving a picture returns `400 column "avatar_path" does not exist`, and opening anyone's profile shows *Something went wrong* because the `friend_count` RPC isn't there to call.

Verify:

```sql
select id, public from storage.buckets where id = 'avatars';   -- one row, public = true
select avatar_path from public.profiles limit 1;               -- column exists, null
select public.friend_count(auth.uid());                        -- 0 in the SQL editor, which has no session
```

## What to test

**Upload a picture.** Profile → Edit → tap the avatar → **Choose from Library** → pick one → **Save**. It should appear immediately in the header, and then everywhere you show up: the feed, the friends list, your reviews on a restaurant page.

**Take one.** Same flow, **Take Photo**. Needs a real device — the option is hidden in the Simulator, which has no camera. iOS will ask for camera permission the first time.

**Replace it, then remove it.** Upload a second picture and check **Storage → avatars → `<your user id>`** in the dashboard: there should be exactly **one** file in the folder, not two. The old one is deleted after the row stops pointing at it. Then Edit → tap the avatar → **Remove Photo** → Save; the folder should be empty and the header back to the orange placeholder.

**Friend profiles.** Needs two accounts, like every friend feature.

- Feed → the **person icon in the top right** → your friends list. A red dot on that icon means someone is waiting on a request.
- Tap a friend → their profile. Reviews, Liked, and Tasting List should all have real content, and the friend count should match what they see on their own profile.
- Tap the reviewer's name on any review, on any restaurant page, and on any feed card — all three should land on the same screen.
- From the friend's profile: **Friends ▾ → Remove Friend**. The two locked sections should close the moment it reloads.
- Then find them again by username and send a request; the profile should read **Request Sent**, and on their device **Accept Request**.

**A stranger's profile.** Review a restaurant from a second account that isn't your friend, then tap that reviewer's name from your own. You should see their picture, bio, review count, friend count, and their reviews — and Liked / Tasting List should say *shares this with friends only* rather than looking empty. The tasting-list stat shows `—`, not `0`.

That last part is not the app being polite. Try it in the SQL editor as that user and you'll get zero rows back: the `likes` and `tasting_list` SELECT policies only return rows to the owner and their accepted friends. The screen is reporting what the database will withhold, so an empty section can't be mistaken for an empty list.

## Notes

**The `avatars` bucket is public-read, like `review-photos`.** A profile picture appears next to every review and every feed row; a signed-URL round trip per thumbnail would cost far more than the privacy it buys, and avatars are meant to be visible to non-friends anyway — that's what makes someone recognisable when they turn up in a username search.

It's a **separate bucket** rather than a folder inside `review-photos`, so "clear my review photos" and "replace my avatar" can never reach each other's files.

**Avatars are downscaled to 512px at JPEG 0.85** — smaller than review photos, because nothing displays one larger than about 80pt. On a 3x screen that's 240px of actual pixels, so 512 is already generous.

**Every upload gets a fresh UUID filename**, which is what lets the response carry a one-year cache header. A replaced avatar is a new path, so nothing has to be invalidated — the old URL simply stops being referenced. The previous file is deleted right after the profile row stops pointing at it (storage doesn't cascade, and skipping this would leave one dead file per edit).

**The column is `avatar_path`, not `avatar_url`.** It holds `<user_id>/<uuid>.jpg`. Keeping the CDN host out of the row means the project could move, or the bucket could go private behind signed URLs, without rewriting every profile.

**`friend_count()` is `SECURITY DEFINER`, and that's not a lapse.** The `friendships` SELECT policy returns only edges the caller is part of — by design, so nobody can enumerate someone else's social graph. The side effect is that counting a friend's friends client-side always returns 1. The function bypasses RLS to return a single integer and nothing else; *who* those friends are stays hidden. Anything richer than a count belongs behind a friendship check.

It's also `revoke`d from `PUBLIC` before being granted to `authenticated`. Functions are executable by everyone unless told otherwise, and the publishable key can reach RPCs without a session.

**Account deletion now clears two folders.** Same client-side Storage API pass as before, once per bucket, still best effort — see the Phase 7 notes for why it can't be done in SQL.

## Known gap

Nothing invalidates a cached avatar if you somehow write the *same* path twice. Nothing does, because the filename is a fresh UUID every time — but if a future change ever reuses a path, the one-year cache header will make it look like the upload silently failed.
