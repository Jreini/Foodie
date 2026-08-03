-- =============================================================================
-- Foodie — fix: account deletion blocked by the storage guard
-- =============================================================================
-- Symptom: deleting an account failed with
--   42501 "Direct deletion from storage tables is not allowed.
--          Use the Storage API instead."
--
-- Cause: delete_current_user() tried to clear the user's photos with a plain
-- `delete from storage.objects`. Supabase guards that table against direct
-- deletes, because removing the row without removing the underlying file
-- leaves an orphaned object nobody can reach or clean up.
--
-- Fix: the function stops touching storage entirely and does only what SQL is
-- allowed to do. The client now clears the photos through the Storage API
-- first, while the user is still authenticated — which is the only moment it
-- can happen, since the delete policy matches on the owner's own id and that
-- owner is about to stop existing.
-- =============================================================================

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

    -- Storage cleanup deliberately absent: it happens client-side through the
    -- Storage API before this is called. See SupabaseDataService.deleteAccount.
    --
    -- Everything below falls out by cascade: profiles references auth.users on
    -- delete cascade, and every user-owned table references profiles the same
    -- way — reviews, likes, tasting_list, friendships, list memberships, and
    -- activities all go with it.
    delete from auth.users where id = uid;
end;
$$;

grant execute on function public.delete_current_user() to authenticated;
