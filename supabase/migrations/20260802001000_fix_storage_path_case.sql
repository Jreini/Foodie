-- =============================================================================
-- Foodie — fix: photo uploads rejected by storage RLS
-- =============================================================================
-- Symptom: uploading a review photo failed with
--   403 "new row violates row-level security policy"
--
-- Cause: a case mismatch between the two ends of the comparison. Swift's
-- `UUID.uuidString` renders uppercase ("A1B2C3D4-…"), while Postgres renders
-- `auth.uid()::text` lowercase ("a1b2c3d4-…"). The upload path therefore began
-- with an uppercase folder name that could never equal the lowercase text on
-- the other side, so the policy rejected every upload.
--
-- Fixed on the client too (paths are now built lowercase), but the comparison
-- is corrected here as well because case-insensitive is simply the right rule:
-- two UUID strings differing only in case *are the same UUID*, so a
-- case-sensitive text comparison was always wrong, and this stops the same slip
-- from silently 403ing again.
--
-- `lower()` rather than a `::uuid` cast on purpose — a cast would raise on any
-- path whose first segment isn't a valid UUID, turning a clean authorization
-- failure into a 500.
-- =============================================================================

drop policy if exists "Users upload review photos to their own folder" on storage.objects;
drop policy if exists "Users delete their own review photos" on storage.objects;

create policy "Users upload review photos to their own folder"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'review-photos'
        and lower((storage.foldername(name))[1]) = (select auth.uid())::text
    );

create policy "Users delete their own review photos"
    on storage.objects for delete
    to authenticated
    using (
        bucket_id = 'review-photos'
        and lower((storage.foldername(name))[1]) = (select auth.uid())::text
    );

-- Same mismatch would have left photos behind on account deletion: the folder
-- was never matched, so the storage objects survived a deleted user.
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
      and lower((storage.foldername(name))[1]) = uid::text;

    -- Cascades through profiles to reviews, likes, tasting_list, friendships,
    -- list memberships, and activities.
    delete from auth.users where id = uid;
end;
$$;

grant execute on function public.delete_current_user() to authenticated;
