-- =============================================================================
-- Foodie — review photos + account deletion
-- =============================================================================
-- Two unrelated things that both need server-side setup:
--   1. A Storage bucket for review photos, with write access scoped per user.
--   2. Account deletion, which the App Store requires of any app with accounts.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Storage bucket
-- -----------------------------------------------------------------------------
-- Public read. Food photos attached to public reviews aren't sensitive, and a
-- public bucket means images load from the CDN with a plain URL — no signed-URL
-- round trip before every thumbnail. The trade-off is that anyone holding a URL
-- can view it, which is the same bargain almost every photo-sharing app makes.
insert into storage.buckets (id, name, public)
values ('review-photos', 'review-photos', true)
on conflict (id) do nothing;

-- Writes are scoped by folder: the first path segment must be the caller's own
-- user id, so nobody can write into (or delete from) someone else's folder.
-- Paths look like `<user_id>/<uuid>.jpg`.
create policy "Review photos are publicly readable"
    on storage.objects for select
    to public
    using (bucket_id = 'review-photos');

create policy "Users upload review photos to their own folder"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'review-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

create policy "Users delete their own review photos"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'review-photos'
        and (storage.foldername(name))[1] = (select auth.uid())::text
    );

-- -----------------------------------------------------------------------------
-- Account deletion
-- -----------------------------------------------------------------------------
-- Deleting from auth.users needs privileges the app's publishable key doesn't
-- have. The usual answer is an Edge Function holding the secret key; a
-- SECURITY DEFINER function does the same job without deploying or maintaining
-- one, and is arguably safer: it can delete exactly one row — the caller's own —
-- and takes no arguments, so there's nothing to tamper with.
--
-- Everything else falls out by cascade: profiles references auth.users on
-- delete cascade, and every other user-owned table references profiles the
-- same way. Storage objects don't cascade, so they're removed explicitly first.
create or replace function public.delete_current_user()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    uid uuid := auth.uid();
begin
    if uid is null then
        raise exception 'Not signed in';
    end if;

    delete from storage.objects
    where bucket_id = 'review-photos'
      and (storage.foldername(name))[1] = uid::text;

    -- Cascades through profiles to reviews, likes, tasting_list, friendships,
    -- list memberships, and activities.
    delete from auth.users where id = uid;
end;
$$;

grant execute on function public.delete_current_user() to authenticated;
