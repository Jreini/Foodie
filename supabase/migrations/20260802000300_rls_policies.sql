-- =============================================================================
-- Foodie — Row Level Security
-- =============================================================================
-- The publishable key ships inside the app, so these policies ARE the security
-- boundary. Nothing else stands between a signed-in user and the data.
--
-- Two conventions applied throughout:
--   * `to authenticated` on every policy. Never rely on auth.uid() being null
--     as the only thing keeping anonymous callers out.
--   * `(select auth.uid())` rather than a bare call. Wrapping it lets the
--     planner hoist it into an initPlan and evaluate once per query instead of
--     once per row — the difference is dramatic on large tables.
--
-- A table with RLS enabled and no policy for an action denies that action.
-- That is used deliberately below: restaurants have no UPDATE policy and
-- activities have no INSERT policy, because only triggers should do those.
-- =============================================================================

alter table public.profiles     enable row level security;
alter table public.friendships  enable row level security;
alter table public.restaurants  enable row level security;
alter table public.reviews      enable row level security;
alter table public.likes        enable row level security;
alter table public.tasting_list enable row level security;
alter table public.lists        enable row level security;
alter table public.list_members enable row level security;
alter table public.list_entries enable row level security;
alter table public.activities   enable row level security;

-- -----------------------------------------------------------------------------
-- profiles
-- -----------------------------------------------------------------------------
-- Readable by any signed-in user: finding people by username is the whole
-- point of adding friends. Only name, username, bio, and avatar live here —
-- email and provider identity stay in auth.users, which is never exposed.
create policy "Profiles are viewable by authenticated users"
    on public.profiles for select
    to authenticated
    using (true);

create policy "Users can insert their own profile"
    on public.profiles for insert
    to authenticated
    with check ((select auth.uid()) = id);

create policy "Users can update their own profile"
    on public.profiles for update
    to authenticated
    using ((select auth.uid()) = id)
    with check ((select auth.uid()) = id);

-- -----------------------------------------------------------------------------
-- friendships
-- -----------------------------------------------------------------------------
create policy "Users can view friendships they are part of"
    on public.friendships for select
    to authenticated
    using ((select auth.uid()) in (requester_id, addressee_id));

create policy "Users can send friend requests as themselves"
    on public.friendships for insert
    to authenticated
    with check ((select auth.uid()) = requester_id);

-- Only the person who received the request can accept it. Without the
-- restriction to addressee_id, a requester could accept on the other's behalf.
create policy "Addressee can respond to a request"
    on public.friendships for update
    to authenticated
    using ((select auth.uid()) = addressee_id)
    with check ((select auth.uid()) = addressee_id);

create policy "Either party can remove a friendship"
    on public.friendships for delete
    to authenticated
    using ((select auth.uid()) in (requester_id, addressee_id));

-- -----------------------------------------------------------------------------
-- restaurants
-- -----------------------------------------------------------------------------
-- Shared reference data, visible to everyone signed in.
create policy "Restaurants are viewable by authenticated users"
    on public.restaurants for select
    to authenticated
    using (true);

create policy "Authenticated users can add restaurants"
    on public.restaurants for insert
    to authenticated
    with check ((select auth.uid()) = created_by);

-- No UPDATE or DELETE policy on purpose. The crowd columns are maintained by
-- refresh_restaurant_aggregates(), which is SECURITY DEFINER and therefore
-- bypasses RLS; letting clients write here would let anyone forge a rating.

-- -----------------------------------------------------------------------------
-- reviews
-- -----------------------------------------------------------------------------
-- Reviews are public within the app — a restaurant page shows everyone's.
create policy "Reviews are viewable by authenticated users"
    on public.reviews for select
    to authenticated
    using (true);

create policy "Users can write their own reviews"
    on public.reviews for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

create policy "Users can edit their own reviews"
    on public.reviews for update
    to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

create policy "Users can delete their own reviews"
    on public.reviews for delete
    to authenticated
    using ((select auth.uid()) = user_id);

-- -----------------------------------------------------------------------------
-- likes
-- -----------------------------------------------------------------------------
-- Narrower than reviews: your likes are visible to you and your friends, which
-- is all the group "Roll the Dice" pick needs.
create policy "Users can view their own and friends' likes"
    on public.likes for select
    to authenticated
    using (
        (select auth.uid()) = user_id
        or (select public.is_friend(user_id))
    );

create policy "Users can like as themselves"
    on public.likes for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

create policy "Users can remove their own likes"
    on public.likes for delete
    to authenticated
    using ((select auth.uid()) = user_id);

-- -----------------------------------------------------------------------------
-- tasting_list
-- -----------------------------------------------------------------------------
create policy "Users can view their own and friends' tasting lists"
    on public.tasting_list for select
    to authenticated
    using (
        (select auth.uid()) = user_id
        or (select public.is_friend(user_id))
    );

create policy "Users can add to their own tasting list"
    on public.tasting_list for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

create policy "Users can edit their own tasting list"
    on public.tasting_list for update
    to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

create policy "Users can remove from their own tasting list"
    on public.tasting_list for delete
    to authenticated
    using ((select auth.uid()) = user_id);

-- -----------------------------------------------------------------------------
-- lists
-- -----------------------------------------------------------------------------
create policy "Members can view their lists"
    on public.lists for select
    to authenticated
    using ((select public.is_list_member(id)));

create policy "Users can create lists they own"
    on public.lists for insert
    to authenticated
    with check ((select auth.uid()) = owner_id);

create policy "Owners can update their lists"
    on public.lists for update
    to authenticated
    using ((select auth.uid()) = owner_id)
    with check ((select auth.uid()) = owner_id);

create policy "Owners can delete their lists"
    on public.lists for delete
    to authenticated
    using ((select auth.uid()) = owner_id);

-- -----------------------------------------------------------------------------
-- list_members
-- -----------------------------------------------------------------------------
create policy "Members can see who else is on a list"
    on public.list_members for select
    to authenticated
    using ((select public.is_list_member(list_id)));

create policy "Owners can add members"
    on public.list_members for insert
    to authenticated
    with check ((select public.is_list_owner(list_id)));

-- Owners can remove anyone; anyone can remove themselves (leave the list).
create policy "Owners can remove members and members can leave"
    on public.list_members for delete
    to authenticated
    using (
        (select auth.uid()) = user_id
        or (select public.is_list_owner(list_id))
    );

-- -----------------------------------------------------------------------------
-- list_entries
-- -----------------------------------------------------------------------------
create policy "Members can view list entries"
    on public.list_entries for select
    to authenticated
    using ((select public.is_list_member(list_id)));

create policy "Members can add entries as themselves"
    on public.list_entries for insert
    to authenticated
    with check (
        (select public.is_list_member(list_id))
        and (select auth.uid()) = added_by
    );

create policy "Contributors can edit their own entries"
    on public.list_entries for update
    to authenticated
    using ((select auth.uid()) = added_by)
    with check ((select auth.uid()) = added_by);

create policy "Contributors and list owners can delete entries"
    on public.list_entries for delete
    to authenticated
    using (
        (select auth.uid()) = added_by
        or (select public.is_list_owner(list_id))
    );

-- -----------------------------------------------------------------------------
-- activities
-- -----------------------------------------------------------------------------
-- Read-only to clients. Rows come exclusively from log_activity(), so nobody
-- can fabricate an event under someone else's name.
create policy "Users can view their own and friends' activity"
    on public.activities for select
    to authenticated
    using (
        (select auth.uid()) = user_id
        or (select public.is_friend(user_id))
    );

-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------
-- The project has "automatically expose new tables" enabled, so these are
-- usually redundant. Stated explicitly so the schema also applies cleanly to a
-- project without that setting. RLS above remains the actual gate; `anon` is
-- deliberately granted nothing.
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
