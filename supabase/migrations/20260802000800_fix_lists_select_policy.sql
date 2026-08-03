-- =============================================================================
-- Foodie — fix: creating a shared list was rejected by RLS
-- =============================================================================
-- Symptom: creating a list failed with
--   42501 "new row violates row-level security policy for table \"lists\""
-- even though the INSERT policy (owner_id = auth.uid()) was satisfied.
--
-- Cause: the insert asks for the created row back (PostgREST sends
-- `Prefer: return=representation`, i.e. INSERT ... RETURNING), and Postgres
-- applies the SELECT policy to a returned row. The old SELECT policy was
-- membership-only:
--
--     using ((select public.is_list_member(id)))
--
-- and membership is granted by add_list_owner_as_member(), an AFTER INSERT
-- trigger. AFTER triggers fire at the end of the statement, after RETURNING has
-- already been evaluated — so at the moment the policy ran, the owner was not
-- yet a member of their own brand-new list, and the whole INSERT was rejected.
-- (Same shape as supabase/supabase#7289.)
--
-- Fix: let owners see their lists directly rather than only through membership.
-- That closes the window and is the more correct rule anyway — an owner should
-- never be able to lose sight of their own list because a membership row went
-- missing.
--
-- Note this is the only table with the problem: every other insert that asks
-- for its row back is covered by a SELECT policy that passes immediately
-- (restaurants/reviews use `true`, tasting_list and profiles match on the
-- caller's own id, and list_entries requires a membership the inserter already
-- had).
-- =============================================================================

drop policy if exists "Members can view their lists" on public.lists;

create policy "Owners and members can view lists"
    on public.lists for select
    to authenticated
    using (
        (select auth.uid()) = owner_id
        or (select public.is_list_member(id))
    );
