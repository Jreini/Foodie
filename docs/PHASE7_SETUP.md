# Phase 7 — Applying the migration (Justin's steps)

One migration, then build. No console work — the Storage bucket is created by the SQL itself.

## Apply

Supabase Dashboard → **SQL Editor** → paste and run:

[`supabase/migrations/20260802000900_photos_and_account_deletion.sql`](../supabase/migrations/20260802000900_photos_and_account_deletion.sql)

It creates the `review-photos` bucket with per-user write policies, and adds `delete_current_user()`.

Verify:

```sql
select id, public from storage.buckets where id = 'review-photos';
```

One row, `public = true`.

## What to test

**Photos.** Open a restaurant → Review → Add Photos → pick two or three → Post. Reopen the restaurant; the photos should appear under your review.

Then check **Storage → review-photos** in the dashboard. You'll see a folder named with your user id, and the files inside should be a few hundred KB each — not the several MB the originals were. That's the client-side downscale working, and it's the difference between the free tier lasting and not.

**Account deletion.** ⚠️ **Use a throwaway account, not your main one** — this is irreversible and there's no undo.

Profile → ⋯ → Delete Account → Delete Everything. You should land back on the login screen. Then confirm in the dashboard:

```sql
select count(*) from auth.users;          -- one fewer
select count(*) from public.profiles;     -- one fewer, via cascade
```

Their reviews, likes, tasting list, friendships, list memberships, and activity should all be gone too — every user-owned table cascades from `profiles`, which cascades from `auth.users`.

## Notes

**The bucket is public-read on purpose.** Food photos attached to public reviews aren't sensitive, and a public bucket means images load from the CDN with a plain URL instead of a signed-URL round trip before every thumbnail. The trade-off is that anyone holding a URL can view the image — the same bargain nearly every photo-sharing app makes. Writes are still locked down: the INSERT policy requires the first path segment to be the uploader's own user id, so nobody can write into someone else's folder.

**Photos are downscaled before upload**, to 1600px on the long edge at JPEG 0.8. Egress is the quota Foodie would realistically outgrow first — a handful of full-resolution iPhone photos is tens of megabytes, and every *view* counts against it again.

**Photos upload before the review row is written.** A review referencing an upload that failed would render as broken images forever, so the order matters.

**Account deletion is a SQL function, not an Edge Function.** Deleting from `auth.users` needs privileges the publishable key doesn't have. The usual answer is an Edge Function holding the secret key; a `SECURITY DEFINER` function does the same job with nothing to deploy or maintain, and is arguably safer — it takes no arguments and can delete exactly one row, the caller's own. It also avoids needing the Supabase CLI, which isn't installed on this machine.

**Storage objects are deleted explicitly.** Database rows cascade from `auth.users`; storage objects don't, so the function removes the user's photo folder first.

## Push notifications

Deferred, as the plan allowed. They need APNs certificates, a database webhook or Edge Function, and device-token storage — a meaningful chunk of setup for something that isn't required to ship. Worth doing once there are enough people that friend requests aren't noticed immediately.
