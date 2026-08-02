-- =============================================================================
-- Foodie — functions and triggers
-- =============================================================================
-- All server-side logic lives here. There is no application server: profile
-- creation, aggregate maintenance, and feed writes are all database jobs.
--
-- Every function is SECURITY DEFINER with `set search_path = ''`:
--   * DEFINER lets the helpers read tables the calling user's RLS would hide,
--     which is what stops policies from recursing into themselves.
--   * The empty search_path forces fully-qualified names so a caller can't
--     shadow `public` with their own schema and hijack the function body.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Authorization helpers (used inside RLS policies)
-- -----------------------------------------------------------------------------

-- True when the caller and `other_id` have an accepted friendship either way.
create or replace function public.is_friend(other_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
    select exists (
        select 1
        from public.friendships f
        where f.status = 'accepted'
          and (
                (f.requester_id = auth.uid() and f.addressee_id = other_id)
             or (f.addressee_id = auth.uid() and f.requester_id = other_id)
          )
    );
$$;

-- True when the caller belongs to the list. Reading list_members from inside a
-- list_members policy would recurse forever; DEFINER breaks the cycle.
create or replace function public.is_list_member(target_list_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
    select exists (
        select 1
        from public.list_members m
        where m.list_id = target_list_id
          and m.user_id = auth.uid()
    );
$$;

-- True when the caller owns the list.
create or replace function public.is_list_owner(target_list_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
    select exists (
        select 1
        from public.lists l
        where l.id = target_list_id
          and l.owner_id = auth.uid()
    );
$$;

grant execute on function public.is_friend(uuid)      to authenticated;
grant execute on function public.is_list_member(uuid) to authenticated;
grant execute on function public.is_list_owner(uuid)  to authenticated;

-- -----------------------------------------------------------------------------
-- Profile bootstrap
-- -----------------------------------------------------------------------------

-- Every auth user gets a profile row immediately, so foreign keys to profiles
-- are always satisfiable. `username` stays null until onboarding claims one.
--
-- The name comes from whatever the provider supplied: Apple's name is written
-- to `full_name` by the app on first sign-in (it is offered exactly once),
-- while Google populates `name` on every sign-in.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (id, name)
    values (
        new.id,
        coalesce(
            new.raw_user_meta_data ->> 'full_name',
            new.raw_user_meta_data ->> 'name'
        )
    )
    on conflict (id) do nothing;

    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- Backfill: accounts created during Phase 1 testing signed up before this
-- trigger existed, so they have no profile row and would otherwise be stuck
-- with nothing to attach a username to.
insert into public.profiles (id, name)
select u.id,
       coalesce(
           u.raw_user_meta_data ->> 'full_name',
           u.raw_user_meta_data ->> 'name'
       )
from auth.users u
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- Restaurant aggregate maintenance
-- -----------------------------------------------------------------------------

-- Recomputes the stored crowd values whenever a review changes. Runs as a
-- statement-level-ish AFTER trigger per row; the restaurant row is the only
-- thing written, so this stays cheap.
create or replace function public.refresh_restaurant_aggregates()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    target_id uuid := coalesce(new.restaurant_id, old.restaurant_id);
begin
    update public.restaurants r
    set review_count   = agg.total,
        average_rating = coalesce(agg.avg_rating, 0),
        -- With no reviews left, fall back to the seeded baseline rather than
        -- leaving a stale crowd value behind.
        average_tier   = coalesce(agg.avg_tier, r.baseline_tier)
    from (
        select count(*)                        as total,
               avg(rating)::double precision   as avg_rating,
               avg(tier_placement)::double precision as avg_tier
        from public.reviews
        where restaurant_id = target_id
    ) as agg
    where r.id = target_id;

    return null;
end;
$$;

create trigger reviews_refresh_aggregates
    after insert or update or delete on public.reviews
    for each row execute function public.refresh_restaurant_aggregates();

-- Keeps reviews.updated_at honest.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger reviews_touch_updated_at
    before update on public.reviews
    for each row execute function public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Shared list bootstrap
-- -----------------------------------------------------------------------------

-- The creator has to be a member, or the list's own RLS policies would hide it
-- from them the instant it was created.
create or replace function public.add_list_owner_as_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.list_members (list_id, user_id, role)
    values (new.id, new.owner_id, 'owner')
    on conflict do nothing;

    return new;
end;
$$;

create trigger lists_add_owner_member
    after insert on public.lists
    for each row execute function public.add_list_owner_as_member();

-- -----------------------------------------------------------------------------
-- Activity feed
-- -----------------------------------------------------------------------------

-- Feed rows are written here rather than by the app so a client can never
-- forge activity for someone else. INSERT only — editing a review shouldn't
-- announce itself a second time.
create or replace function public.log_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if tg_table_name = 'reviews' then
        insert into public.activities (user_id, restaurant_id, type, review_id)
        values (new.user_id, new.restaurant_id, 'review', new.id);

    elsif tg_table_name = 'likes' then
        insert into public.activities (user_id, restaurant_id, type)
        values (new.user_id, new.restaurant_id, 'like');

    elsif tg_table_name = 'tasting_list' then
        insert into public.activities (user_id, restaurant_id, type)
        values (new.user_id, new.restaurant_id, 'tasting_add');
    end if;

    return null;
end;
$$;

create trigger reviews_log_activity
    after insert on public.reviews
    for each row execute function public.log_activity();

create trigger likes_log_activity
    after insert on public.likes
    for each row execute function public.log_activity();

create trigger tasting_list_log_activity
    after insert on public.tasting_list
    for each row execute function public.log_activity();
