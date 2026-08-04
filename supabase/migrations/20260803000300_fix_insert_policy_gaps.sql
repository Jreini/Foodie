-- =============================================================================
-- Foodie — close two INSERT policies that constrain who, but not what
-- =============================================================================
-- Both policies fixed here have the same shape: they check that the caller owns
-- the row they're inserting, and say nothing about the columns that decide what
-- the row *means*. PostgREST accepts any column a policy doesn't constrain, and
-- the publishable key ships inside the app — so "the app only ever sends the
-- default" is not a control, it's a habit of our own client.
--
-- Neither change touches existing rows. Policies govern new statements only, and
-- both new conditions are already true of everything the app has ever written.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- friendships — a request may only be created as 'pending'
-- -----------------------------------------------------------------------------
-- The old policy checked `auth.uid() = requester_id` and stopped there, which
-- left `status` free. A crafted insert with status = 'accepted' created a
-- mutual, fully-accepted friendship that the addressee never agreed to — and an
-- accepted friendship is not cosmetic. It is the key to two SELECT policies:
-- `likes` and `tasting_list` both return rows to anyone `is_friend()` approves,
-- so forging the edge reads someone's saved restaurants. It also puts their
-- activity in the attacker's feed.
--
-- Nothing legitimate inserts an accepted row. `sendFriendRequest` sends only the
-- two ids and lets the column default to 'pending', and accepting is a separate
-- UPDATE that the addressee-only policy already guards correctly.
--
-- Worth noting for anyone auditing this later: the friend-request notification
-- trigger added in Phase 9 fires only on pending rows, so a forged accept
-- arrived silently. Closing this also closes that quiet path.
drop policy if exists "Users can send friend requests as themselves" on public.friendships;

create policy "Users can send friend requests as themselves"
    on public.friendships for insert
    to authenticated
    with check (
        (select auth.uid()) = requester_id
        and status = 'pending'
    );

-- -----------------------------------------------------------------------------
-- list_members — a client may only add ordinary members
-- -----------------------------------------------------------------------------
-- `role` was unconstrained, so a list owner could add somebody as 'owner'.
--
-- This one is not a privilege escalation, and it's worth being precise about
-- why: `is_list_owner()` reads `lists.owner_id`, never `list_members.role`, so
-- the role column grants nothing. Two smaller things made it worth closing
-- anyway. It would misreport who owns a list wherever the role is displayed,
-- and `notify_list_added` skips rows with role = 'owner' to avoid announcing the
-- owner-bootstrap row — which made 'owner' a way to add someone to a list
-- without telling them.
--
-- The bootstrap insert is unaffected: `add_list_owner_as_member()` is SECURITY
-- DEFINER, so it bypasses RLS entirely and can still write its 'owner' row.
-- `addListMember` omits the column and gets the 'member' default.
drop policy if exists "Owners can add members" on public.list_members;

create policy "Owners can add members"
    on public.list_members for insert
    to authenticated
    with check (
        (select public.is_list_owner(list_id))
        and role = 'member'
    );

-- -----------------------------------------------------------------------------
-- Not fixed here, deliberately: restaurants
-- -----------------------------------------------------------------------------
-- The same gap exists on `restaurants`. Its INSERT policy checks
-- `auth.uid() = created_by`, which leaves the trigger-maintained crowd columns
-- — average_rating, average_tier, review_count — writable on insert. A crafted
-- insert could seed a brand-new place with a five-star average and a review
-- count it never earned. (Only on insert: there is no UPDATE policy, and
-- `refresh_restaurant_aggregates()` corrects the values as soon as anyone
-- actually reviews the place.)
--
-- It is left alone because the fix is column-level INSERT privileges, and
-- `ensureRestaurantPersisted` is the hottest write path in the app — every
-- review, like, and tasting-list add goes through it first. Getting the column
-- list wrong there breaks all three for real users. It deserves its own change,
-- applied and verified on its own. Recorded in docs/BACKLOG.md.
