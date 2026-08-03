-- =============================================================================
-- Foodie — profile pictures + friend counts on other people's profiles
-- =============================================================================
-- Three things, all needed by viewable friend profiles:
--   1. A Storage bucket for avatars, written per user and readable by everyone.
--   2. `profiles.avatar_url` renamed to `avatar_path`, because it holds a
--      storage object path rather than a URL.
--   3. `friend_count()`, because RLS deliberately hides other people's
--      friendship rows — so the client cannot count them itself.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- avatars bucket
-- -----------------------------------------------------------------------------
-- Public read, same bargain as review-photos: an avatar shows up next to every
-- review and feed card, so a signed-URL round trip before each one would cost
-- far more than the privacy it buys. Avatars are also shown to non-friends by
-- design — that's the whole point of being findable by username.
--
-- Separate from review-photos rather than a folder inside it, so "delete all my
-- review photos" and "replace my avatar" can never reach each other's files.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Writes are scoped by folder exactly as review-photos are: the first path
-- segment must be the caller's own user id. Paths look like `<user_id>/<uuid>.jpg`.
--
-- The comparison is `lower(...)` for the reason recorded in
-- 20260802001000: Swift renders UUIDs uppercase, Postgres renders
-- `auth.uid()::text` lowercase, and a case-sensitive comparison of two strings
-- that are the same UUID silently 403s every upload.
create policy "Avatars are publicly readable"
    on storage.objects for select
    to public
    using (bucket_id = 'avatars');

create policy "Users upload avatars to their own folder"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'avatars'
        and lower((storage.foldername(name))[1]) = (select auth.uid())::text
    );

-- Needed to clear the previous file when someone replaces their picture, and to
-- empty the folder before account deletion — Postgres refuses direct deletes
-- from storage.objects, so that has to happen client-side through the Storage
-- API while the owner is still signed in.
create policy "Users delete their own avatars"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'avatars'
        and lower((storage.foldername(name))[1]) = (select auth.uid())::text
    );

-- -----------------------------------------------------------------------------
-- profiles.avatar_url → avatar_path
-- -----------------------------------------------------------------------------
-- The column stores the object path (`<user_id>/<uuid>.jpg`), not a URL. Keeping
-- the CDN host out of the row means the project can move — or the bucket can go
-- private behind signed URLs — without rewriting every profile. Nothing has ever
-- written to this column, so the rename costs nothing.
alter table public.profiles rename column avatar_url to avatar_path;

comment on column public.profiles.avatar_path is
    'Object path in the public `avatars` bucket, e.g. <user_id>/<uuid>.jpg. Not a URL.';

-- -----------------------------------------------------------------------------
-- friend_count()
-- -----------------------------------------------------------------------------
-- A friend's profile shows how many friends they have, and the client cannot
-- work that out: the friendships SELECT policy only returns edges the caller is
-- part of, so counting them client-side always yields 1 for a friend and 0 for
-- a stranger.
--
-- SECURITY DEFINER for that reason, and safe to be: it returns a single integer
-- and never exposes *who* those friends are. Anything richer belongs behind a
-- friendship check.
create or replace function public.friend_count(target uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
    select count(*)::integer
    from public.friendships f
    where f.status = 'accepted'
      and (f.requester_id = target or f.addressee_id = target);
$$;

-- Functions are executable by PUBLIC unless told otherwise, and the publishable
-- key can reach RPCs without a session. Revoke first so this needs a signed-in
-- caller like every policy in the schema does.
revoke execute on function public.friend_count(uuid) from public;
grant execute on function public.friend_count(uuid) to authenticated;
