-- =============================================================================
-- Foodie — group pick support
-- =============================================================================
-- The friendships table and its policies have existed since the initial schema.
-- This adds the one piece of server-side logic the friend features need: the
-- overlap query behind "Roll the Dice" for a group.
-- =============================================================================

-- Restaurants the caller and the named friends are collectively interested in,
-- ranked by how many of them are interested.
--
-- SECURITY INVOKER on purpose — the opposite of the helper functions in
-- 20260802000200. Those needed DEFINER to break policy recursion. This one runs
-- as the caller precisely so RLS applies: the likes and tasting_list policies
-- already expose only the caller's own rows and their accepted friends' rows.
-- That means passing in a stranger's id yields nothing, and no explicit
-- friendship check is needed here. Switching this to DEFINER would silently
-- turn it into a way to read anyone's saved restaurants.
create or replace function public.group_pick_candidates(friend_ids uuid[])
returns table (restaurant_id uuid, votes bigint)
language sql
stable
security invoker
set search_path = ''
as $$
    with people as (
        select auth.uid() as user_id
        union
        select unnest(friend_ids)
    ),
    interests as (
        -- A like and a tasting-list entry both count as "interested", and
        -- UNION (not UNION ALL) keeps one person from voting twice for the
        -- same restaurant by doing both.
        select l.user_id, l.restaurant_id
        from public.likes l
        join people p on p.user_id = l.user_id

        union

        select t.user_id, t.restaurant_id
        from public.tasting_list t
        join people p on p.user_id = t.user_id
    )
    select i.restaurant_id, count(distinct i.user_id) as votes
    from interests i
    group by i.restaurant_id
    order by votes desc, i.restaurant_id;
$$;

grant execute on function public.group_pick_candidates(uuid[]) to authenticated;

-- Feed pagination walks backwards through time, and the friend list is read on
-- every friends screen. Both are covered by existing indexes
-- (activities_user_created_idx, friendships_requester_idx/addressee_idx); this
-- adds the one for filtering pending requests by status.
create index if not exists friendships_status_idx
    on public.friendships (status);
